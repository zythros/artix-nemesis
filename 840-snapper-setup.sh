#!/bin/bash
#set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install and configure Snapper for BTRFS snapshots (can be run standalone)
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

installed_dir=$(dirname $(readlink -f $(basename `pwd`)))

##################################################################################################################################

if [ "$DEBUG" = true ]; then
    echo
    echo "------------------------------------------------------------"
    echo "Running $(basename $0)"
    echo "------------------------------------------------------------"
    echo
    read -n 1 -s -r -p "Debug mode is on. Press any key to continue..."
    echo
fi

##################################################################################################################################

echo
tput setaf 2
echo "########################################################################"
echo "################### Setting up Snapper (BTRFS snapshots)"
echo "########################################################################"
tput sgr0
echo

artix_pacman_nohook_setup

##################################################################################################################################
# Check if root filesystem is BTRFS
##################################################################################################################################

ROOT_FSTYPE=$(findmnt -n -o FSTYPE /)

if [ "$ROOT_FSTYPE" != "btrfs" ]; then
    tput setaf 3
    echo "Root filesystem is $ROOT_FSTYPE, not BTRFS"
    echo "Snapper requires BTRFS. Skipping installation."
    tput sgr0
    echo
    exit 0
fi

tput setaf 2
echo "BTRFS detected on root filesystem"
tput sgr0
echo

##################################################################################################################################
# Track warnings for final summary
##################################################################################################################################

WARNINGS=()

##################################################################################################################################
# Check for required tools
##################################################################################################################################

# Check for pacman (Arch-based system)
if ! command -v pacman &>/dev/null; then
    tput setaf 1
    echo "ERROR: pacman not found"
    echo "This script requires an Arch-based system (Arch, Manjaro, EndeavourOS, ArcoLinux, etc.)"
    tput sgr0
    exit 1
fi

# Check for GRUB bootloader (use sudo - /boot/grub may have restricted permissions)
if ! sudo test -d /boot/grub && ! sudo test -f /boot/grub/grub.cfg; then
    tput setaf 3
    echo "SKIP: GRUB bootloader not detected — snapper/grub-btrfs requires GRUB."
    echo "      grub-btrfs snapshot boot menu integration is not available on systemd-boot"
    echo "      or other bootloaders. Skipping this script."
    tput sgr0
    exit 0
fi

tput setaf 2
echo "GRUB bootloader detected"
tput sgr0

##################################################################################################################################
# Install snapper and related packages
# snapper-openrc provides OpenRC init scripts for snapper-timeline and snapper-cleanup
##################################################################################################################################

SNAPPER_PACKAGES="snapper snap-pac grub-btrfs inotify-tools"

tput setaf 3
echo "Syncing package databases..."
tput sgr0
sudo pacman --config "$NOHOOK_CONF" -Sy

tput setaf 3
echo "Installing snapper packages..."
tput sgr0

if ! sudo pacman --config "$NOHOOK_CONF" -S --noconfirm --needed $SNAPPER_PACKAGES; then
    tput setaf 1
    echo "ERROR: Failed to install snapper packages"
    echo "Check your internet connection and pacman configuration."
    tput sgr0
    exit 1
fi

# snapper-openrc provides OpenRC init scripts for snapper-timeline and snapper-cleanup.
# Try pacman first (Artix world repo), fall back to yay (Chaotic AUR / AUR).
# Non-fatal: snapper still works for manual snapshots and snap-pac hooks without it.
if ! pacman -Q snapper-openrc &>/dev/null; then
    tput setaf 3
    echo "Installing snapper-openrc (OpenRC timeline/cleanup services)..."
    tput sgr0
    if ! pkg_install snapper-openrc; then
        tput setaf 3
        echo "WARNING: snapper-openrc not found — automatic timeline snapshots won't run."
        echo "         Install manually if needed: yay -S snapper-openrc"
        tput sgr0
        WARNINGS+=("snapper-openrc: not found in repos — automatic timeline snapshots disabled")
    fi
fi

##################################################################################################################################
# Check if snapper root config already exists
##################################################################################################################################

if snapper -c root list &>/dev/null 2>&1; then
    tput setaf 2
    echo "Snapper 'root' config already exists"
    tput sgr0
else
    ##############################################################################################################################
    # Create snapper config for root
    ##############################################################################################################################

    tput setaf 3
    echo "Creating snapper configuration for root..."
    tput sgr0

    # Snapper creates /.snapshots directory/subvolume
    # On Arch-based systems with proper BTRFS layout, we need to handle this carefully

    # Check if /.snapshots exists as a subvolume mount
    if findmnt /.snapshots &>/dev/null; then
        tput setaf 2
        echo "/.snapshots is already mounted (likely @snapshots subvolume)"
        tput sgr0
    elif [ -d "/.snapshots" ]; then
        # Directory exists but not mounted - might be from failed setup
        tput setaf 3
        echo "Removing existing /.snapshots directory..."
        tput sgr0
        sudo rm -rf /.snapshots
    fi

    # Create the snapper config
    sudo snapper -c root create-config /

    if [ $? -eq 0 ]; then
        tput setaf 2
        echo "Snapper 'root' config created successfully"
        tput sgr0
    else
        tput setaf 1
        echo "ERROR: Failed to create snapper config"
        echo "You may need to set up /.snapshots subvolume manually"
        tput sgr0
        exit 1
    fi
fi

##################################################################################################################################
# Configure snapper settings
##################################################################################################################################

SNAPPER_CONFIG="/etc/snapper/configs/root"

