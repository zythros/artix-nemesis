#!/bin/bash
#set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install base GUI applications.
#             Edit the APPS list below — comment out any line to skip that app.
#             Packages are sourced from official Artix/Arch repos only — no AUR
#             or Chaotic AUR required. Anything AUR-only is commented out below;
#             uncomment it yourself only if you've deliberately opted into 801.
#             Post-install fixups (e.g. sudo wrappers) are handled automatically.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

# ── Apps to install ───────────────────────────────────────────────────────────
# Comment out any line to skip that app.
APPS=(
    fish                 # login shell (chsh + fish_add_path ~/.local/bin auto-configured)
    ttf-jetbrains-mono-nerd  # sets JetBrainsMono Nerd Font as default "monospace" (fontconfig)
    gparted              # partition editor (alacritty+sudo wrapper auto-configured)
    mullvad-browser-bin  # privacy browser
    gimp                 # image editor
    freetube             # YouTube frontend
    darktable            # RAW photo editor
    vlc                  # media player (codecs: libdvdcss libdvdread libdvdnav libbluray libaacs auto-installed)
    kdenlive             # video editor
    krename              # batch file renamer
    flameshot            # screenshot tool with annotation
    rofi                 # app launcher (bound to Mod+d in dwm's config.h)
    freecad              # parametric 3D CAD modeler
    cifs-utils           # SMB/CIFS share mounting (fstab + manual)
    podman               # rootless container engine (shared-root-mount OpenRC fixup auto-configured)
    distrobox            # run other distros' containers as if native (needs podman above)
    # sublime-text-4      # text editor — AUR/chaotic-aur only, disabled by default (run 801 + uncomment to opt in)
    python-yaml          # dep: blood-pressure-tracker
    python-matplotlib    # dep: blood-pressure-tracker
)
# ─────────────────────────────────────────────────────────────────────────────

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
echo "################### Installing base apps"
echo "########################################################################"
tput sgr0
echo

##################################################################################################################################
# Authenticate sudo once up front; keepalive prevents expiry during long installs
##################################################################################################################################

sudo -v
while true; do timeout 30 sudo -v; sleep 50; done &
SUDO_KEEPALIVE=$!

artix_pacman_nohook_setup
# extend trap to also kill the sudo keepalive
trap "artix_pacman_cleanup; kill $SUDO_KEEPALIVE 2>/dev/null" EXIT
sudo pacman --config "$NOHOOK_CONF" -Sy

##################################################################################################################################
# Helpers
##################################################################################################################################

# Called after each successful install; add per-app fixups here.
post_install() {
    local pkg="$1"
    case "$pkg" in
        ttf-jetbrains-mono-nerd)
            # Set as the default "monospace" font (per-user, via fontconfig) so
            # dwm's bar, alacritty, dmenu, and rofi all pick it up automatically —
            # they already just reference the generic "monospace" family.
            FONTCONFIG_CONF="$HOME/.config/fontconfig/fonts.conf"
            mkdir -p "$(dirname "$FONTCONFIG_CONF")"
            if grep -qF 'JetBrainsMono Nerd Font' "$FONTCONFIG_CONF" 2>/dev/null; then
                echo "  → fontconfig already prefers JetBrainsMono Nerd Font — skipping."
            elif [ -f "$FONTCONFIG_CONF" ]; then
                tput setaf 3
                echo "  → WARNING: $FONTCONFIG_CONF already exists with other content — not auto-editing." >&2
                echo "    Add this <match> block inside <fontconfig>...</fontconfig> manually:"
                echo '      <match target="pattern"><test name="family"><string>monospace</string></test><edit name="family" mode="prepend" binding="strong"><string>JetBrainsMono Nerd Font</string></edit></match>'
                tput sgr0
            else
                tput setaf 6
                echo "  → writing $FONTCONFIG_CONF ..."
                tput sgr0
                cat > "$FONTCONFIG_CONF" <<'FONTCONF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="pattern">
    <test name="family"><string>monospace</string></test>
    <edit name="family" mode="prepend" binding="strong"><string>JetBrainsMono Nerd Font</string></edit>
  </match>
</fontconfig>
FONTCONF
                tput setaf 2
                echo "  → JetBrainsMono Nerd Font set as default monospace."
                tput sgr0
            fi
            # Hooks are skipped (nohook conf) — rebuild the font cache manually
            fc-cache -f &>/dev/null || true
            ;;
        vlc)
            # Codec packages not always pulled in as hard deps
            local codecs=(libdvdcss libdvdread libdvdnav libbluray)
            tput setaf 6
            echo "  → installing VLC codec packages: ${codecs[*]}"
            tput sgr0
            for codec in "${codecs[@]}"; do
                if pacman -Q "$codec" &>/dev/null; then
                    echo "    $codec already installed — skipping."
                else
                    pkg_install "$codec" && echo "    $codec installed." || echo "    WARNING: $codec failed." >&2
                fi
            done
            ;;
        fish)
            # Set fish as the login shell
            if [ "$(getent passwd "$USER" | cut -d: -f7)" != "/usr/bin/fish" ]; then
                tput setaf 6
                echo "  → setting fish as login shell (chsh) ..."
                tput sgr0
                chsh -s /usr/bin/fish
            else
                echo "  → fish already the login shell — skipping chsh."
            fi
            # Ensure ~/.local/bin is in fish PATH
            FISH_CONF="$HOME/.config/fish/config.fish"
            mkdir -p "$(dirname "$FISH_CONF")"
            if grep -qF "fish_add_path ~/.local/bin" "$FISH_CONF" 2>/dev/null; then
                echo "  → fish_add_path already in config.fish — skipping."
            else
                tput setaf 6
                echo "  → adding fish_add_path ~/.local/bin to $FISH_CONF ..."
                tput sgr0
                cat >> "$FISH_CONF" <<'FISHCONF'
