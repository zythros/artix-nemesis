#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Menu      : Configure Snapper for BTRFS snapshots
# Group     : optional
# Purpose   : Install and configure Snapper for BTRFS snapshots (can be run standalone)
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

script_start "Setting up Snapper (BTRFS snapshots)"

##################################################################################################################################
# Check if root filesystem is BTRFS, and for GRUB
##################################################################################################################################

ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)
[ "$ROOT_FSTYPE" = "btrfs" ] || script_skip "Root filesystem is $ROOT_FSTYPE, not BTRFS — Snapper requires BTRFS."
ok "BTRFS detected on root filesystem"

# Check for GRUB bootloader (use sudo - /boot/grub may have restricted permissions)
if ! sudo test -d /boot/grub && ! sudo test -f /boot/grub/grub.cfg; then
    script_skip "GRUB bootloader not detected — snapper/grub-btrfs requires GRUB.
grub-btrfs snapshot boot menu integration is not available on systemd-boot or other bootloaders."
fi
ok "GRUB bootloader detected"

##################################################################################################################################
# Install snapper and related packages
# snapper-openrc provides OpenRC init scripts for snapper-timeline and snapper-cleanup
##################################################################################################################################

section "Packages"
pkg_sync
ensure_pkgs snapper snap-pac grub-btrfs inotify-tools \
    || die "snapper packages missing — check your internet connection and pacman configuration"

# Official repos only (Artix world repo) — no AUR/yay fallback.
# Non-fatal: snapper still works for manual snapshots and snap-pac hooks without it.
ensure_pkgs --optional snapper-openrc \
    || warn "without snapper-openrc, automatic timeline snapshots and cleanup won't run (AUR: paru -S snapper-openrc)"

##################################################################################################################################
# Check if snapper root config already exists
##################################################################################################################################

section "Snapper config"

if snapper -c root list &>/dev/null; then
    ok "Snapper 'root' config already exists"
else
    echo "Creating snapper configuration for root..."

    # Snapper creates /.snapshots directory/subvolume
    if findmnt /.snapshots &>/dev/null; then
        ok "/.snapshots is already mounted (likely @snapshots subvolume)"
    elif [ -d "/.snapshots" ]; then
        # Directory exists but not mounted - might be from failed setup
        echo "Removing existing /.snapshots directory..."
        sudo rm -rf /.snapshots
    fi

    sudo snapper -c root create-config / \
        || die "Failed to create snapper config — you may need to set up the /.snapshots subvolume manually"
    ok "Snapper 'root' config created successfully"
fi

##################################################################################################################################
# Configure snapper settings
##################################################################################################################################

SNAPPER_CONFIG="/etc/snapper/configs/root"

if [ -f "$SNAPPER_CONFIG" ]; then
    echo "Configuring snapper settings..."

    # Allow user to use snapper (add to ALLOW_USERS)
    CURRENT_USER=$(whoami)
    if ! sudo grep -q "ALLOW_USERS=\".*$CURRENT_USER" "$SNAPPER_CONFIG"; then
        sudo sed -i "s/ALLOW_USERS=\"\"/ALLOW_USERS=\"$CURRENT_USER\"/" "$SNAPPER_CONFIG"
        ok "Added $CURRENT_USER to ALLOW_USERS"
    fi

    # Set reasonable snapshot limits (prevent disk filling up)
    # Timeline snapshots: keep fewer old ones
    sudo sed -i 's/TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="5"/' "$SNAPPER_CONFIG"
    sudo sed -i 's/TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/' "$SNAPPER_CONFIG"
    sudo sed -i 's/TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="0"/' "$SNAPPER_CONFIG"
    sudo sed -i 's/TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="0"/' "$SNAPPER_CONFIG"
    sudo sed -i 's/TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' "$SNAPPER_CONFIG"

    # Number cleanup: keep last 5-10 snapshots from snap-pac
    sudo sed -i 's/NUMBER_LIMIT=.*/NUMBER_LIMIT="10"/' "$SNAPPER_CONFIG"
    sudo sed -i 's/NUMBER_LIMIT_IMPORTANT=.*/NUMBER_LIMIT_IMPORTANT="5"/' "$SNAPPER_CONFIG"

    ok "Configured snapshot retention limits"
else
    err "$SNAPPER_CONFIG missing — retention limits not set"
fi

##################################################################################################################################
# Enable OpenRC services for automatic snapshots
# snapper-openrc provides: snapper-timeline (hourly snapshots) and snapper-cleanup (cleanup old snapshots)
# grub-btrfsd watches for new snapshots and regenerates the grub menu
##################################################################################################################################

section "Services"

