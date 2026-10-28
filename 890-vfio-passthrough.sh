#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Menu      : Configure VFIO passthrough for RTX 3090
# Group     : hardware
# Purpose   : Configure VFIO passthrough for the secondary GPU — isolates it from the nvidia driver
#             so it can be assigned exclusively to a VM via virt-manager / QEMU.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

# PCI model string (as shown by lspci) of the GPU to pass through to VMs.
# GA102 = the RTX 3090 on artix-pc. Its audio function (.1) is bound too.
PASSTHROUGH_GPU_MODEL="GA102"

##################################################################################################################################

script_start "Setting up VFIO passthrough ($PASSTHROUGH_GPU_MODEL)"

##################################################################################################################################
# Detect the passthrough GPU PCI address and IDs
##################################################################################################################################

GPU_ADDR=$(lspci | grep "$PASSTHROUGH_GPU_MODEL" | grep -i "VGA" | awk '{print $1}')
[ -n "$GPU_ADDR" ] || die "Could not detect a $PASSTHROUGH_GPU_MODEL GPU PCI address. Aborting."
echo "Detected $PASSTHROUGH_GPU_MODEL GPU at: $GPU_ADDR"

# Companion audio device is at the same bus:device, function 1
AUDIO_ADDR="${GPU_ADDR%.*}.1"

GPU_ID=$(lspci -nn | grep "^$GPU_ADDR " | grep -oP '\[10de:[0-9a-f]+\]' | tail -1 | tr -d '[]')
AUDIO_ID=$(lspci -nn | grep "^$AUDIO_ADDR " | grep -oP '\[10de:[0-9a-f]+\]' | tail -1 | tr -d '[]')

[ -n "$GPU_ID" ] || die "Could not extract PCI ID for $GPU_ADDR. Aborting."

echo "Passthrough GPU   PCI ID: $GPU_ID"
if [ -n "$AUDIO_ID" ]; then
    echo "Passthrough audio PCI ID: $AUDIO_ID"
    VFIO_IDS="$GPU_ID,$AUDIO_ID"
else
    warn "No audio device found at $AUDIO_ADDR — only binding GPU."
    VFIO_IDS="$GPU_ID"
fi

##################################################################################################################################
# Write /etc/modprobe.d/vfio.conf — tells vfio-pci which device IDs to claim
##################################################################################################################################

VFIO_MODPROBE="/etc/modprobe.d/vfio.conf"
echo
echo "Writing $VFIO_MODPROBE ..."
sudo tee "$VFIO_MODPROBE" > /dev/null << EOF || die "could not write $VFIO_MODPROBE"
# VFIO passthrough — bind secondary GPU to vfio-pci instead of nvidia
options vfio-pci ids=$VFIO_IDS
EOF
ok "Written: $VFIO_MODPROBE"

##################################################################################################################################
# Update /etc/mkinitcpio.conf — load vfio modules early (before nvidia claims the device)
##################################################################################################################################

MKINITCPIO_CONF="/etc/mkinitcpio.conf"
echo
echo "Updating MODULES in $MKINITCPIO_CONF ..."

VFIO_MODULES="vfio_pci vfio"

if grep -qP "^MODULES=\(.*vfio_pci" "$MKINITCPIO_CONF"; then
    _c setaf 3
    echo "vfio_pci already present in MODULES — skipping mkinitcpio.conf edit."
    _c sgr0
else
    # Prepend vfio modules to the existing MODULES=() array
    # Handles both empty MODULES=() and MODULES=(existing stuff)
    sudo sed -i "s/^MODULES=(\(.*\))/MODULES=($VFIO_MODULES \1)/" "$MKINITCPIO_CONF"
    # Clean up any trailing spaces from empty original array
    sudo sed -i "s/^MODULES=($VFIO_MODULES )/MODULES=($VFIO_MODULES)/" "$MKINITCPIO_CONF"
    ok "Updated MODULES in $MKINITCPIO_CONF"
