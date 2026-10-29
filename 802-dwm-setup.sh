#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Menu      : Build and install dwm + dmenu (Mod+d app launcher)
# Group     : core
# Purpose   : Set up dwm as a desktop environment option.
#             Builds github.com/zythros/dmenu and installs a j4-dmenu-desktop
#             wrapper (dmenu-desktop, what Mod+d runs), then clones
#             github.com/zythros/dwm, builds from source, installs, writes a
#             LightDM xsessions entry, disables screen blanking/DPMS
#             (~/.xprofile), writes ~/.dwm/keybindings.txt, makes
#             JetBrains Mono Nerd Font the default "monospace" font, and
#             sets a system-wide dark preference that GTK, Qt, browsers and
#             Electron apps follow, and makes alacritty the preferred
#             terminal for XFCE/GTK apps (Thunar's "Open Terminal Here").
#             Needs Xorg + LightDM already installed (800-base-desktop.sh).
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

script_start "Setting up dwm + dmenu"

##################################################################################################################################
# 1. Build + runtime dependencies (alacritty, j4-dmenu-desktop; xset for 8;
#    JetBrains Mono Nerd Font for 10; dark theme + portal for 11)
##################################################################################################################################

section "Dependencies"
ensure_pkgs base-devel libx11 libxft libxinerama alacritty j4-dmenu-desktop xorg-xset ttf-jetbrains-mono-nerd \
    gnome-themes-extra dconf xdg-desktop-portal xdg-desktop-portal-gtk

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
# 3. dmenu — zythros fork (-c center, -l grid), replaces any pacman dmenu
##################################################################################################################################

section "dmenu (zythros fork)"

if pacman -Qi dmenu &>/dev/null; then
    echo "Removing pacman dmenu (replaced by the zythros fork) ..."
    if sudo pacman -Rns --noconfirm dmenu; then
        ok "Pacman dmenu removed."
    else
        err "could not remove pacman dmenu — the fork's install may be shadowed"
    fi
fi

DMENU_SRC="$HOME/.local/src/dmenu"
git_sync https://github.com/zythros/dmenu.git "$DMENU_SRC" || die "no dmenu source — nothing to build"
echo
make_install "$DMENU_SRC" || die "dmenu build/install failed"

##################################################################################################################################
# 4. dmenu-desktop wrapper — what dwm's Mod+d runs (dmenucmd in zythros/dwm config.h)
#    j4-dmenu-desktop lists apps by .desktop display name. A wrapper is the
#    cleanest way to pass its --dmenu="..." flag (no shell escaping inside a C
#    string array), and /usr/local/bin is on dwm's PATH whatever the login
#    shell, so config.h can name it without an absolute path.
##################################################################################################################################

echo
WRAPPER="/usr/local/bin/dmenu-desktop"
echo "Writing $WRAPPER ..."
# Colors match the dwm bar (zythros/dwm config.h): col_gray1/col_gray3 for
# normal, col_cyan/col_gray4 for the selected entry.
sudo tee "$WRAPPER" > /dev/null <<'EOF' || die "could not write $WRAPPER"
#!/bin/bash
exec j4-dmenu-desktop --dmenu="dmenu -i -c -l 8 -fn 'monospace:size=12' -nb '#222222' -nf '#bbbbbb' -sb '#005577' -sf '#eeeeee'"
EOF
sudo chmod 755 "$WRAPPER"
ok "Wrapper written."

# The old 820-dmenu-setup.sh put the wrapper in ~/.local/bin and patched an
# absolute path into dwm's config.h. Remove its copy so only one exists.
OLD_WRAPPER="$HOME/.local/bin/dmenu-desktop"
if grep -qs 'exec j4-dmenu-desktop' "$OLD_WRAPPER"; then
    rm -f "$OLD_WRAPPER" && echo "Removed old wrapper $OLD_WRAPPER."
fi

##################################################################################################################################
# 5. dwm — clone or update fork, build and install
##################################################################################################################################

