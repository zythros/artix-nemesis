#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install OpenRGB and set all RGB hardware (fans, RAM, GPU, keyboard) to a static color at boot.
#             Uses /etc/local.d/rgb.start (OpenRC local service) to apply the color on every boot.
#             i2c-dev is loaded in the boot script so OpenRGB can reach RAM RGB controllers over SMBus.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

RGB_COLOR="ff8000"

if [ "$DEBUG" = true ]; then
    echo
    echo "------------------------------------------------------------"
    echo "Running $(basename $0)"
    echo "------------------------------------------------------------"
    echo
    read -n 1 -s -r -p "Debug mode is on. Press any key to continue..."
    echo
fi

echo
tput setaf 2
echo "########################################################################"
echo "################### RGB setup"
echo "########################################################################"
tput sgr0
echo

##################################################################################################################################
# Authenticate sudo once; keepalive prevents expiry during install
##################################################################################################################################

sudo -v
while true; do timeout 30 sudo -v; sleep 50; done &
SUDO_KEEPALIVE=$!

artix_pacman_nohook_setup
trap "artix_pacman_cleanup; kill $SUDO_KEEPALIVE 2>/dev/null" EXIT

##################################################################################################################################
# Step 1: Install OpenRGB
##################################################################################################################################

echo
tput setaf 3
echo "── Installing OpenRGB ───────────────────────────────────────────────────"
tput sgr0

pkg_install openrgb && { tput setaf 2; echo "  openrgb installed."; tput sgr0; } || {
    tput setaf 1; echo "ERROR: failed to install openrgb" >&2; tput sgr0; exit 1
}

# Reload udev rules so the openrgb USB rules (60-openrgb.rules) take effect immediately
# udevadm trigger can hang on eudev/Artix waiting for uevent processing — cap it
sudo udevadm control --reload-rules
sudo timeout 10 udevadm trigger 2>/dev/null || true

##################################################################################################################################
# Step 2: Write /etc/local.d/rgb.start
##################################################################################################################################

echo
tput setaf 3
echo "── Writing /etc/local.d/rgb.start ───────────────────────────────────────"
tput sgr0

sudo tee /etc/local.d/rgb.start > /dev/null <<EOF
#!/bin/sh
# i2c-dev is required for OpenRGB to reach RAM RGB controllers over SMBus
modprobe i2c-dev
# Allow USB devices (keyboard, fan hub) time to enumerate before OpenRGB scans
sleep 5
# Resize ASUS Aura Addressable zones on device 2 (motherboard) to 100 LEDs each.
# Zones 1-3 map to Aura Addressable 1-3 headers; fans and PSU light strip are
# connected via the Fractal case ARGB hub. LED count intentionally overshoots --
# single static color makes the exact count irrelevant.
openrgb --device 2 --zone 1 --size 100
openrgb --device 2 --zone 2 --size 100
openrgb --device 2 --zone 3 --size 100
openrgb --mode static --color ${RGB_COLOR}
EOF

sudo chmod +x /etc/local.d/rgb.start
tput setaf 2; echo "  /etc/local.d/rgb.start written (color: #${RGB_COLOR})."; tput sgr0

##################################################################################################################################
# Step 3: Apply color now
##################################################################################################################################

echo
tput setaf 3
echo "── Applying color now ────────────────────────────────────────────────────"
tput sgr0

sudo modprobe i2c-dev 2>/dev/null || true

if sudo openrgb --mode static --color "$RGB_COLOR"; then
    tput setaf 2; echo "  RGB set to #${RGB_COLOR}."; tput sgr0
else
    tput setaf 3
    echo "  WARNING: openrgb exited non-zero — some devices may not be detected yet."
    echo "  Check detected hardware:  openrgb --list-devices"
    echo "  The boot script will retry on next boot."
    tput sgr0
fi

##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
tput setaf 2
echo "RGB hardware will be set to #${RGB_COLOR} on every boot via /etc/local.d/rgb.start."
echo "To change the color, edit RGB_COLOR in this script and rerun, or edit /etc/local.d/rgb.start directly."
echo "To check detected devices:  openrgb --list-devices"
tput sgr0
echo
