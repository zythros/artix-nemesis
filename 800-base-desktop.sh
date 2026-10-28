#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Menu      : Xorg + LightDM + D-Bus — run first on a bare Artix install
# Group     : core
# Purpose   : Install the graphical base every other script assumes: Xorg,
#             the LightDM display manager (GTK greeter) and D-Bus, and enable
#             the lightdm + dbus OpenRC services.
#             Skip this if your Artix install already boots to a login screen.
#             LightDM is enabled, not started — reboot (or run
#             `sudo rc-service lightdm start`) after 802 has added dwm.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

script_start "Setting up Xorg + LightDM + D-Bus"
pkg_sync

##################################################################################################################################
# 1. Packages
##################################################################################################################################

# xorg-server         : X server (built-in modesetting driver covers most GPUs; 880/881 add NVIDIA)
# xorg-xinit          : startx, for debugging a session without LightDM
# xf86-input-libinput : keyboard/mouse/touchpad input
# mesa                : OpenGL
# ttf-dejavu          : a default "monospace" font for dwm, dmenu and alacritty
# ttf-nerd-fonts-symbols-mono : icon glyphs (e.g. slstatus's calendar icon); dwm
#                       falls back to it for characters DejaVu doesn't have
# lightdm*            : display manager + greeter + OpenRC service
# dbus-openrc         : system bus service (dwm's session bus comes from 802's dbus-launch)
PACKAGES=(
    xorg-server
    xorg-xinit
    xf86-input-libinput
    mesa
    ttf-dejavu
    ttf-nerd-fonts-symbols-mono
    lightdm
    lightdm-gtk-greeter
    lightdm-openrc
    dbus
    dbus-openrc
)

section "Packages"
ensure_pkgs "${PACKAGES[@]}" || die "base desktop packages missing"

##################################################################################################################################
# 2. Services
##################################################################################################################################

section "Services"
enable_service dbus

# Enable only: starting LightDM now would switch away from this terminal.
if rc-update show default 2>/dev/null | awk '{print $1}' | grep -qx lightdm; then
    echo "lightdm already enabled at default runlevel."
elif sudo rc-update add lightdm default; then
    ok "lightdm enabled at default runlevel (starts at next boot)."
else
    err "could not enable lightdm (rc-update add lightdm default)"
fi

##################################################################################################################################

script_done
echo "Next: run 802-dwm-setup.sh (adds the dwm session to LightDM), then reboot."
echo "Debugging without LightDM: startx (needs ~/.xinitrc with 'exec dwm')."
echo
