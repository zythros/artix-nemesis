#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Menu      : Install OpenRGB; set all RGB hardware to #ff8000 at boot
# Group     : hardware
# Purpose   : Install OpenRGB and set all RGB hardware (fans, RAM, GPU, keyboard) to a static color at boot.
#             Uses /etc/local.d/rgb.start (OpenRC local service) to apply the color on every boot.
#             i2c-dev is loaded in the boot script so OpenRGB can reach RAM RGB controllers over SMBus.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

# Static colour (hex, no #) applied to every detected RGB device
RGB_COLOR="ff8000"

# Addressable zones to resize before setting the colour. Device 2 is the
# ASUS Aura motherboard controller on artix-pc; zones 1-3 are its Aura
# Addressable headers. Find yours with: openrgb --list-devices
# Set AURA_ZONES="" to skip resizing.
AURA_DEVICE=2
AURA_ZONES="1 2 3"
AURA_ZONE_SIZE=100   # intentionally overshoots — one static colour makes the exact count irrelevant

##################################################################################################################################

ZONE_CMDS=""
for zone in $AURA_ZONES; do
    ZONE_CMDS+="openrgb --device $AURA_DEVICE --zone $zone --size $AURA_ZONE_SIZE"$'\n'
done

script_start "RGB setup"

##################################################################################################################################
# Step 1: Install OpenRGB
##################################################################################################################################

section "Installing OpenRGB"
ensure_arch_extra   # openrgb is only in Arch [extra]
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
# Resize addressable zones (fans and PSU light strip hang off the case ARGB hub)
${ZONE_CMDS}openrgb --mode static --color ${RGB_COLOR}
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
