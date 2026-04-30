#!/bin/bash
set -e
##################################################################################################################################
# Author    : zythros
# Purpose   : Install NVIDIA drivers inside a VM with a passed-through RTX 3090 (GA102).
#             Only one GPU is visible to the guest, so no Xorg pinning or dual-GPU
#             workarounds are needed — just driver install + nouveau blacklist.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
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
echo "################### Setting up NVIDIA drivers (VM guest)"
echo "########################################################################"
tput sgr0
echo

##################################################################################################################################
# Ensure Arch [extra] repo is available — nvidia-utils lives there, not in Artix's own repos.
##################################################################################################################################

if ! pacman -Q artix-archlinux-support &>/dev/null; then
    tput setaf 3
    echo "artix-archlinux-support not installed — installing..."
    tput sgr0
    sudo pacman -Sy --noconfirm artix-archlinux-support
fi

if ! grep -q '^\[extra\]' /etc/pacman.conf; then
    tput setaf 3
    echo "Arch [extra] repo not in pacman.conf — adding..."
    tput sgr0
    sudo tee -a /etc/pacman.conf <<'PACMAN_EOF'

# Arch Linux [extra] repo — added by 881-nvidia-vm-setup.sh
[extra]
Include = /etc/pacman.d/mirrorlist-arch
PACMAN_EOF
fi

tput setaf 3
echo "Syncing package databases..."
tput sgr0
sudo pacman -Sy

##################################################################################################################################
# Install nvidia-open-dkms, nvidia-utils, nvidia-utils-openrc.
# nvidia-open-dkms builds for the running kernel via DKMS — survives kernel upgrades.
##################################################################################################################################

NVIDIA_PKGS=()
pacman -Q nvidia-open-dkms   &>/dev/null || NVIDIA_PKGS+=(nvidia-open-dkms)
pacman -Q nvidia-utils        &>/dev/null || NVIDIA_PKGS+=(nvidia-utils)
pacman -Q nvidia-utils-openrc &>/dev/null || NVIDIA_PKGS+=(nvidia-utils-openrc)

if [ ${#NVIDIA_PKGS[@]} -gt 0 ]; then
    tput setaf 3
    echo "Installing missing NVIDIA packages: ${NVIDIA_PKGS[*]}"
    tput sgr0
    if ! sudo pacman -S --noconfirm "${NVIDIA_PKGS[@]}"; then
        tput setaf 1
        echo "ERROR: pacman failed to install NVIDIA packages. Aborting."
        tput sgr0
        exit 1
    fi
    tput setaf 2
    echo "NVIDIA packages installed."
    tput sgr0
else
    echo "NVIDIA packages already installed."
fi

# Verify DKMS built modules for the running kernel
KVER=$(uname -r)
if ! ls /usr/lib/modules/"$KVER"/extramodules/nvidia*.ko* 2>/dev/null | grep -q nvidia; then
    tput setaf 1
    echo "ERROR: nvidia DKMS modules not found for kernel $KVER — DKMS build may have failed."
    echo "       Run: sudo dkms status"
    tput sgr0
    exit 1
fi
tput setaf 2
echo "nvidia DKMS modules verified for kernel $KVER."
tput sgr0

##################################################################################################################################
# Blacklist nouveau
##################################################################################################################################

NOUVEAU_BLACKLIST="/etc/modprobe.d/blacklist-nouveau.conf"
if [ ! -f "$NOUVEAU_BLACKLIST" ]; then
    echo "blacklist nouveau" | sudo tee "$NOUVEAU_BLACKLIST" > /dev/null
    tput setaf 2
    echo "Written: $NOUVEAU_BLACKLIST"
    tput sgr0
else
    echo "nouveau already blacklisted: $NOUVEAU_BLACKLIST"
fi

# Rebuild initramfs so the driver and blacklist take effect on next boot
tput setaf 3
echo "Rebuilding initramfs (mkinitcpio -P) ..."
tput sgr0
sudo mkinitcpio -P
tput setaf 2
echo "initramfs rebuilt."
tput sgr0

##################################################################################################################################
# Enable nvidia-drm.modeset=1 kernel parameter (required for nvidia-open-dkms)
##################################################################################################################################

MODESET_PARAM="nvidia-drm.modeset=1"

if sudo test -f "/boot/loader/loader.conf"; then
    tput setaf 3
    echo "Detected systemd-boot — adding $MODESET_PARAM to boot entries..."
    tput sgr0
    for entry in /boot/loader/entries/*.conf; do
        if grep -q "^options" "$entry"; then
            if ! grep -q "$MODESET_PARAM" "$entry"; then
                sudo sed -i "s/^options .*/& $MODESET_PARAM/" "$entry"
                tput setaf 2
                echo "Updated: $entry"
                tput sgr0
            else
                echo "Already present in: $entry"
            fi
        fi
    done

elif [ -f "/etc/default/grub" ]; then
    tput setaf 3
    echo "Detected GRUB — adding $MODESET_PARAM to /etc/default/grub..."
    tput sgr0
    if ! grep -q "$MODESET_PARAM" /etc/default/grub; then
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"$MODESET_PARAM /" /etc/default/grub
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT='/GRUB_CMDLINE_LINUX_DEFAULT='$MODESET_PARAM /" /etc/default/grub
        sudo grub-mkconfig -o /boot/grub/grub.cfg
        tput setaf 2
        echo "GRUB updated and config regenerated."
        tput sgr0
    else
        echo "$MODESET_PARAM already present in /etc/default/grub"
    fi

else
    tput setaf 1
    echo "Could not detect bootloader. Add '$MODESET_PARAM' to your kernel parameters manually."
    tput sgr0
fi

##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
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
tput sgr0
