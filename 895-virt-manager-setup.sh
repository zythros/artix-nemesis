#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Menu      : Install virt-manager / QEMU-KVM
# Group     : optional
# Purpose   : Install and configure virt-manager / QEMU-KVM on the host.
#             - Installs all required packages
#             - Enables and starts libvirtd
#             - Adds current user to libvirt + kvm groups
#             - Activates the default NAT network (autostart)
#             - Registers VM_DISK_DIR (below, /mnt/vmssd) as a libvirt storage pool (existing qcow2 files)
#
#             A GPU bound to vfio-pci by 890-vfio-passthrough.sh can be passed through.
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

script_start "Setting up virt-manager / QEMU-KVM"
pkg_sync

##################################################################################################################################
# 1. Install packages
##################################################################################################################################

section "Packages"

# qemu-desktop  : QEMU with x86_64 system emulation + common device support
# libvirt       : hypervisor abstraction daemon (manages QEMU, networking, storage)
# libvirt-openrc: OpenRC init scripts for libvirtd and virtlogd
# virt-manager  : GTK GUI for managing VMs
# dnsmasq       : NAT/DHCP for the default libvirt network
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
    edk2-ovmf
    swtpm
    virt-viewer
    libguestfs
)

# exfatprogs (pulled by libguestfs) conflicts with exfat-utils — remove it first if present
if pacman -Q exfat-utils &>/dev/null; then
    echo "Removing conflicting exfat-utils ..."
    sudo pacman --config "$NOHOOK_CONF" -Rns --noconfirm exfat-utils || err "could not remove exfat-utils"
fi

ensure_pkgs "${PACKAGES[@]}" || die "packages missing — fix the problem above and re-run"

##################################################################################################################################
# 2. Enable and start libvirtd
##################################################################################################################################

section "Enabling libvirtd"

enable_service libvirtd

# virtlogd handles VM console/serial logs — runs as a daemon under OpenRC
enable_service virtlogd

##################################################################################################################################
# 3. Add user to libvirt and kvm groups
##################################################################################################################################

section "Adding $USER to libvirt + kvm groups"

if sudo usermod -aG libvirt,kvm "$USER"; then
    ok "User $USER added to: libvirt, kvm"
    ok "(Group membership takes effect after next login or 'newgrp libvirt')"
else
    err "could not add $USER to the libvirt/kvm groups"
fi

##################################################################################################################################
# 4. Activate the default NAT network
##################################################################################################################################

section "Activating default libvirt NAT network"

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
) && ok "Default network defined." || err "could not define the default libvirt network"
else
    echo "Default network already defined."
fi

# Start and autostart the default network
if sudo virsh net-info default | grep -q "Active:.*no"; then
    if sudo virsh net-start default; then
        ok "Default network started."
    else
        err "could not start the default libvirt network"
    fi
else
    echo "Default network already active."
fi

if sudo virsh net-info default | grep -q "Autostart:.*no"; then
    sudo virsh net-autostart default && ok "Default network set to autostart." \
        || err "could not set the default libvirt network to autostart"
else
    echo "Default network autostart already enabled."
fi

##################################################################################################################################
# 5. Register VM_DISK_DIR as a libvirt storage pool
##################################################################################################################################

section "Registering storage pool: $POOL_NAME -> $VM_DISK_DIR"

if [ ! -d "$VM_DISK_DIR" ]; then
    warn "$VM_DISK_DIR does not exist or is not mounted — storage pool '$POOL_NAME' not registered"
    _c setaf 3
    echo "Mount your SSD first, then run:"
    echo "  sudo virsh pool-define-as $POOL_NAME dir - - - - $VM_DISK_DIR"
    echo "  sudo virsh pool-build $POOL_NAME"
    echo "  sudo virsh pool-start $POOL_NAME"
    echo "  sudo virsh pool-autostart $POOL_NAME"
    _c sgr0
else
    if sudo virsh pool-info "$POOL_NAME" &>/dev/null; then
        echo "Storage pool '$POOL_NAME' already defined."
    else
        sudo virsh pool-define-as "$POOL_NAME" dir - - - - "$VM_DISK_DIR" \
            && ok "Storage pool '$POOL_NAME' defined." || err "could not define storage pool '$POOL_NAME'"
    fi

    if sudo virsh pool-info "$POOL_NAME" | grep -q "State:.*running"; then
        echo "Storage pool '$POOL_NAME' already running."
    else
        sudo virsh pool-build "$POOL_NAME" 2>/dev/null || true
        sudo virsh pool-start "$POOL_NAME" \
            && ok "Storage pool '$POOL_NAME' started." || err "could not start storage pool '$POOL_NAME'"
    fi

    if sudo virsh pool-info "$POOL_NAME" | grep -q "Autostart:.*no"; then
        sudo virsh pool-autostart "$POOL_NAME" \
            && ok "Storage pool '$POOL_NAME' set to autostart." || err "could not autostart storage pool '$POOL_NAME'"
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

section "Setting virt-manager default firmware to UEFI"

# virt-manager stores its UI defaults in dconf/gsettings.
# Setting firmware=uefi makes the New VM wizard pre-select UEFI instead of BIOS.
# This must run as the regular user (not sudo) to hit the right dconf store.
# Without a session bus (TTY, ssh) gsettings silently falls back to an
# in-memory backend and still exits 0 — use a throwaway bus so dconf writes
# the real file, and read the value back to confirm.
GSETTINGS=(gsettings)
[ -z "$DBUS_SESSION_BUS_ADDRESS" ] && GSETTINGS=(dbus-run-session -- gsettings)
if "${GSETTINGS[@]}" set org.virt-manager.virt-manager.new-vm firmware uefi 2>/dev/null \
    && [ "$("${GSETTINGS[@]}" get org.virt-manager.virt-manager.new-vm firmware 2>/dev/null)" = "'uefi'" ]; then
    ok "virt-manager default firmware set to UEFI."
else
    warn "could not set virt-manager's default firmware — after logging in run: gsettings set org.virt-manager.virt-manager.new-vm firmware uefi"
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
    ok "OVMF firmware found: $OVMF_CODE"
else
    err "OVMF firmware not found — 'edk2-ovmf' package may not have installed correctly"
fi

##################################################################################################################################

script_done
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
echo "  4. To attach a GPU bound to vfio-pci by 890-vfio-passthrough.sh:"
echo "       VM Details -> Add Hardware -> PCI Host Device"
echo "       Select the GPU and its audio function (same bus:device, .0 and .1)"
echo
