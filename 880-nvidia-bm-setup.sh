#!/bin/bash
set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Configure Xorg and kernel for dual NVIDIA GPUs
#             Fixes modesetting/glamor crash that prevents SDDM from starting
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

# PCI model string for the display GPU (the one Xorg should use).
# Change this if your display GPU is not a GA106.
DISPLAY_GPU_MODEL="GA106"

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
echo "################### Setting up NVIDIA Xorg configuration"
echo "########################################################################"
tput sgr0
echo

artix_pacman_nohook_setup

##################################################################################################################################
# Ensure Arch [extra] repo is available — nvidia-utils lives there, not in Artix's own repos.
# artix-archlinux-support provides /etc/pacman.d/mirrorlist-arch; we add [extra] ourselves.
##################################################################################################################################

if ! pacman -Q artix-archlinux-support &>/dev/null; then
    tput setaf 3
    echo "artix-archlinux-support not installed — installing..."
    tput sgr0
    sudo pacman --config "$NOHOOK_CONF" -Sy --noconfirm artix-archlinux-support
fi

if ! grep -q '^\[extra\]' /etc/pacman.conf; then
    tput setaf 3
    echo "Arch [extra] repo not in pacman.conf — adding..."
    tput sgr0
    sudo tee -a /etc/pacman.conf <<'PACMAN_EOF'

# Arch Linux [extra] repo — added by 880-nvidia-xorg-setup.sh
[extra]
Include = /etc/pacman.d/mirrorlist-arch
PACMAN_EOF
fi

# [extra] may have just been added — regenerate NOHOOK_CONF so -Sy includes it
# (same pattern as 801 fix for [chaotic-aur]: NOHOOK_CONF was generated before the repo was appended)
sudo rm -f "$NOHOOK_CONF"
NOHOOK_CONF="$(sudo mktemp)"
sudo chmod 644 "$NOHOOK_CONF"
sudo sh -c "grep -v '^\s*HookDir' /etc/pacman.conf | sed '/^\[options\]/a HookDir = $NOHOOK_DIR' > '$NOHOOK_CONF'"
export NOHOOK_CONF

tput setaf 3
echo "Syncing package databases..."
tput sgr0
sudo pacman --config "$NOHOOK_CONF" -Sy

##################################################################################################################################
# Ensure nvidia-open-dkms, nvidia-utils, and nvidia-utils-openrc are installed.
# nvidia-open-dkms builds from source for the running kernel via DKMS — survives kernel upgrades.
# nvidia-utils lives in Arch [extra] (not Artix repos), which is why [extra] is added above.
##################################################################################################################################

NVIDIA_PKGS=()
pacman -Q nvidia-open-dkms    &>/dev/null || NVIDIA_PKGS+=(nvidia-open-dkms)
pacman -Q nvidia-utils         &>/dev/null || NVIDIA_PKGS+=(nvidia-utils)
pacman -Q nvidia-utils-openrc  &>/dev/null || NVIDIA_PKGS+=(nvidia-utils-openrc)

