#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Menu      : SPICE clipboard sharing (VM guests only)
# Purpose   : Set up host-VM clipboard sharing (copy/paste) via SPICE
#             Installs spice-vdagent and qemu-guest-agent for QEMU/KVM VMs
#             Artix/OpenRC port — skips automatically on bare metal
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

script_start "Setting up VM clipboard sharing"

##################################################################################################################################
# Check if running inside a VM
##################################################################################################################################

# virt-what replaces systemd-detect-virt (not available on Artix/OpenRC)
command -v virt-what &>/dev/null || ensure_pkgs virt-what || die "virt-what is needed to detect a VM"

VIRT_TYPE=$(sudo virt-what 2>/dev/null | head -1)

[ -n "$VIRT_TYPE" ] || script_skip "Not running inside a VM — no clipboard sharing to set up."
echo "Detected virtualization: $VIRT_TYPE"

##################################################################################################################################
# 1. Install packages
##################################################################################################################################

echo
echo "Installing VM guest packages..."

# -openrc packages: the OpenRC service files are packaged separately on Artix
ensure_pkgs spice-vdagent spice-vdagent-openrc qemu-guest-agent qemu-guest-agent-openrc xclip

##################################################################################################################################
# 2. Enable services (OpenRC)
##################################################################################################################################

echo
echo "Enabling services..."

# spice-vdagent — system daemon for the SPICE agent connection (spice-vdagentd)
enable_service spice-vdagent

# qemu-guest-agent — host-guest communication channel
enable_service qemu-guest-agent

##################################################################################################################################
# 3. Ensure spice-vdagent starts in X session
##################################################################################################################################

echo
echo "Configuring spice-vdagent autostart..."

# --- XDG autostart (fallback for DEs that read it) ---
if [ ! -f /etc/xdg/autostart/spice-vdagent.desktop ]; then
    echo "  Creating XDG autostart entry..."
    sudo mkdir -p /etc/xdg/autostart
    sudo tee /etc/xdg/autostart/spice-vdagent.desktop > /dev/null << 'DESKTOP' || err "could not write the XDG autostart entry"
[Desktop Entry]
Name=Spice vdagent
Comment=Agent for Spice guests
Exec=/usr/bin/spice-vdagent
Terminal=false
Type=Application
NoDisplay=true
DESKTOP
    echo "  Created /etc/xdg/autostart/spice-vdagent.desktop"
else
    echo "  XDG autostart entry already present"
fi

# --- ~/.xprofile injection (for dwm via LightDM) ---
XPROFILE="$HOME/.xprofile"
if grep -q "spice-vdagent" "$XPROFILE" 2>/dev/null; then
    echo "  ~/.xprofile already has spice-vdagent"
else
    echo "  Adding spice-vdagent to ~/.xprofile..."
    cat >> "$XPROFILE" << 'XPROFILE_ENTRY'

# VM clipboard sharing — only runs when inside a VM
command -v spice-vdagent &>/dev/null && spice-vdagent &
XPROFILE_ENTRY
    echo "  Added to $XPROFILE"
fi

# Start now if in a graphical session
if [ -n "$DISPLAY" ]; then
    if ! pgrep -x spice-vdagent &>/dev/null; then
        echo "  Starting spice-vdagent..."
        spice-vdagent &
    else
        echo "  spice-vdagent already running"
    fi
fi

##################################################################################################################################
# 4. Summary
##################################################################################################################################

script_done
echo "VM clipboard sharing:"
echo "  - spice-vdagent (clipboard sync, auto-resize)"
echo "  - qemu-guest-agent (host-guest communication)"
echo "  - xclip (clipboard utilities)"
echo
echo "Services enabled (OpenRC):"
echo "  - spice-vdagent (system daemon, needs a SPICE channel on the VM)"
echo "  - qemu-guest-agent (host communication)"
echo
echo "Copy/paste between host and VM should work after next login."
echo "If not working now, log out and back in (or reboot)."
echo
