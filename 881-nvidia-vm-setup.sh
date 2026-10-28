#!/bin/bash
set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Menu      : NVIDIA drivers — VM guest (3090 passthrough)
# Purpose   : Install NVIDIA drivers inside a VM with a passed-through RTX 3090 (GA102).
#             Only one GPU is visible to the guest, so no Xorg pinning or dual-GPU
#             workarounds are needed — just driver install + nouveau blacklist.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

script_start "Setting up NVIDIA drivers (VM guest)"

##################################################################################################################################
# Ensure Arch [extra] repo is available — nvidia-utils lives there, not in Artix's own repos.
##################################################################################################################################

ensure_pkgs artix-archlinux-support || die "artix-archlinux-support is needed for Arch [extra]"

if ! grep -q '^\[extra\]' /etc/pacman.conf; then
    _c setaf 3
    echo "Arch [extra] repo not in pacman.conf — adding..."
    _c sgr0
    sudo tee -a /etc/pacman.conf <<'PACMAN_EOF'

# Arch Linux [extra] repo — added by 881-nvidia-vm-setup.sh
[extra]
Include = /etc/pacman.d/mirrorlist-arch
PACMAN_EOF
fi

# [extra] may have just been added — regenerate NOHOOK_CONF so -Sy includes it
nohook_regen
pkg_sync || die "could not sync package databases"

##################################################################################################################################
# Install nvidia-open-dkms, nvidia-utils, nvidia-utils-openrc.
# nvidia-open-dkms builds for the running kernel via DKMS — survives kernel upgrades.
##################################################################################################################################

ensure_pkgs nvidia-open-dkms nvidia-utils nvidia-utils-openrc || die "NVIDIA packages missing — aborting"

# Ensure linux-headers for the running kernel are present — DKMS needs them to build modules.
# On Artix/Arch the headers package is simply 'linux-headers' and matches the running 'linux' kernel.
ensure_pkgs linux-headers || die "linux-headers missing (required for DKMS build)"

# Verify DKMS built modules for the running kernel; attempt rebuild if missing.
# Use "dkms status" rather than filesystem globs — Arch DKMS installs to
# updates/dkms/ (not extra/ or extramodules/), so path checks produce false negatives.
KVER=$(uname -r)
if ! sudo dkms status 2>/dev/null | grep -q "nvidia.*${KVER}.*installed"; then
    _c setaf 3
    echo "nvidia DKMS modules not found for kernel $KVER — attempting dkms autoinstall..."
    _c sgr0
    sudo dkms autoinstall
    if ! sudo dkms status 2>/dev/null | grep -q "nvidia.*${KVER}.*installed"; then
        die "nvidia DKMS modules still not found for kernel $KVER after autoinstall (run: sudo dkms status)"
    fi
fi
ok "nvidia DKMS modules verified for kernel $KVER."

##################################################################################################################################
# Blacklist nouveau
##################################################################################################################################

NOUVEAU_BLACKLIST="/etc/modprobe.d/blacklist-nouveau.conf"
if [ ! -f "$NOUVEAU_BLACKLIST" ]; then
    echo "blacklist nouveau" | sudo tee "$NOUVEAU_BLACKLIST" > /dev/null
    ok "Written: $NOUVEAU_BLACKLIST"
else
    echo "nouveau already blacklisted: $NOUVEAU_BLACKLIST"
fi

# Rebuild initramfs so the driver and blacklist take effect on next boot
_c setaf 3
echo "Rebuilding initramfs (mkinitcpio -P) ..."
_c sgr0
sudo mkinitcpio -P || die "mkinitcpio -P failed"
ok "initramfs rebuilt."

##################################################################################################################################
# Enable nvidia-drm.modeset=1 kernel parameter (required for nvidia-open-dkms)
##################################################################################################################################

MODESET_PARAM="nvidia-drm.modeset=1"

if sudo test -f "/boot/loader/loader.conf"; then
    _c setaf 3
    echo "Detected systemd-boot — adding $MODESET_PARAM to boot entries..."
    _c sgr0
    for entry in /boot/loader/entries/*.conf; do
        if grep -q "^options" "$entry"; then
            if ! grep -q "$MODESET_PARAM" "$entry"; then
                sudo sed -i "s/^options .*/& $MODESET_PARAM/" "$entry"
                ok "Updated: $entry"
            else
                echo "Already present in: $entry"
            fi
        fi
    done

elif [ -f "/etc/default/grub" ]; then
    _c setaf 3
    echo "Detected GRUB — adding $MODESET_PARAM to /etc/default/grub..."
    _c sgr0
    if ! grep -q "$MODESET_PARAM" /etc/default/grub; then
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"$MODESET_PARAM /" /etc/default/grub
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT='/GRUB_CMDLINE_LINUX_DEFAULT='$MODESET_PARAM /" /etc/default/grub
        sudo grub-mkconfig -o /boot/grub/grub.cfg
        ok "GRUB updated and config regenerated."
    else
        echo "$MODESET_PARAM already present in /etc/default/grub"
    fi

else
    err "Could not detect bootloader. Add '$MODESET_PARAM' to your kernel parameters manually."
fi

##################################################################################################################################

script_done
echo "Configured:"
echo "  - Arch [extra] repo added to pacman.conf (if missing) for nvidia-utils"
echo "  - nvidia-open-dkms + nvidia-utils + nvidia-utils-openrc installed (if missing)"
echo "  - $NOUVEAU_BLACKLIST"
echo "      Blacklists nouveau so nvidia takes ownership at boot"
echo "  - initramfs rebuilt via mkinitcpio -P"
echo "  - kernel param: $MODESET_PARAM"
echo
echo "Reboot for changes to take effect."
echo
