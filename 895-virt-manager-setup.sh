#!/bin/bash
#set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install and configure virt-manager / QEMU-KVM on the host.
#             - Installs all required packages
#             - Enables and starts libvirtd
#             - Adds current user to libvirt + kvm groups
#             - Activates the default NAT network (autostart)
#             - Registers /mnt/vmssd as a libvirt storage pool (existing qcow2 files)
#
#             RTX 3090 is already bound to vfio-pci (890-vfio-passthrough.sh).
#             After running this script, add it as a PCI host device in virt-manager.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

# Directory where existing qcow2 disk images live.
# Change this if your images are elsewhere.
VM_DISK_DIR="/mnt/vmssd"

# Name for the libvirt storage pool that maps to VM_DISK_DIR.
POOL_NAME="vmssd"

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

artix_pacman_nohook_setup
sudo pacman --config "$NOHOOK_CONF" -Sy

##################################################################################################################################
# 1. Install packages
##################################################################################################################################

echo
tput setaf 2
echo "########################################################################"
echo "################### Installing virt-manager / QEMU-KVM packages"
echo "########################################################################"
tput sgr0
echo

# qemu-desktop  : QEMU with x86_64 system emulation + common device support
# libvirt       : hypervisor abstraction daemon (manages QEMU, networking, storage)
# libvirt-openrc: OpenRC init scripts for libvirtd and virtlogd
# virt-manager  : GTK GUI for managing VMs
# dnsmasq       : NAT/DHCP for the default libvirt network
# bridge-utils  : brctl — needed for bridged networking
# NOTE: iptables-nft intentionally omitted — conflicts with iptables (already installed)
#       libvirt works with whichever iptables backend is present
# edk2-ovmf     : UEFI firmware for VMs (required for Secure Boot / Windows 11); explicit name avoids provider prompt
# swtpm         : software TPM emulator (required for Windows 11 TPM 2.0)
# virt-viewer   : lightweight SPICE/VNC viewer (used by virt-manager)
# libguestfs    : guest filesystem tools (optional but useful: virt-df, guestfish)

PACKAGES=(
    qemu-desktop
    libvirt
    libvirt-openrc
    virt-manager
    dnsmasq
    bridge-utils
    edk2-ovmf
    swtpm
    virt-viewer
    libguestfs
)

# exfatprogs (pulled by libguestfs) conflicts with exfat-utils — remove it first if present
if pacman -Q exfat-utils &>/dev/null; then
    echo "Removing conflicting exfat-utils ..."
    sudo pacman --config "$NOHOOK_CONF" -Rns --noconfirm exfat-utils
fi

if sudo pacman --config "$NOHOOK_CONF" -S --noconfirm --needed "${PACKAGES[@]}"; then
    tput setaf 2
    echo "Packages installed."
    tput sgr0
else
    tput setaf 1
    echo "ERROR: pacman failed — aborting. Fix the conflict above and re-run."
    tput sgr0
    exit 1
fi

##################################################################################################################################
# 2. Enable and start libvirtd
##################################################################################################################################

echo
tput setaf 3
echo "########################################################################"
echo "################### Enabling libvirtd"
echo "########################################################################"
tput sgr0
echo

sudo rc-update add libvirtd default
sudo rc-service libvirtd start

# virtlogd handles VM console/serial logs — runs as a daemon under OpenRC
sudo rc-update add virtlogd default
sudo rc-service virtlogd start

tput setaf 2
echo "libvirtd enabled and running."
tput sgr0

##################################################################################################################################
# 3. Add user to libvirt and kvm groups
##################################################################################################################################

echo
tput setaf 3
echo "########################################################################"
echo "################### Adding $USER to libvirt + kvm groups"
echo "########################################################################"
tput sgr0
echo

sudo usermod -aG libvirt "$USER"
sudo usermod -aG kvm "$USER"

tput setaf 2
echo "User $USER added to: libvirt, kvm"
echo "(Group membership takes effect after next login or 'newgrp libvirt')"
tput sgr0

##################################################################################################################################
# 4. Activate the default NAT network
##################################################################################################################################

echo
tput setaf 3
echo "########################################################################"
echo "################### Activating default libvirt NAT network"
echo "########################################################################"
tput sgr0
echo

# Define the default network if it doesn't exist yet
if ! sudo virsh net-info default &>/dev/null; then
    sudo virsh net-define /usr/share/ebtables/default.xml 2>/dev/null \
        || sudo virsh net-define /etc/libvirt/qemu/networks/default.xml 2>/dev/null \
        || sudo virsh net-define <(cat <<'NETXML'
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
NETXML
)
    tput setaf 2
    echo "Default network defined."
    tput sgr0
else
    echo "Default network already defined."
fi

# Start and autostart the default network
if sudo virsh net-info default | grep -q "Active:.*no"; then
    sudo virsh net-start default
    tput setaf 2
    echo "Default network started."
    tput sgr0
else
    echo "Default network already active."
fi

if sudo virsh net-info default | grep -q "Autostart:.*no"; then
    sudo virsh net-autostart default
    tput setaf 2
    echo "Default network set to autostart."
    tput sgr0
else
    echo "Default network autostart already enabled."