if status is-interactive
    fish_add_path ~/.local/bin
end
FISHCONF
            fi
            ;;
        gparted)
            # polkit service not available on Artix — run via alacritty+sudo instead
            local desktop="$HOME/.local/share/applications/gparted.desktop"
            mkdir -p "$(dirname "$desktop")"
            cat > "$desktop" <<'EOF'
[Desktop Entry]
Name=GParted
GenericName=Partition Editor
Comment=Create, reorganize, and delete partitions
Exec=alacritty -e sudo gparted %f
Icon=gparted
Terminal=false
Type=Application
Categories=System;Filesystem;
Keywords=Partition;
StartupNotify=true
EOF
            tput setaf 6
            echo "  → wrote $desktop (alacritty+sudo wrapper)"
            tput sgr0
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
                tput setaf 6
                echo "  → set useX11LegacyScreenshot=true in $FLAMESHOT_CONF"
                tput sgr0
            fi
            ;;
        podman)
            # Rootless podman/distrobox need "/" to have shared mount propagation.
            # systemd sets this automatically at boot; OpenRC does not, so podman
            # warns `"/" is not a shared mount` and rootless container mounts can
            # break. Fix: a small custom OpenRC service that runs
            # `mount --make-rshared /` at boot — same pattern as
            # 835-spacemouse-setup.sh's spacenavd service.
            SHARED_ROOT_SVC="/etc/init.d/shared-root"
            if [ -f "$SHARED_ROOT_SVC" ]; then
                echo "  → $SHARED_ROOT_SVC already exists — skipping."
            else
                tput setaf 6
                echo "  → writing $SHARED_ROOT_SVC ..."
                tput sgr0
                sudo tee "$SHARED_ROOT_SVC" > /dev/null <<'RCEOF'
#!/sbin/openrc-run

description="Mark / as a shared mount (required for podman/distrobox rootless mounts)"

depend() {
    need localmount
}

start() {
    ebegin "Marking / as a shared mount"
    mount --make-rshared /
    eend $?
}
RCEOF
                sudo chmod 755 "$SHARED_ROOT_SVC"
                tput setaf 2
                echo "  → $SHARED_ROOT_SVC written."
                tput sgr0
            fi

            sudo rc-update add shared-root default 2>/dev/null || true
            echo "  → shared-root enabled at default runlevel."

            if sudo rc-service shared-root start 2>/dev/null; then
                tput setaf 2
                echo "  → / is now a shared mount."
                tput sgr0
            else
                echo "  → shared-root already applied (or start failed — check: sudo rc-service shared-root status)."
            fi
            ;;
    esac
}

##################################################################################################################################
# Install loop
##################################################################################################################################

FAILED=()

for app in "${APPS[@]}"; do
    echo
    tput setaf 3
    echo "── $app ──────────────────────────────────────────"
    tput sgr0

    if pacman -Q "$app" &>/dev/null; then
        echo "$app already installed — skipping install, but re-applying post-install fixups."
        post_install "$app"
        continue
    fi

    echo "Installing $app ..."
    pkg_install "$app" || true  # timeout/hook failures don't abort — check pacman -Q as truth
    if pacman -Q "$app" &>/dev/null; then
        tput setaf 2
        echo "$app installed."
        tput sgr0
        post_install "$app"
    else
        tput setaf 1
        echo "ERROR: $app installation failed." >&2
        tput sgr0
        FAILED+=("$app")
    fi
done

##################################################################################################################################
# Deploy alacritty config
##################################################################################################################################

ALACRITTY_CONF="$HOME/.config/alacritty/alacritty.toml"
if grep -qF '#0a0a0a' "$ALACRITTY_CONF" 2>/dev/null; then
    echo "alacritty config already in place — skipping."
else
    mkdir -p "$(dirname "$ALACRITTY_CONF")"
    tput setaf 6
    echo "Writing alacritty config ..."
    tput sgr0
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
    tput setaf 2
    echo "  → wrote $ALACRITTY_CONF"
    tput sgr0
fi

##################################################################################################################################
# Install blood-pressure-tracker (Python CLI from GitHub source)
##################################################################################################################################

BP_WRAPPER="$HOME/.local/bin/bp-tracker"
if [ -f "$BP_WRAPPER" ]; then
    echo "bp-tracker already installed — skipping."
else
    tput setaf 6
    echo "Installing blood-pressure-tracker ..."
    tput sgr0
    BP_SRC="$HOME/.local/src/bp-tracker"
    rm -rf "$BP_SRC"
    git clone https://github.com/zythros/blood-pressure-tracker "$BP_SRC"
    export PATH="$HOME/.local/bin:$PATH"
    bash "$BP_SRC/install.sh"
    tput setaf 2
    echo "  → bp-tracker installed."
    tput sgr0
fi

##################################################################################################################################
# Run desktop/icon hooks manually now that all installs are complete
##################################################################################################################################

echo
echo "Updating desktop database and icon caches ..."
sudo update-desktop-database &>/dev/null || true
sudo gtk-update-icon-cache -f /usr/share/icons/hicolor &>/dev/null || true
tput setaf 2
echo "Done."
tput sgr0

##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo

if [ ${#FAILED[@]} -gt 0 ]; then
    tput setaf 1
    echo "The following apps failed to install:"
    for f in "${FAILED[@]}"; do
        echo "  - $f"
    done
    tput sgr0
else
    tput setaf 2
    echo "All apps installed successfully."
    tput sgr0
fi

echo
tput sgr0