fi

##################################################################################################################################
# Enable IOMMU kernel parameter in GRUB or systemd-boot
##################################################################################################################################

# Detect CPU vendor for the correct IOMMU flag
CPU_VENDOR=$(grep -m1 "vendor_id" /proc/cpuinfo | awk '{print $3}')
if echo "$CPU_VENDOR" | grep -q "AMD"; then
    IOMMU_PARAM="amd_iommu=on"
else
    IOMMU_PARAM="intel_iommu=on"
fi
PT_PARAM="iommu=pt"

echo
if sudo test -f "/boot/loader/loader.conf"; then
    _c setaf 3
    echo "Detected systemd-boot — adding $IOMMU_PARAM $PT_PARAM to boot entries..."
    _c sgr0

    for entry in /boot/loader/entries/*.conf; do
        if grep -q "^options" "$entry"; then
            CHANGED=0
            if ! grep -q "$IOMMU_PARAM" "$entry"; then
                sudo sed -i "s/^options .*/& $IOMMU_PARAM/" "$entry"
                CHANGED=1
            fi
            if ! grep -q "$PT_PARAM" "$entry"; then
                sudo sed -i "s/^options .*/& $PT_PARAM/" "$entry"
                CHANGED=1
            fi
            if [ $CHANGED -eq 1 ]; then
                ok "Updated: $entry"
            else
                echo "Already present in: $entry"
            fi
        fi
    done

elif [ -f "/etc/default/grub" ]; then
    _c setaf 3
    echo "Detected GRUB — adding $IOMMU_PARAM $PT_PARAM to /etc/default/grub..."
    _c sgr0

    GRUB_CHANGED=0
    if ! grep -q "$IOMMU_PARAM" /etc/default/grub; then
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"$IOMMU_PARAM /" /etc/default/grub
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT='/GRUB_CMDLINE_LINUX_DEFAULT='$IOMMU_PARAM /" /etc/default/grub
        GRUB_CHANGED=1
    else
        echo "$IOMMU_PARAM already present in /etc/default/grub"
    fi
    if ! grep -q "$PT_PARAM" /etc/default/grub; then
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"/GRUB_CMDLINE_LINUX_DEFAULT=\"$PT_PARAM /" /etc/default/grub
        sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT='/GRUB_CMDLINE_LINUX_DEFAULT='$PT_PARAM /" /etc/default/grub
        GRUB_CHANGED=1
    else
        echo "$PT_PARAM already present in /etc/default/grub"
    fi

    if [ $GRUB_CHANGED -eq 1 ]; then
        sudo grub-mkconfig -o /boot/grub/grub.cfg
        ok "GRUB updated and config regenerated."
    fi

else
    err "Could not detect bootloader. Add '$IOMMU_PARAM $PT_PARAM' to your kernel parameters manually."
fi

##################################################################################################################################
# Rebuild initramfs
##################################################################################################################################

echo
_c setaf 3
echo "Rebuilding initramfs (mkinitcpio -P) ..."
_c sgr0
sudo mkinitcpio -P || die "mkinitcpio -P failed — VFIO modules not in the initramfs"
ok "Initramfs rebuilt."

##################################################################################################################################

script_done
echo "Configured:"
echo "  - $VFIO_MODPROBE (vfio-pci IDs: $VFIO_IDS)"
echo "  - $MKINITCPIO_CONF (vfio modules loaded early: $VFIO_MODULES)"
echo "  - Kernel params: $IOMMU_PARAM $PT_PARAM"
echo "  - Initramfs rebuilt"
echo
echo "REBOOT required to activate VFIO passthrough."
echo
echo "After reboot, verify:"
echo "  lspci -k | grep -A2 '$GPU_ADDR'   # should show 'Kernel driver in use: vfio-pci'"
echo "  dmesg | grep -i iommu             # should show IOMMU enabled"
echo
