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
echo "################### Setting up Epson ET-3950 printer + scanner"
echo "########################################################################"
tput sgr0
echo

##################################################################################################################################
# Authenticate sudo once; keepalive prevents expiry during installs
##################################################################################################################################

sudo -v
while true; do timeout 30 sudo -v; sleep 50; done &
SUDO_KEEPALIVE=$!

artix_pacman_nohook_setup
trap "artix_pacman_cleanup; kill $SUDO_KEEPALIVE 2>/dev/null" EXIT

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
# 3. Print job manager GUI
##################################################################################################################################

echo
tput setaf 3
echo "── system-config-printer ─────────────────────────────────────"
tput sgr0

if pacman -Q system-config-printer &>/dev/null; then
    echo "system-config-printer already installed — skipping."
else
    echo "Installing system-config-printer ..."
    pkg_install system-config-printer || true
    if pacman -Q system-config-printer &>/dev/null; then
        tput setaf 2; echo "system-config-printer installed."; tput sgr0
    else
        tput setaf 1; echo "ERROR: system-config-printer installation failed." >&2; tput sgr0
    fi
fi

##################################################################################################################################
# 4. SANE + Simple Scan (scanner support)
##################################################################################################################################

echo
tput setaf 3
echo "── SANE + scanner frontends (skanlite, gscan2pdf) ───────────"
tput sgr0

for pkg in sane skanlite gscan2pdf; do
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

# Add printer IP to epsonds backend so SANE can find the network scanner
EPSONDS_CONF="/etc/sane.d/epsonds.conf"
PRINTER_IP="10.0.100.103"
if grep -qF "net $PRINTER_IP" "$EPSONDS_CONF" 2>/dev/null; then
    echo "epsonds.conf already has $PRINTER_IP — skipping."
else
    echo "Adding $PRINTER_IP to $EPSONDS_CONF ..."
    echo "net $PRINTER_IP" | sudo tee -a "$EPSONDS_CONF" > /dev/null
    tput setaf 2; echo "epsonds.conf updated."; tput sgr0
fi

# Hooks are skipped (nohook conf) — update desktop DB manually so dmenu sees simple-scan
echo "Updating desktop database ..."
sudo update-desktop-database /usr/share/applications &>/dev/null || true
tput setaf 2; echo "Desktop database updated."; tput sgr0

##################################################################################################################################
# 5. Epson ESCPR2 driver  (ET-3950 requires ESCPR2, not the older ESCPR)
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
# 6. Enable and start services (OpenRC)
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
# 7. Add current user to lp group (required for printer access)
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
# 8. Add the ET-3950 to CUPS
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