section "dwm"
DWM_SRC="$HOME/.local/src/dwm"

# Drop local edits (e.g. the old 820 dmenucmd patch) so the pull can't conflict
[ -d "$DWM_SRC/.git" ] && git -C "$DWM_SRC" checkout config.h
git_sync https://github.com/zythros/dwm.git "$DWM_SRC" || die "no dwm source — nothing to build"
echo
make_install "$DWM_SRC" || die "dwm build/install failed"

##################################################################################################################################
# 6. Ensure dbus is installed — dwm doesn't start a session bus itself, and
#    apps like flameshot silently fail (or don't appear at all via rofi/dmenu)
#    without one. See: dbus-launch wraps the session below.
##################################################################################################################################

if ! command -v dbus-launch &>/dev/null; then
    echo
    ensure_pkgs dbus
fi

##################################################################################################################################
# 7. Create LightDM xsessions entry (idempotent — rewritten if dbus-launch missing)
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
# 8. Disable screen blanking / DPMS in the dwm session
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
# 9. Write ~/.dwm/keybindings.txt
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
# 10. Default "monospace" font -> JetBrains Mono Nerd Font
#     dwm, dmenu (incl. the Mod+d wrapper) and 803's alacritty config all ask
#     for "monospace", so one fontconfig alias switches them all. The Mono
#     variant keeps Nerd Font icons one cell wide in terminals. A conf.d file,
#     not ~/.config/fontconfig/fonts.conf (lxqt-config-appearance owns that).
#     Loaded via 50-user.conf, ahead of 60-latin.conf's defaults.
##################################################################################################################################

echo
FONT_CONF="$HOME/.config/fontconfig/conf.d/10-monospace-jetbrains.conf"
echo "Writing $FONT_CONF ..."
mkdir -p "$(dirname "$FONT_CONF")"
cat > "$FONT_CONF" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<!-- written by artix-nemesis 802-dwm-setup.sh -->
<fontconfig>
  <alias binding="strong">
    <family>monospace</family>
    <prefer><family>JetBrainsMono Nerd Font Mono</family></prefer>
  </alias>
</fontconfig>
EOF
MONO_FONT=$(fc-match -f '%{family[0]}' monospace)
if [ "$MONO_FONT" = "JetBrainsMono Nerd Font Mono" ]; then
    ok "monospace -> $MONO_FONT (dwm/dmenu pick it up at next login, alacritty in new windows)."
else
    warn "monospace still resolves to '$MONO_FONT' — is ttf-jetbrains-mono-nerd installed?"
fi

##################################################################################################################################
# 11. Dark mode by default
#     dwm has no settings daemon, so set the preference everywhere apps look:
#       - gsettings color-scheme (dconf) -> xdg-desktop-portal-gtk serves it as
#         org.freedesktop.appearance color-scheme: Firefox, Chromium,
#         Electron and libadwaita apps follow it
#       - GTK3/4 settings.ini prefer-dark, GTK2 ~/.gtkrc-2.0 (Adwaita-dark)
#       - Qt: the gtk3 platform theme (built into qt5/qt6-base) follows GTK
#     Existing theme choices are kept: only missing files/keys are added.
##################################################################################################################################

section "Dark mode"

# gsettings needs a session bus to reach dconf; not there over ssh or a TTY
gset() {
    if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
        gsettings "$@"
    else
        dbus-run-session -- gsettings "$@"
    fi
}
if gset set org.gnome.desktop.interface color-scheme prefer-dark \
    && [ "$(gset get org.gnome.desktop.interface color-scheme)" = "'prefer-dark'" ]; then
    ok "gsettings color-scheme = prefer-dark (portal: browsers, Electron, libadwaita)."
else
    err "could not set gsettings color-scheme — is dconf installed?"