# Optional extras: failures are warnings, snapper itself works without them
if pacman -Q snapper-openrc &>/dev/null; then
    enable_service snapper-timeline || warn "hourly snapshots won't run automatically"
    enable_service snapper-cleanup  || warn "old snapshots won't be cleaned automatically"
fi

# Only attempt if the OpenRC service file was installed by grub-btrfs or grub-btrfs-openrc
if [ -f /etc/init.d/grub-btrfsd ]; then
    enable_service grub-btrfsd || warn "snapshots won't auto-update in the GRUB menu"
else
    warn "grub-btrfsd: init script not found — snapshots won't auto-update in the GRUB menu"
fi

##################################################################################################################################
# snapper-rollback (full system rollback) — AUR-only, not installed automatically
##################################################################################################################################

_c setaf 3
echo
echo "snapper-rollback is AUR-only and is not installed automatically (no AUR/yay dependency by design)."
echo "GRUB-menu snapshot boot + manual snapper commands above still work without it."
echo "Install manually later if you choose to: paru -S snapper-rollback  (or yay -S snapper-rollback)"
_c sgr0

##################################################################################################################################
# Configure snapper-rollback for this system's layout
##################################################################################################################################

if command -v snapper-rollback &>/dev/null; then
    _c setaf 3
    echo "Configuring snapper-rollback..."
    _c sgr0

    # Create btrfsroot mount point
    sudo mkdir -p /btrfsroot

    # Detect root subvolume name and device
    ROOT_SUBVOL=$(findmnt -n -o SOURCE / | sed 's/.*\[\/\([^]]*\)\].*/\1/')
    ROOT_DEV=$(findmnt -n -o SOURCE / | sed 's/\[.*//')

    # Write config
    sudo tee /etc/snapper-rollback.conf > /dev/null << EOF
[root]
subvol_main = $ROOT_SUBVOL
subvol_snapshots = $ROOT_SUBVOL/.snapshots
mountpoint = /btrfsroot
dev = $ROOT_DEV
EOF

    ok "snapper-rollback configured for subvolume: $ROOT_SUBVOL"
fi

##################################################################################################################################
# Create initial snapshot + regenerate GRUB config to include snapshots
##################################################################################################################################

section "Initial snapshot"
sudo snapper -c root create --description "Initial snapshot after snapper setup" \
    || err "could not create the initial snapshot"

echo "Regenerating GRUB config to include snapshots..."
sudo grub-mkconfig -o /boot/grub/grub.cfg \
    || warn "grub-mkconfig failed (run manually: sudo grub-mkconfig -o /boot/grub/grub.cfg)"

##################################################################################################################################
# Summary
##################################################################################################################################

script_done
echo "Snapper BTRFS snapshot system installed:"
echo
echo "Packages installed:"
echo "  - snapper          : Snapshot management tool"
echo "  - snap-pac         : Auto snapshots before/after pacman operations"
echo "  - grub-btrfs       : Adds snapshots to GRUB boot menu"
echo "  - snapper-openrc   : OpenRC init scripts for snapper services"
echo "  - snapper-rollback : NOT installed (AUR-only, skipped by design — see warnings below)"
echo
echo "Configuration:"
echo "  - Config file: /etc/snapper/configs/root"
echo "  - Snapshots:   /.snapshots/"
echo
echo "Retention limits:"
echo "  - Hourly:  5"
echo "  - Daily:   7"
echo "  - Weekly:  0 (disabled)"
echo "  - Monthly: 0 (disabled)"
echo "  - Yearly:  0 (disabled)"
echo "  - Number (snap-pac): 10"
echo
echo "OpenRC services enabled:"
echo "  - snapper-timeline : Hourly snapshots"
echo "  - snapper-cleanup  : Automatic cleanup"
echo "  - grub-btrfsd      : Updates GRUB on new snapshots"
echo
echo "Usage:"
echo "  snapper -c root list              : List all snapshots"
echo "  snapper -c root create -d \"desc\"  : Create manual snapshot"
echo "  snapper -c root delete <num>      : Delete snapshot"
echo "  snapper -c root status 1..0       : Compare snapshot 1 to current"
echo "  snapper -c root undochange 2..3   : Revert changes between snapshots"
echo
echo "Full system rollback (snapper-rollback):"
echo "  sudo snapper-rollback --dry-run 1 : Preview rollback to snapshot 1"
echo "  echo CONFIRM | sudo snapper-rollback 1 : Rollback to snapshot 1"
echo "  (Reboot required after rollback)"
echo
echo "Rollback from GRUB:"
echo "  1. Reboot and select snapshot from GRUB submenu"
echo "  2. Boot into snapshot (read-only)"
echo "  3. Use snapper-rollback to make permanent"
echo
