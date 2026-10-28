#!/bin/bash
set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Menu      : NVIDIA drivers — bare metal (dual GPU)
# Group     : hardware
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

script_start "Setting up NVIDIA Xorg configuration"

##################################################################################################################################
# Ensure Arch [extra] repo is available — nvidia-utils lives there, not in Artix's own repos.
# artix-archlinux-support provides /etc/pacman.d/mirrorlist-arch; we add [extra] ourselves.
##################################################################################################################################

ensure_arch_extra || die "Arch [extra] repo unavailable"
pkg_sync || die "could not sync package databases"

##################################################################################################################################
# Ensure nvidia-open-dkms, nvidia-utils, and nvidia-utils-openrc are installed.
# nvidia-open-dkms builds from source for the running kernel via DKMS — survives kernel upgrades.
# nvidia-utils lives in Arch [extra] (not Artix repos), which is why [extra] is added above.
##################################################################################################################################

ensure_pkgs nvidia-open-dkms nvidia-utils nvidia-utils-openrc || die "NVIDIA packages missing — aborting, xorg.conf will NOT be written"

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

# Blacklist nouveau so it does not claim the GPUs before the nvidia driver
NOUVEAU_BLACKLIST="/etc/modprobe.d/blacklist-nouveau.conf"
if [ ! -f "$NOUVEAU_BLACKLIST" ]; then
    echo "blacklist nouveau" | sudo tee "$NOUVEAU_BLACKLIST" > /dev/null
    ok "Written: $NOUVEAU_BLACKLIST"
else
    echo "nouveau already blacklisted: $NOUVEAU_BLACKLIST"
fi

# Rebuild initramfs so the new driver and blacklist take effect on next boot
_c setaf 3
echo "Rebuilding initramfs (mkinitcpio -P) ..."
_c sgr0
sudo mkinitcpio -P || die "mkinitcpio -P failed"
ok "initramfs rebuilt."

echo

# Create Xorg config to force nvidia driver on the display GPU.
# BusID pins Xorg to the display GPU so the passthrough GPU is ignored.
# Without this, Xorg may assign the second GPU to modesetting, which crashes via glamor_init.
XORG_CONF="/etc/X11/xorg.conf.d/10-nvidia.conf"

# Detect display GPU PCI address and convert to Xorg BusID format (decimal)
PCI_ADDR=$(lspci | grep "$DISPLAY_GPU_MODEL" | grep -i "VGA" | awk '{print $1}')
[ -n "$PCI_ADDR" ] || die "Could not detect display GPU ($DISPLAY_GPU_MODEL) PCI address. Aborting xorg conf write."
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
ok "Written: $XORG_CONF"

# Named 99-nvidia-flags.conf so it sorts last alphabetically and wins
# if any earlier config also has a ServerFlags section.
FLAGS_CONF="/etc/X11/xorg.conf.d/99-nvidia-flags.conf"
echo "Writing $FLAGS_CONF ..."
sudo tee "$FLAGS_CONF" > /dev/null << EOF
Section "ServerFlags"
    Option "AutoAddGPU" "false"
EndSection
EOF
ok "Written: $FLAGS_CONF"

##################################################################################################################################
# Enable nvidia-drm.modeset=1 kernel parameter (required for nvidia-open-dkms)
##################################################################################################################################

MODESET_PARAM="nvidia-drm.modeset=1"

# Detect bootloader: systemd-boot or GRUB
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
        # Handle both single-quoted and double-quoted GRUB_CMDLINE_LINUX_DEFAULT
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
echo "  - $XORG_CONF"
echo "      Forces nvidia driver on display GPU ($DISPLAY_GPU_MODEL), BusID: $BUS_ID"
echo "  - $FLAGS_CONF"
echo "      AutoAddGPU false — prevents secondary GPU from being grabbed by modesetting"
echo "  - kernel param: $MODESET_PARAM"
echo
echo "Fixes: Xorg modesetting/glamor crash with dual NVIDIA GPUs"
echo "       that prevented SDDM/LightDM from reaching the login screen."
echo