fi
if [ "$(gset get org.gnome.desktop.interface gtk-theme)" = "'Adwaita'" ]; then
    gset set org.gnome.desktop.interface gtk-theme Adwaita-dark && echo "gsettings gtk-theme = Adwaita-dark."
fi

# GTK3/4: create (GTK3 also gets Adwaita-dark; GTK4 has no installable
# themes), or add prefer-dark to an existing file
for v in 3.0 4.0; do
    GTK_INI="$HOME/.config/gtk-$v/settings.ini"
    if [ ! -f "$GTK_INI" ]; then
        mkdir -p "$(dirname "$GTK_INI")"
        {
            echo '[Settings]'
            [ "$v" = 3.0 ] && echo 'gtk-theme-name=Adwaita-dark'
            echo 'gtk-application-prefer-dark-theme=1'
        } > "$GTK_INI"
        ok "Wrote $GTK_INI (dark)."
    elif ! grep -q '^gtk-application-prefer-dark-theme' "$GTK_INI"; then
        sed -i '/^\[Settings\]/a gtk-application-prefer-dark-theme=1' "$GTK_INI"
        ok "Added prefer-dark to $GTK_INI (theme left as is)."
    else
        echo "$GTK_INI already sets prefer-dark — skipping."
    fi
done

# GTK2: only if the user has no gtkrc yet
GTKRC2="$HOME/.gtkrc-2.0"
if [ -f "$GTKRC2" ]; then
    echo "$GTKRC2 exists — leaving it alone."
else
    echo 'gtk-theme-name="Adwaita-dark"' > "$GTKRC2"
    ok "Wrote $GTKRC2 (Adwaita-dark)."
fi

# Qt: gtk3 platform theme, unless something (e.g. /etc/environment) set one
if grep -qF 'QT_QPA_PLATFORMTHEME' "$XPROFILE" 2>/dev/null; then
    echo "$XPROFILE already handles QT_QPA_PLATFORMTHEME — skipping."
else
    echo '[ -z "$QT_QPA_PLATFORMTHEME" ] && export QT_QPA_PLATFORMTHEME=gtk3  # Qt follows GTK dark theme (802-dwm-setup.sh)' >> "$XPROFILE"
    ok "Qt set to follow GTK in $XPROFILE (unless already set system-wide)."
fi

##################################################################################################################################
# 12. alacritty as the preferred terminal for XFCE/GTK apps
#     Thunar's "Open Terminal Here" (and anything using exo-open) reads
#     ~/.config/xfce4/helpers.rc and falls back to xfce4-terminal without
#     it. exo ships an alacritty helper, so naming it is enough.
##################################################################################################################################

echo
HELPERS_RC="$HOME/.config/xfce4/helpers.rc"
if grep -q '^TerminalEmulator=' "$HELPERS_RC" 2>/dev/null; then
    echo "$HELPERS_RC already names a terminal ($(grep '^TerminalEmulator=' "$HELPERS_RC" | cut -d= -f2)) — skipping."
else
    mkdir -p "$(dirname "$HELPERS_RC")"
    echo 'TerminalEmulator=alacritty' >> "$HELPERS_RC"
    ok "alacritty set as preferred terminal in $HELPERS_RC (Thunar, exo-open)."
fi

##################################################################################################################################

script_done
echo "dwm is now available as a session in LightDM."
echo "Keybindings: $KEYBINDINGS_FILE"
echo "Source:      $DWM_SRC, $DMENU_SRC"
echo "Mod+d:       $WRAPPER (j4-dmenu-desktop + zythros dmenu, dwm bar colours)"
echo "Font:        $FONT_CONF (monospace -> JetBrainsMono Nerd Font Mono)"
echo "Dark mode:   gsettings color-scheme + GTK2/3/4 + Qt (takes effect at next login / app start)"
echo "Terminal:    $HELPERS_RC (XFCE/GTK apps open alacritty)"
echo "To rebuild:  make -C $DWM_SRC clean && make -C $DWM_SRC && sudo make -C $DWM_SRC install"
echo