if [ -f "$SNAPPER_CONFIG" ]; then
    tput setaf 3
    echo "Configuring snapper settings..."
    tput sgr0

    # Allow user to use snapper (add to ALLOW_USERS)
    CURRENT_USER=$(whoami)
    if ! grep -q "ALLOW_USERS=\".*$CURRENT_USER" "$SNAPPER_CONFIG"; then
        sudo sed -i "s/ALLOW_USERS=\"\"/ALLOW_USERS=\"$CURRENT_USER\"/" "$SNAPPER_CONFIG"
        tput setaf 2
        echo "Added $CURRENT_USER to ALLOW_USERS"
        tput sgr0
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

    tput setaf 2
    echo "Configured snapshot retention limits"
    tput sgr0
fi

##################################################################################################################################
# Enable OpenRC services for automatic snapshots
# snapper-openrc provides: snapper-timeline (hourly snapshots) and snapper-cleanup (cleanup old snapshots)
##################################################################################################################################

tput setaf 3
echo "Enabling snapper OpenRC services..."
tput sgr0

# Timeline service: takes hourly snapshots
if sudo rc-update add snapper-timeline default && sudo rc-service snapper-timeline start; then
    tput setaf 2
    echo "snapper-timeline enabled and started"
    tput sgr0
else
    WARNINGS+=("snapper-timeline: Failed to enable (hourly snapshots won't run automatically)")
fi

# Cleanup service: removes old snapshots based on limits
if sudo rc-update add snapper-cleanup default && sudo rc-service snapper-cleanup start; then
    tput setaf 2
    echo "snapper-cleanup enabled and started"
    tput sgr0
else
    WARNINGS+=("snapper-cleanup: Failed to enable (old snapshots won't be cleaned automatically)")
fi

##################################################################################################################################
# Enable grub-btrfs daemon for boot menu integration
##################################################################################################################################

tput setaf 3
echo "Enabling grub-btrfsd service..."
tput sgr0

# grub-btrfsd watches for new snapshots and regenerates grub menu
if sudo rc-update add grub-btrfsd default && sudo rc-service grub-btrfsd start; then
    tput setaf 2
    echo "grub-btrfsd enabled and started (snapshots will appear in GRUB menu)"
    tput sgr0
else
    tput setaf 3
    echo "WARNING: Failed to enable grub-btrfsd service"
    tput sgr0
    WARNINGS+=("grub-btrfsd: Failed to enable (snapshots won't auto-update in GRUB menu)")
fi

##################################################################################################################################
# Install snapper-rollback from AUR (proper rollback for Arch)
##################################################################################################################################

tput setaf 3
echo "Installing snapper-rollback from AUR..."
tput sgr0

# Check for AUR helper
if command -v paru &>/dev/null; then
    if ! paru -S --noconfirm --needed snapper-rollback; then
        tput setaf 3
        echo "WARNING: Failed to install snapper-rollback from AUR"
        tput sgr0
        WARNINGS+=("snapper-rollback: AUR installation failed (install manually: paru -S snapper-rollback)")
    fi
elif command -v yay &>/dev/null; then
    if ! yay -S --noconfirm --needed snapper-rollback; then
        tput setaf 3
        echo "WARNING: Failed to install snapper-rollback from AUR"
        tput sgr0
        WARNINGS+=("snapper-rollback: AUR installation failed (install manually: yay -S snapper-rollback)")
    fi
else
    tput setaf 3
    echo "WARNING: No AUR helper found (paru/yay). Skipping snapper-rollback."
    tput sgr0
    WARNINGS+=("snapper-rollback: No AUR helper (paru/yay) found - install one, then run: paru -S snapper-rollback")
fi

##################################################################################################################################
# Configure snapper-rollback for this system's layout
##################################################################################################################################

if command -v snapper-rollback &>/dev/null; then
    tput setaf 3
    echo "Configuring snapper-rollback..."
    tput sgr0

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

    tput setaf 2
    echo "snapper-rollback configured for subvolume: $ROOT_SUBVOL"
    tput sgr0
fi

##################################################################################################################################
# Create initial snapshot
##################################################################################################################################

tput setaf 3
echo "Creating initial snapshot..."
tput sgr0

sudo snapper -c root create --description "Initial snapshot after snapper setup"

##################################################################################################################################
# Regenerate GRUB config to include snapshots
##################################################################################################################################

tput setaf 3
echo "Regenerating GRUB config to include snapshots..."
tput sgr0

if ! sudo grub-mkconfig -o /boot/grub/grub.cfg; then
    tput setaf 3
    echo "WARNING: Failed to regenerate GRUB config"
    tput sgr0
    WARNINGS+=("grub-mkconfig: Failed to regenerate (run manually: sudo grub-mkconfig -o /boot/grub/grub.cfg)")
fi

##################################################################################################################################
# Summary
##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
echo "Snapper BTRFS snapshot system installed:"
echo
echo "Packages installed:"
echo "  - snapper          : Snapshot management tool"
echo "  - snap-pac         : Auto snapshots before/after pacman operations"
echo "  - grub-btrfs       : Adds snapshots to GRUB boot menu"
echo "  - snapper-openrc   : OpenRC init scripts for snapper services"
echo "  - snapper-rollback : Full system rollback support (AUR)"
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
tput sgr0

##################################################################################################################################
# Show warnings if any
##################################################################################################################################

if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo
    tput setaf 3
    echo "########################################################################"
    echo "############################ WARNINGS ##################################"
    echo "########################################################################"
    echo
    echo "The following issues occurred during setup:"
    echo
    for warning in "${WARNINGS[@]}"; do
        echo "  ! $warning"
    done
    echo
    echo "Snapper is installed but some features may not work as expected."
    echo "Review the warnings above and fix manually if needed."
    echo "########################################################################"
    tput sgr0
fi
