#!/bin/bash
#set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install base GUI applications.
#             Edit the APPS list below — comment out any line to skip that app.
#             Packages are sourced from Artix repos + Chaotic AUR (run 801 first).
#             Post-install fixups (e.g. sudo wrappers) are handled automatically.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

# ── Apps to install ───────────────────────────────────────────────────────────
# Comment out any line to skip that app.
APPS=(
    gparted              # partition editor (alacritty+sudo wrapper auto-configured)
    mullvad-browser-bin  # privacy browser
    gimp                 # image editor
    freetube             # YouTube frontend
    darktable            # RAW photo editor
    vlc                  # media player (codecs: libdvdcss libdvdread libdvdnav libbluray auto-installed)
    kdenlive             # video editor
    krename              # batch file renamer
    flameshot            # screenshot tool with annotation
    freecad              # parametric 3D CAD modeler
)
# ─────────────────────────────────────────────────────────────────────────────

if ! grep -q '^\[chaotic-aur\]' /etc/pacman.conf 2>/dev/null; then
    tput setaf 1
    echo "ERROR: Chaotic AUR is not configured. Run 801-chaotic-aur-setup.sh first." >&2
    tput sgr0
    exit 1
fi

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
while true; do sudo -v; sleep 50; done &
SUDO_KEEPALIVE=$!

artix_pacman_nohook_setup
# extend trap to also kill the sudo keepalive
trap "sudo rm -rf '$NOHOOK_DIR' '$NOHOOK_CONF'; kill $SUDO_KEEPALIVE 2>/dev/null" EXIT

##################################################################################################################################
# Helpers
##################################################################################################################################

pkg_install() {
    local pkg="$1"
    # Remove stale lock left by a previous timeout-killed pacman
    sudo rm -f /var/lib/pacman/db.lck
    # Use nohook config — avoids D-Bus hook hang on Artix/OpenRC.
    # Fall back to yay (with same nohook conf) for pure AUR packages.
    if sudo pacman --config "$NOHOOK_CONF" -S --noconfirm --needed "$pkg"; then
        return 0
    fi
    sudo rm -f /var/lib/pacman/db.lck
    if command -v yay &>/dev/null; then
        yay --config "$NOHOOK_CONF" -S --noconfirm --needed "$pkg"
        return $?
    fi
    return 1
}

# Called after each successful install; add per-app fixups here.
post_install() {
    local pkg="$1"
    case "$pkg" in
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
        echo "$app already installed — skipping."
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