fi

##################################################################################################################################
# 5. Register VM_DISK_DIR as a libvirt storage pool
##################################################################################################################################

echo
tput setaf 3
echo "########################################################################"
echo "################### Registering storage pool: $POOL_NAME -> $VM_DISK_DIR"
echo "########################################################################"
tput sgr0
echo

if [ ! -d "$VM_DISK_DIR" ]; then
    tput setaf 1
    echo "WARNING: $VM_DISK_DIR does not exist or is not mounted. Skipping pool registration."
    echo "Mount your SSD first, then run:"
    echo "  sudo virsh pool-define-as $POOL_NAME dir - - - - $VM_DISK_DIR"
    echo "  sudo virsh pool-build $POOL_NAME"
    echo "  sudo virsh pool-start $POOL_NAME"
    echo "  sudo virsh pool-autostart $POOL_NAME"
    tput sgr0
else
    if sudo virsh pool-info "$POOL_NAME" &>/dev/null; then
        echo "Storage pool '$POOL_NAME' already defined."
    else
        sudo virsh pool-define-as "$POOL_NAME" dir - - - - "$VM_DISK_DIR"
        tput setaf 2
        echo "Storage pool '$POOL_NAME' defined."
        tput sgr0
    fi

    if sudo virsh pool-info "$POOL_NAME" | grep -q "State:.*running"; then
        echo "Storage pool '$POOL_NAME' already running."
    else
        sudo virsh pool-build "$POOL_NAME" 2>/dev/null || true
        sudo virsh pool-start "$POOL_NAME"
        tput setaf 2
        echo "Storage pool '$POOL_NAME' started."
        tput sgr0
    fi

    if sudo virsh pool-info "$POOL_NAME" | grep -q "Autostart:.*no"; then
        sudo virsh pool-autostart "$POOL_NAME"
        tput setaf 2
        echo "Storage pool '$POOL_NAME' set to autostart."
        tput sgr0
    else
        echo "Storage pool '$POOL_NAME' autostart already enabled."
    fi

    echo
    echo "Disk images found in $VM_DISK_DIR:"
    ls "$VM_DISK_DIR"/*.qcow2 2>/dev/null | while read f; do
        echo "  $(basename "$f")"
    done
fi

##################################################################################################################################
# 6. Set virt-manager defaults: UEFI firmware for new VMs
##################################################################################################################################

echo
tput setaf 3
echo "########################################################################"
echo "################### Setting virt-manager default firmware to UEFI"
echo "########################################################################"
tput sgr0
echo

# virt-manager stores its UI defaults in dconf/gsettings.
# Setting firmware=uefi makes the New VM wizard pre-select UEFI instead of BIOS.
# This must run as the regular user (not sudo) to hit the right dconf store.
if gsettings set org.virt-manager.virt-manager.new-vm firmware uefi 2>/dev/null; then
    tput setaf 2
    echo "virt-manager default firmware set to UEFI."
    tput sgr0
else
    tput setaf 3
    echo "WARNING: gsettings not available in this session (running as root or no DBUS session)."
    echo "Run manually after logging in:"
    echo "  gsettings set org.virt-manager.virt-manager.new-vm firmware uefi"
    tput sgr0
fi

# Confirm OVMF firmware files are in place (installed via edk2-ovmf package)
OVMF_CODE=""
for candidate in \
    /usr/share/edk2/x64/OVMF_CODE.4m.fd \
    /usr/share/edk2/x64/OVMF_CODE.fd \
    /usr/share/OVMF/x64/OVMF_CODE.fd \
    /usr/share/OVMF/OVMF_CODE.fd; do
    if [ -f "$candidate" ]; then
        OVMF_CODE="$candidate"
        break
    fi
done
if [ -n "$OVMF_CODE" ]; then
    tput setaf 2
    echo "OVMF firmware found: $OVMF_CODE"
    tput sgr0
else
    tput setaf 1
    echo "ERROR: OVMF firmware not found — 'edk2-ovmf' package may not have installed correctly."
    tput sgr0
fi

##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
echo "Installed:"
for pkg in "${PACKAGES[@]}"; do echo "  - $pkg"; done
echo
echo "Configured:"
echo "  - libvirtd (rc-update default + started)"
echo "  - virtlogd (rc-update default + started)"
echo "  - User '$USER' added to groups: libvirt, kvm"
echo "  - Default NAT network (virbr0, 192.168.122.0/24) active + autostart"
echo "  - Storage pool '$POOL_NAME' -> $VM_DISK_DIR (active + autostart)"
echo "  - virt-manager default firmware: UEFI (gsettings)"
echo
echo "Next steps:"
echo "  1. Log out and back in (or run 'newgrp libvirt') for group membership to take effect"
echo "  2. Open virt-manager and create a new VM"
echo "  3. Under 'Storage', select pool '$POOL_NAME' to use existing qcow2 files"
echo "  4. To attach RTX 3090 (already vfio-bound):"
echo "       VM Details -> Add Hardware -> PCI Host Device"
echo "       Select: RTX 3090 (IOMMU group 36: 3f:00.0 + 3f:00.1)"
echo
tput sgr0
