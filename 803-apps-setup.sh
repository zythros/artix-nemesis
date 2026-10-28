#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Menu      : Install preferred apps
# Group     : core
# Purpose   : Install base GUI applications.
#             Edit the APPS list below — comment out any line to skip that app.
#             Packages are sourced from official Artix/Arch repos only — no AUR
#             or Chaotic AUR. AUR-only apps are deliberately not listed here.
#             Post-install fixups (e.g. config tweaks) are handled automatically.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

# ── Apps to install ───────────────────────────────────────────────────────────
# Comment out any line to skip that app.
APPS=(
    fish                 # login shell (chsh + fish_add_path ~/.local/bin auto-configured)
    vlc                  # media player (codecs: libdvdcss libdvdread libdvdnav libbluray libaacs auto-installed)
    kdenlive             # video editor
    krename              # batch file renamer
    flameshot            # screenshot tool with annotation
    rofi                 # app launcher (bound to Mod+Shift+d in dwm's config.h)
    cifs-utils           # SMB/CIFS share mounting (fstab + manual)
    connman-gtk          # GUI for connman (already installed/running on Artix by default; standalone window, no systray needed)
    python-yaml          # dep: blood-pressure-tracker
    python-matplotlib    # dep: blood-pressure-tracker
)
# ─────────────────────────────────────────────────────────────────────────────

script_start "Installing base apps"
pkg_sync

##################################################################################################################################
# Helpers
##################################################################################################################################

# Called after each successful install; add per-app fixups here.
post_install() {
    local pkg="$1"
    case "$pkg" in
        vlc)
            # Codec packages not always pulled in as hard deps
            local codecs=(libdvdcss libdvdread libdvdnav libbluray)
            info "  → installing VLC codec packages: ${codecs[*]}"
            ensure_pkgs --optional "${codecs[@]}"
            ;;
        fish)
            # Set fish as the login shell
            if [ "$(getent passwd "$USER" | cut -d: -f7)" != "/usr/bin/fish" ]; then
                info "  → setting fish as login shell (chsh) ..."
                chsh -s /usr/bin/fish || err "chsh failed — fish is not the login shell (run: chsh -s /usr/bin/fish)"
            else
                echo "  → fish already the login shell — skipping chsh."
            fi
            # Ensure ~/.local/bin is in fish PATH
            FISH_CONF="$HOME/.config/fish/config.fish"
            mkdir -p "$(dirname "$FISH_CONF")"
            if grep -qF "fish_add_path ~/.local/bin" "$FISH_CONF" 2>/dev/null; then
                echo "  → fish_add_path already in config.fish — skipping."
            else
                info "  → adding fish_add_path ~/.local/bin to $FISH_CONF ..."
                cat >> "$FISH_CONF" <<'FISHCONF'
if status is-interactive
    fish_add_path ~/.local/bin
end
FISHCONF
            fi
            ;;
        connman-gtk)
            # Defaults to a status/tray icon and can start minimized to it —
            # dwm has no systray (same gap that rules out nm-applet), so the
            # window never appears. --no-icon skips the tray icon entirely.
            local desktop="$HOME/.local/share/applications/connman-gtk.desktop"
            mkdir -p "$(dirname "$desktop")"
            cat > "$desktop" <<'EOF'