if [ ${#NVIDIA_PKGS[@]} -gt 0 ]; then
    tput setaf 3
    echo "Installing missing NVIDIA packages: ${NVIDIA_PKGS[*]}"
    tput sgr0
    if ! sudo pacman --config "$NOHOOK_CONF" -S --noconfirm "${NVIDIA_PKGS[@]}"; then
        tput setaf 1
        echo "ERROR: pacman failed to install NVIDIA packages. Aborting — xorg.conf will NOT be written."
        tput sgr0
        exit 1
    fi
    tput setaf 2
    echo "NVIDIA packages installed."
    tput sgr0
else
    echo "NVIDIA packages already installed."
fi

# Verify DKMS built modules for the running kernel; attempt rebuild if missing
KVER=$(uname -r)
if ! ls /usr/lib/modules/"$KVER"/extra/nvidia*.ko* 2>/dev/null | grep -q nvidia && \
   ! ls /usr/lib/modules/"$KVER"/extramodules/nvidia*.ko* 2>/dev/null | grep -q nvidia; then
    tput setaf 3
    echo "nvidia DKMS modules not found for kernel $KVER — attempting dkms autoinstall..."
    tput sgr0
    sudo dkms autoinstall
    # Re-check after rebuild attempt
    if ! ls /usr/lib/modules/"$KVER"/extra/nvidia*.ko* 2>/dev/null | grep -q nvidia && \
       ! ls /usr/lib/modules/"$KVER"/extramodules/nvidia*.ko* 2>/dev/null | grep -q nvidia; then
        tput setaf 1
        echo "ERROR: nvidia DKMS modules still not found for kernel $KVER after autoinstall."
        echo "       Run: sudo dkms status"
        tput sgr0
        exit 1
    fi
fi
tput setaf 2
echo "nvidia DKMS modules verified for kernel $KVER."
tput sgr0

# Blacklist nouveau so it does not claim the GPUs before the nvidia driver
NOUVEAU_BLACKLIST="/etc/modprobe.d/blacklist-nouveau.conf"
if [ ! -f "$NOUVEAU_BLACKLIST" ]; then
    echo "blacklist nouveau" | sudo tee "$NOUVEAU_BLACKLIST" > /dev/null
    tput setaf 2
    echo "Written: $NOUVEAU_BLACKLIST"
    tput sgr0
else
    echo "nouveau already blacklisted: $NOUVEAU_BLACKLIST"
fi

# Rebuild initramfs so the new driver and blacklist take effect on next boot
tput setaf 3
echo "Rebuilding initramfs (mkinitcpio -P) ..."
tput sgr0
sudo mkinitcpio -P
tput setaf 2
echo "initramfs rebuilt."
tput sgr0

echo

# Create Xorg config to force nvidia driver on the display GPU.
# BusID pins Xorg to the display GPU so the passthrough GPU is ignored.
# Without this, Xorg may assign the second GPU to modesetting, which crashes via glamor_init.
XORG_CONF="/etc/X11/xorg.conf.d/10-nvidia.conf"

# Detect display GPU PCI address and convert to Xorg BusID format (decimal)
PCI_ADDR=$(lspci | grep "$DISPLAY_GPU_MODEL" | grep -i "VGA" | awk '{print $1}')
if [ -z "$PCI_ADDR" ]; then
    tput setaf 1
    echo "ERROR: Could not detect display GPU ($DISPLAY_GPU_MODEL) PCI address. Aborting xorg conf write."
    tput sgr0
    exit 1
fi
BUS=$(printf "%d" "0x$(echo "$PCI_ADDR" | cut -d: -f1)")
DEV=$(printf "%d" "0x$(echo "$PCI_ADDR" | cut -d: -f2 | cut -d. -f1)")
FN=$(echo "$PCI_ADDR" | cut -d. -f2)
BUS_ID="PCI:${BUS}:${DEV}:${FN}"
echo "Detected display GPU ($DISPLAY_GPU_MODEL) at $PCI_ADDR -> Xorg BusID: $BUS_ID"

echo "Writing $XORG_CONF ..."
sudo tee "$XORG_CONF" > /dev/null << EOF
Section "Device"
    Identifier  "Nvidia Card"
    Driver      "nvidia"
    BusID       "$BUS_ID"
    Option      "NoLogo" "true"
EndSection
EOF
tput setaf 2
echo "Written: $XORG_CONF"
tput sgr0

# Named 99-nvidia-flags.conf so it sorts last alphabetically and wins
# if any earlier config also has a ServerFlags section.
FLAGS_CONF="/etc/X11/xorg.conf.d/99-nvidia-flags.conf"
echo "Writing $FLAGS_CONF ..."
sudo tee "$FLAGS_CONF" > /dev/null << EOF
Section "ServerFlags"
    Option "AutoAddGPU" "false"
EndSection
EOF
tput setaf 2
echo "Written: $FLAGS_CONF"
tput sgr0

##################################################################################################################################
# Enable nvidia-drm.modeset=1 kernel parameter (required for nvidia-open-dkms)
##################################################################################################################################

MODESET_PARAM="nvidia-drm.modeset=1"

# Detect bootloader: systemd-boot or GRUB
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
        # Handle both single-quoted and double-quoted GRUB_CMDLINE_LINUX_DEFAULT
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
echo "  - $XORG_CONF"
echo "      Forces nvidia driver on display GPU ($DISPLAY_GPU_MODEL), BusID: $BUS_ID"
echo "  - $FLAGS_CONF"
echo "      AutoAddGPU false — prevents secondary GPU from being grabbed by modesetting"
echo "  - kernel param: $MODESET_PARAM"
echo
echo "Fixes: Xorg modesetting/glamor crash with dual NVIDIA GPUs"
echo "       that prevented SDDM/LightDM from reaching the login screen."
echo
tput sgr0
