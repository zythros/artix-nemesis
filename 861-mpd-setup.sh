#!/bin/bash
#set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install MPD (Music Player Daemon) + rmpc TUI client; configure
#             MPD as a system service (OpenRC).
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

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
echo "################### Setting up MPD + rmpc"
echo "########################################################################"
tput sgr0
echo

##################################################################################################################################
# Authenticate sudo once; keepalive prevents expiry during installs
##################################################################################################################################

sudo -v
while true; do timeout 30 sudo -v; sleep 50; done &
SUDO_KEEPALIVE=$!

artix_pacman_nohook_setup
trap "artix_pacman_cleanup; kill $SUDO_KEEPALIVE 2>/dev/null" EXIT

##################################################################################################################################
# 1. MPD
##################################################################################################################################

echo
tput setaf 3
echo "── MPD ───────────────────────────────────────────────────────"
tput sgr0

for pkg in mpd mpd-openrc; do
    if pacman -Q "$pkg" &>/dev/null; then
        echo "$pkg already installed — skipping."
    else
        echo "Installing $pkg ..."
        pkg_install "$pkg" || true
        if pacman -Q "$pkg" &>/dev/null; then
            tput setaf 2; echo "$pkg installed."; tput sgr0
        else
            tput setaf 1; echo "ERROR: $pkg installation failed." >&2; tput sgr0
        fi
    fi
done

##################################################################################################################################
# 2. rmpc TUI client
##################################################################################################################################

echo
tput setaf 3
echo "── rmpc ──────────────────────────────────────────────────────"
tput sgr0

if pacman -Q rmpc &>/dev/null; then
    echo "rmpc already installed — skipping."
else
    echo "Installing rmpc ..."
    pkg_install rmpc || true
    if pacman -Q rmpc &>/dev/null; then
        tput setaf 2; echo "rmpc installed."; tput sgr0
    else
        tput setaf 1; echo "ERROR: rmpc installation failed." >&2; tput sgr0
    fi
fi

##################################################################################################################################
# 3. Music directory
##################################################################################################################################

echo
tput setaf 3
echo "── Music directory ───────────────────────────────────────────"
tput sgr0

MUSIC_DIR="$HOME/Music"
if [ -d "$MUSIC_DIR" ]; then
    echo "Music directory $MUSIC_DIR already exists — skipping."
else
    mkdir -p "$MUSIC_DIR"
    tput setaf 2; echo "Created $MUSIC_DIR."; tput sgr0
fi

# MPD system service uses /var/lib/mpd/music by default.
# Symlink ~/Music into it so the system daemon sees the user's library.
MPD_MUSIC_DIR="/var/lib/mpd/music"
if [ -L "$MPD_MUSIC_DIR" ] && [ "$(readlink "$MPD_MUSIC_DIR")" = "$MUSIC_DIR" ]; then
    echo "$MPD_MUSIC_DIR → $MUSIC_DIR already linked — skipping."
elif [ -d "$MPD_MUSIC_DIR" ] && [ -z "$(ls -A "$MPD_MUSIC_DIR")" ]; then
    sudo rmdir "$MPD_MUSIC_DIR"
    sudo ln -s "$MUSIC_DIR" "$MPD_MUSIC_DIR"
    tput setaf 2; echo "Linked $MPD_MUSIC_DIR → $MUSIC_DIR."; tput sgr0
elif [ ! -e "$MPD_MUSIC_DIR" ]; then
    sudo ln -s "$MUSIC_DIR" "$MPD_MUSIC_DIR"
    tput setaf 2; echo "Linked $MPD_MUSIC_DIR → $MUSIC_DIR."; tput sgr0
else
    tput setaf 3; echo "WARNING: $MPD_MUSIC_DIR already exists and is non-empty — not replacing."; tput sgr0
fi

##################################################################################################################################
# 4. Enable and start MPD (OpenRC)
##################################################################################################################################

echo
tput setaf 3
echo "── Enabling MPD service ──────────────────────────────────────"
tput sgr0

if sudo rc-update add mpd default 2>/dev/null; then
    tput setaf 2; echo "mpd enabled at default runlevel."; tput sgr0
else
    echo "mpd already enabled."
fi

echo "Starting mpd ..."
if sudo rc-service mpd start 2>/dev/null; then
    tput setaf 2; echo "mpd started."; tput sgr0
else
    echo "mpd already running (or start failed — check rc-service mpd status)."
fi

##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
echo "MPD config: /etc/mpd.conf"
echo "Music dir:  $MUSIC_DIR"
echo "Connect:    rmpc  (default: localhost:6600)"
echo
tput sgr0
