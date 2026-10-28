#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Menu      : Install OpenRGB; set all RGB hardware to #ff8000 at boot
# Purpose   : Install OpenRGB and set all RGB hardware (fans, RAM, GPU, keyboard) to a static color at boot.
#             Uses /etc/local.d/rgb.start (OpenRC local service) to apply the color on every boot.
#             i2c-dev is loaded in the boot script so OpenRGB can reach RAM RGB controllers over SMBus.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

RGB_COLOR="ff8000"

script_start "RGB setup"

##################################################################################################################################
# Step 1: Install OpenRGB
##################################################################################################################################

section "Installing OpenRGB"
ensure_pkgs openrgb || die "openrgb is required"

# Reload udev rules so the openrgb USB rules (60-openrgb.rules) take effect immediately
# udevadm trigger can hang on eudev/Artix waiting for uevent processing — cap it
sudo udevadm control --reload-rules
sudo timeout 10 udevadm trigger 2>/dev/null || true

##################################################################################################################################
# Step 2: Write /etc/local.d/rgb.start
##################################################################################################################################

section "Writing /etc/local.d/rgb.start"

sudo tee /etc/local.d/rgb.start > /dev/null <<EOF || die "could not write /etc/local.d/rgb.start"
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
ok "  /etc/local.d/rgb.start written (color: #${RGB_COLOR})."

##################################################################################################################################
# Step 3: Apply color now
##################################################################################################################################

section "Applying color now"

sudo modprobe i2c-dev 2>/dev/null || true

if sudo openrgb --mode static --color "$RGB_COLOR"; then
    ok "  RGB set to #${RGB_COLOR}."
else
    # Not an error: the boot script retries once USB devices have enumerated
    warn "openrgb exited non-zero — some devices may not be detected yet (check: openrgb --list-devices; the boot script retries on next boot)"
fi

##################################################################################################################################

script_done
echo "RGB hardware will be set to #${RGB_COLOR} on every boot via /etc/local.d/rgb.start."
echo "To change the color, edit RGB_COLOR in this script and rerun, or edit /etc/local.d/rgb.start directly."
echo "To check detected devices:  openrgb --list-devices"
echo
