#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Menu      : Install CUPS + Epson ET-3950 driver; add printer at 10.0.100.103
# Purpose   : Install CUPS + Epson ET-3950 driver (ESCPR2) + Avahi for network
#             printer discovery.  After running, add the printer via the CUPS
#             web UI at http://localhost:631.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

script_start "Setting up Epson ET-3950 printer + scanner"

PRINTER_IP="10.0.100.103"

##################################################################################################################################
# 1. CUPS
##################################################################################################################################

section "CUPS"
ensure_pkgs cups cups-openrc

##################################################################################################################################
# 2. Avahi — mDNS / network printer auto-discovery
##################################################################################################################################

section "Avahi (mDNS / network printer discovery)"
ensure_pkgs avahi avahi-openrc nss-mdns

# Patch /etc/nsswitch.conf so .local hostnames resolve via mDNS
if grep -q 'mdns_minimal' /etc/nsswitch.conf; then
    echo "nsswitch.conf already has mdns_minimal — skipping."
else
    echo "Patching /etc/nsswitch.conf for mDNS ..."
    sudo sed -i '/^hosts:/ s/dns/mdns_minimal [NOTFOUND=return] dns/' /etc/nsswitch.conf
    if grep -q 'mdns_minimal' /etc/nsswitch.conf; then
        ok "nsswitch.conf patched."
    else
        err "could not patch /etc/nsswitch.conf for mDNS (no 'hosts: ... dns' line?)"
    fi
fi

##################################################################################################################################
# 3. Print job manager GUI
##################################################################################################################################

section "system-config-printer"
ensure_pkgs system-config-printer

##################################################################################################################################
# 4. SANE + scanner frontends
##################################################################################################################################

section "SANE + scanner frontends (skanlite, gscan2pdf)"
ensure_pkgs sane skanlite gscan2pdf

# Add printer IP to epsonds backend so SANE can find the network scanner
EPSONDS_CONF="/etc/sane.d/epsonds.conf"
if grep -qF "net $PRINTER_IP" "$EPSONDS_CONF" 2>/dev/null; then
    echo "epsonds.conf already has $PRINTER_IP — skipping."
else
    echo "Adding $PRINTER_IP to $EPSONDS_CONF ..."
    if echo "net $PRINTER_IP" | sudo tee -a "$EPSONDS_CONF" > /dev/null; then
        ok "epsonds.conf updated."
    else
        err "could not add $PRINTER_IP to $EPSONDS_CONF — scanner won't be found"
    fi
fi

# Hooks are skipped (nohook conf) — update desktop DB manually so dmenu sees simple-scan
echo "Updating desktop database ..."
sudo update-desktop-database /usr/share/applications &>/dev/null || true
ok "Desktop database updated."

##################################################################################################################################
# 5. Epson ESCPR2 driver  (ET-3950 requires ESCPR2, not the older ESCPR)
##################################################################################################################################

section "Epson ESCPR2 driver"

DRIVER_PKG="epson-inkjet-printer-escpr2"
if ! ensure_pkgs --optional "$DRIVER_PKG"; then
    _c setaf 3
    echo "NOTE: $DRIVER_PKG isn't in the official Artix/Arch repos (AUR-only)."
    echo "      Skipping — not auto-installed from AUR by design. Options:"
    echo "        - Build manually: paru -S $DRIVER_PKG  (or yay -S $DRIVER_PKG)"
    echo "        - Or grab Epson's official .deb/.rpm from epson.com and convert with debtap/rpmextract"
    echo "      Without it, step 8 below won't find a PPD and the printer add will fail."
    _c sgr0
fi

##################################################################################################################################
# 6. Enable and start services (OpenRC)
##################################################################################################################################

section "Enabling services"
enable_service cupsd
enable_service avahi-daemon

##################################################################################################################################
# 7. Add current user to lp group (required for printer access)
##################################################################################################################################

section "User group"

if id -nG "$USER" | grep -qw lp; then
    echo "$USER is already in the lp group."
elif sudo usermod -aG lp "$USER"; then
    ok "$USER added to lp group."
    _c setaf 3; echo "NOTE: group change takes effect on next login."; _c sgr0
else
    err "could not add $USER to the lp group"
fi

##################################################################################################################################
# 8. Add the ET-3950 to CUPS
##################################################################################################################################

PRINTER_NAME="Epson-ET-3950"
PRINTER_URI="socket://$PRINTER_IP:9100"

section "Adding printer to CUPS"

if lpstat -p "$PRINTER_NAME" &>/dev/null; then
    echo "Printer '$PRINTER_NAME' already configured in CUPS — skipping."
else
    echo "Looking for ET-3950 PPD ..."
    PPD=$(lpinfo -m 2>/dev/null | grep -i 'ET.3950' | head -1 | awk '{print $1}')
    if [ -z "$PPD" ]; then
        err "No PPD found for ET-3950. Is $DRIVER_PKG installed?"
    else
        ok "Found PPD: $PPD"
        echo "Adding '$PRINTER_NAME' at $PRINTER_URI ..."
        if sudo lpadmin -p "$PRINTER_NAME" -E -v "$PRINTER_URI" -m "$PPD" -D "Epson ET-3950" \
            && sudo lpadmin -d "$PRINTER_NAME"; then
            ok "Printer '$PRINTER_NAME' added and set as default."
        else
            err "lpadmin could not add '$PRINTER_NAME'"
        fi
    fi
fi

##################################################################################################################################

script_done
echo "Printer management: http://localhost:631"
echo
