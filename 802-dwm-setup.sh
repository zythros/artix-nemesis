#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Menu      : Build and install dwm window manager
# Purpose   : Set up dwm as a desktop environment option.
#             Clones github.com/zythros/dwm, builds from source, installs,
#             writes a LightDM xsessions entry, disables screen blanking/DPMS
#             (~/.xprofile), and writes ~/.dwm/keybindings.txt.
#             Note: Arch [extra] repo must be present (added by 880 or 881) for dmenu.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

script_start "Setting up dwm"

##################################################################################################################################
# 1. Build + runtime dependencies (alacritty, dmenu; xset for 6b)
##################################################################################################################################

section "Dependencies"
ensure_pkgs base-devel libx11 libxft libxinerama alacritty dmenu xorg-xset

##################################################################################################################################
# 2. mullvad-browser (Mod+m) — only if Chaotic AUR is already enabled
#    mullvad-browser-bin isn't in the official repos. Chaotic AUR stays
#    opt-in (801), so this never adds it — just skips when it's absent.
##################################################################################################################################

echo
if pacman -Q mullvad-browser-bin &>/dev/null; then
    echo "mullvad-browser already installed."
elif grep -q '^\[chaotic-aur\]' /etc/pacman.conf; then
    ensure_pkgs --optional mullvad-browser-bin || warn "Mod+m won't launch anything without mullvad-browser-bin"
else
    _c setaf 3
    echo "Chaotic AUR not enabled — skipping mullvad-browser (Mod+m won't launch anything)."
    echo "To get it: run 801-chaotic-aur-setup.sh, then re-run this script."
    _c sgr0
fi

##################################################################################################################################
# 3. Clone or update fork
##################################################################################################################################

section "dwm source"
DWM_SRC="$HOME/.local/src/dwm"

# Drop local patches (e.g. 820's dmenucmd) so the pull can't conflict; 820 re-applies its own
[ -d "$DWM_SRC/.git" ] && git -C "$DWM_SRC" checkout config.h
git_sync https://github.com/zythros/dwm.git "$DWM_SRC" || die "no dwm source — nothing to build"

##################################################################################################################################
# 4. Build and install
##################################################################################################################################

echo
make_install "$DWM_SRC" || die "dwm build/install failed"

##################################################################################################################################
# 5. Ensure dbus is installed — dwm doesn't start a session bus itself, and
#    apps like flameshot silently fail (or don't appear at all via rofi/dmenu)
#    without one. See: dbus-launch wraps the session below.
##################################################################################################################################

if ! command -v dbus-launch &>/dev/null; then
    echo
    ensure_pkgs dbus
fi

##################################################################################################################################
# 6. Create LightDM xsessions entry (idempotent — rewritten if dbus-launch missing)
##################################################################################################################################

echo
SESSION_FILE="/usr/share/xsessions/dwm.desktop"

if [ -f "$SESSION_FILE" ] && grep -qF 'dbus-launch' "$SESSION_FILE"; then
    echo "$SESSION_FILE already exists and wraps dbus-launch — skipping."
else
    echo "Writing $SESSION_FILE ..."
    # Doesn't exist on a fresh install with no other desktop session installed.
    sudo mkdir -p "$(dirname "$SESSION_FILE")"
    if sudo tee "$SESSION_FILE" > /dev/null <<'EOF'
[Desktop Entry]
Name=dwm
Comment=Dynamic Window Manager
Exec=dbus-launch --exit-with-session dwm
Type=Application
EOF
    then
        ok "Session entry created (dwm now runs under a D-Bus session — fixes flameshot and other D-Bus-dependent apps)."
    else
        err "could not write $SESSION_FILE — dwm won't appear in LightDM"
    fi
fi

##################################################################################################################################
# 6b. Disable screen blanking / DPMS in the dwm session
#     X defaults to blanking after 10 min and DPMS-off after that; dwm has no
#     power settings of its own. LightDM's Xsession sources ~/.xprofile at login.
#     Not done via xorg.conf.d ServerFlags: 880's 99-nvidia-flags.conf already
#     has a ServerFlags section and only one wins.
##################################################################################################################################

echo
XPROFILE="$HOME/.xprofile"
if grep -qF 'xset s off -dpms' "$XPROFILE" 2>/dev/null; then
    echo "$XPROFILE already disables screen blanking — skipping."
else
    echo 'xset s off -dpms  # no screen blanking / monitor sleep (802-dwm-setup.sh)' >> "$XPROFILE"
    ok "Screen blanking disabled in $XPROFILE (takes effect at next login)."
fi

##################################################################################################################################
# 7. Write ~/.dwm/keybindings.txt
##################################################################################################################################

echo
KEYBINDINGS_FILE="$HOME/.dwm/keybindings.txt"
mkdir -p "$HOME/.dwm"

echo "Writing $KEYBINDINGS_FILE ..."
cat > "$KEYBINDINGS_FILE" <<'EOF'
dwm keybindings  (Mod = Super / Windows key)
=============================================

Launching
  Mod + Return          alacritty (terminal)
  Mod + Shift + Return  thunar (file manager)
  Mod + d               dmenu (run launcher)
  Mod + Shift + d       rofi (run launcher)
  Mod + m               mullvad-browser (needs Chaotic AUR)
  Mod + s               flameshot (screenshot)

Windows
  Mod + j               focus next window
  Mod + k               focus previous window
  Mod + Shift + c       close focused window
  Mod + Shift + Space   toggle floating

Layout
  Mod + t               tile layout
  Mod + f               floating layout
  Mod + h               shrink master area
  Mod + l               expand master area
  Mod + i               increase master count

Tags (workspaces)
  Mod + Left            previous tag (wrap)
  Mod + Right           next tag (wrap)
  Mod + 1-9             view tag
  Mod + Shift + 1-9     move window to tag
  Mod + Ctrl + 1-9      toggle tag view
  Mod + 0               view all tags
  Mod + Shift + 0       move window to all tags
  Mod + Tab             toggle last tag

Bar
  Mod + b               toggle bar

Multi-monitor
  Mod + ,               focus previous monitor
  Mod + .               focus next monitor
  Mod + Shift + ,       move window to previous monitor
  Mod + Shift + .       move window to next monitor

Wallpaper
  Mod + w               next wallpaper
  Mod + Shift + w       previous wallpaper

System
  Mod + Space           show this file
  Mod + Shift + q       quit dwm
EOF

ok "Keybindings file written."

##################################################################################################################################

script_done
echo "dwm is now available as a session in LightDM."
echo "Keybindings: $KEYBINDINGS_FILE"
echo "Source:      $DWM_SRC"
echo "To rebuild:  make -C $DWM_SRC clean && make -C $DWM_SRC && sudo make -C $DWM_SRC install"
echo