[Desktop Entry]
Name=ConnMan GTK
GenericName=Network Connection Manager
Comment=Manage Wi-Fi and Ethernet connections via connman
Exec=connman-gtk --no-icon
Icon=connman-gtk
Terminal=false
Type=Application
Categories=Network;
Keywords=Network;WiFi;Wireless;
StartupNotify=true
EOF
            info "  → wrote $desktop (--no-icon, no systray in dwm)"
            ;;
        flameshot)
            # On X11 + dwm (no xdg-desktop-portal Screenshot backend), flameshot's
            # portal-based capture times out after 30s and fails. Force the legacy
            # X11 capture path instead. See flameshot-org/flameshot#4737.
            FLAMESHOT_CONF="$HOME/.config/flameshot/flameshot.ini"
            mkdir -p "$(dirname "$FLAMESHOT_CONF")"
            if grep -q '^useX11LegacyScreenshot=true' "$FLAMESHOT_CONF" 2>/dev/null; then
                echo "  → flameshot.ini already has useX11LegacyScreenshot=true — skipping."
            else
                if [ ! -f "$FLAMESHOT_CONF" ]; then
                    printf '[General]\nuseX11LegacyScreenshot=true\n' > "$FLAMESHOT_CONF"
                elif grep -q '^useX11LegacyScreenshot=' "$FLAMESHOT_CONF"; then
                    sed -i 's/^useX11LegacyScreenshot=.*/useX11LegacyScreenshot=true/' "$FLAMESHOT_CONF"
                elif grep -q '^\[General\]' "$FLAMESHOT_CONF"; then
                    sed -i '/^\[General\]/a useX11LegacyScreenshot=true' "$FLAMESHOT_CONF"
                else
                    printf '[General]\nuseX11LegacyScreenshot=true\n' >> "$FLAMESHOT_CONF"
                fi
                info "  → set useX11LegacyScreenshot=true in $FLAMESHOT_CONF"
            fi
            ;;
    esac
}

##################################################################################################################################
# Install loop
##################################################################################################################################

for app in "${APPS[@]}"; do
    section "$app"
    # Post-install fixups are re-applied even if the app was already installed
    ensure_pkgs "$app" && post_install "$app"
done

##################################################################################################################################
# Deploy alacritty config
##################################################################################################################################

ALACRITTY_CONF="$HOME/.config/alacritty/alacritty.toml"
if grep -qF '#0a0a0a' "$ALACRITTY_CONF" 2>/dev/null; then
    echo "alacritty config already in place — skipping."
else
    mkdir -p "$(dirname "$ALACRITTY_CONF")"
    info "Writing alacritty config ..."
    cat > "$ALACRITTY_CONF" <<'ALACRITTYCONF'
[font]
size = 14.0

[font.normal]
family = "monospace"
style = "Regular"

[font.bold]
family = "monospace"
style = "Bold"

[font.italic]
family = "monospace"
style = "Italic"

[window]
padding.x = 8
padding.y = 8
decorations = "full"

[scrolling]
history = 10000

[cursor]
style.shape = "Block"
unfocused_hollow = true

[colors.primary]
background = "#0a0a0a"
foreground = "#d0d2d0"

[colors.normal]
black   = "#1a1a1a"
red     = "#e06c6c"
green   = "#39d353"
yellow  = "#f5c050"
blue    = "#3b9eff"
magenta = "#c87ed8"
cyan    = "#5ec4bd"
white   = "#d0d2d0"

[colors.bright]
black   = "#888888"
red     = "#ff7878"
green   = "#57ff6e"
yellow  = "#ffd855"
blue    = "#5bc8ff"
magenta = "#dc9af5"
cyan    = "#7ee8dd"
white   = "#ffffff"
ALACRITTYCONF
    ok "  → wrote $ALACRITTY_CONF"
fi

##################################################################################################################################
# Install blood-pressure-tracker (Python CLI from GitHub source)
##################################################################################################################################

BP_WRAPPER="$HOME/.local/bin/bp-tracker"
if [ -f "$BP_WRAPPER" ]; then
    echo "bp-tracker already installed — skipping."
else
    info "Installing blood-pressure-tracker ..."
    BP_SRC="$HOME/.local/src/bp-tracker"
    rm -rf "$BP_SRC"
    export PATH="$HOME/.local/bin:$PATH"
    if git clone https://github.com/zythros/blood-pressure-tracker "$BP_SRC" \
        && bash "$BP_SRC/install.sh"; then
        ok "  → bp-tracker installed."
    else
        err "blood-pressure-tracker install failed"
    fi
fi

##################################################################################################################################
# Run desktop/icon hooks manually now that all installs are complete
##################################################################################################################################

echo
echo "Updating desktop database and icon caches ..."
sudo update-desktop-database &>/dev/null || true
sudo gtk-update-icon-cache -f /usr/share/icons/hicolor &>/dev/null || true
ok "Done."

##################################################################################################################################

script_done
