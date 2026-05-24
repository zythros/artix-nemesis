#!/bin/bash
#set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install CUPS + Epson ET-3950 driver (ESCPR2) + Avahi for network
#             printer discovery.  After running, add the printer via the CUPS
#             web UI at http://localhost:631.
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
echo "################### Setting up Epson ET-3950 printer"
echo "########################################################################"
tput sgr0
echo

##################################################################################################################################
# Authenticate sudo once; keepalive prevents expiry during installs
##################################################################################################################################

sudo -v
while true; do sudo -v; sleep 50; done &
SUDO_KEEPALIVE=$!

artix_pacman_nohook_setup
trap "sudo rm -rf '$NOHOOK_DIR' '$NOHOOK_CONF'; kill $SUDO_KEEPALIVE 2>/dev/null" EXIT

##################################################################################################################################
# Helper
##################################################################################################################################

pkg_install() {
    local pkg="$1"
    sudo rm -f /var/lib/pacman/db.lck
    if sudo pacman --config "$NOHOOK_CONF" -S --noconfirm --needed "$pkg"; then
        return 0
    fi
    sudo rm -f /var/lib/pacman/db.lck
    if command -v yay &>/dev/null; then
        yay --config "$NOHOOK_CONF" -S --noconfirm --needed "$pkg"
        return $?
    fi
    return 1
}

##################################################################################################################################
# 1. CUPS
##################################################################################################################################

echo
tput setaf 3
echo "── CUPS ──────────────────────────────────────────────────────"
tput sgr0

for pkg in cups cups-openrc; do
    if pacman -Q "$pkg" &>/dev/null; then
        echo "$pkg already installed — skipping."
    else
        echo "Installing $pkg ..."
        pkg_install "$pkg" || true
        if pacman -Q "$pkg" &>/dev/null; then
            tput setaf 2; echo "$pkg installed."; tput sgr0
        else
            tput setaf 1; echo "ERROR: $pkg installation failed." >&2; tput sgr0
        fi
    fi
done

##################################################################################################################################
# 2. Avahi — mDNS / network printer auto-discovery
##################################################################################################################################

echo
tput setaf 3
echo "── Avahi (mDNS / network printer discovery) ──────────────────"
tput sgr0

for pkg in avahi avahi-openrc nss-mdns; do
    if pacman -Q "$pkg" &>/dev/null; then
        echo "$pkg already installed — skipping."
    else
        echo "Installing $pkg ..."
        pkg_install "$pkg" || true
        if pacman -Q "$pkg" &>/dev/null; then
            tput setaf 2; echo "$pkg installed."; tput sgr0
        else
            tput setaf 1; echo "ERROR: $pkg installation failed." >&2; tput sgr0
        fi
    fi
done

# Patch /etc/nsswitch.conf so .local hostnames resolve via mDNS
if grep -q 'mdns_minimal' /etc/nsswitch.conf; then
    echo "nsswitch.conf already has mdns_minimal — skipping."
else
    echo "Patching /etc/nsswitch.conf for mDNS ..."
    sudo sed -i '/^hosts:/ s/dns/mdns_minimal [NOTFOUND=return] dns/' /etc/nsswitch.conf
    tput setaf 2; echo "nsswitch.conf patched."; tput sgr0
fi

##################################################################################################################################
# 3. Epson ESCPR2 driver  (ET-3950 requires ESCPR2, not the older ESCPR)
##################################################################################################################################

echo
tput setaf 3
echo "── Epson ESCPR2 driver ────────────────────────────────────────"
tput sgr0

DRIVER_PKG="epson-inkjet-printer-escpr2"
if pacman -Q "$DRIVER_PKG" &>/dev/null; then
    echo "$DRIVER_PKG already installed — skipping."
else
    echo "Installing $DRIVER_PKG (tries Chaotic AUR first, falls back to yay) ..."
    pkg_install "$DRIVER_PKG" || true
    if pacman -Q "$DRIVER_PKG" &>/dev/null; then
        tput setaf 2; echo "$DRIVER_PKG installed."; tput sgr0
    else
        tput setaf 1; echo "ERROR: $DRIVER_PKG installation failed." >&2; tput sgr0
    fi
fi

##################################################################################################################################
# 4. Enable and start services (OpenRC)
##################################################################################################################################

echo
tput setaf 3
echo "── Enabling services ─────────────────────────────────────────"
tput sgr0

for svc in cupsd avahi-daemon; do
    echo "Enabling $svc ..."
    if sudo rc-update add "$svc" default 2>/dev/null; then
        tput setaf 2; echo "  $svc enabled at default runlevel."; tput sgr0
    else
        echo "  $svc already enabled."
    fi
    echo "Starting $svc ..."
    if sudo rc-service "$svc" start 2>/dev/null; then
        tput setaf 2; echo "  $svc started."; tput sgr0
    else
        echo "  $svc already running (or start failed — check rc-service $svc status)."
    fi
done

##################################################################################################################################
# 5. Add current user to lp group (required for printer access)
##################################################################################################################################

echo
tput setaf 3
echo "── User group ────────────────────────────────────────────────"
tput sgr0

if id -nG "$USER" | grep -qw lp; then
    echo "$USER is already in the lp group."
else
    echo "Adding $USER to lp group ..."
    sudo usermod -aG lp "$USER"
    tput setaf 2; echo "$USER added to lp group."; tput sgr0
    tput setaf 3; echo "NOTE: group change takes effect on next login."; tput sgr0
fi

##################################################################################################################################
# 6. Add the ET-3950 to CUPS
##################################################################################################################################

PRINTER_NAME="Epson-ET-3950"
PRINTER_URI="socket://10.0.100.103:9100"

echo
tput setaf 3
echo "── Adding printer to CUPS ────────────────────────────────────"
tput sgr0

if lpstat -p "$PRINTER_NAME" &>/dev/null; then
    echo "Printer '$PRINTER_NAME' already configured in CUPS — skipping."
else
    echo "Looking for ET-3950 PPD ..."
    PPD=$(lpinfo -m 2>/dev/null | grep -i 'ET.3950' | head -1 | awk '{print $1}')
    if [ -z "$PPD" ]; then
        tput setaf 1
        echo "ERROR: No PPD found for ET-3950. Is epson-inkjet-printer-escpr2 installed?" >&2
        tput sgr0
    else
        tput setaf 2; echo "Found PPD: $PPD"; tput sgr0
        echo "Adding '$PRINTER_NAME' at $PRINTER_URI ..."
        sudo lpadmin -p "$PRINTER_NAME" -E -v "$PRINTER_URI" -m "$PPD" -D "Epson ET-3950"
        sudo lpadmin -d "$PRINTER_NAME"
        tput setaf 2
        echo "Printer '$PRINTER_NAME' added and set as default."
        tput sgr0
    fi
fi

##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
echo "Printer management: http://localhost:631"
echo
tput sgr0
