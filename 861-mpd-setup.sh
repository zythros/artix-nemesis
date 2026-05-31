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

# nohook install skips sysusers.d (user creation) and tmpfiles.d (dir creation).
# Process them now so the mpd user and /var/lib/mpd exist before we symlink.
if ! id mpd &>/dev/null; then
    sudo systemd-sysusers /usr/lib/sysusers.d/mpd.conf
fi
sudo systemd-tmpfiles --create /usr/lib/tmpfiles.d/mpd.conf

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
# 3. mpd.conf — add commented music_directory example if not already present
##################################################################################################################################

echo
tput setaf 3
echo "── mpd.conf ──────────────────────────────────────────────────"
tput sgr0

MPD_CONF="/etc/mpd.conf"
if grep -q "music_directory" "$MPD_CONF" 2>/dev/null; then
    echo "music_directory already present in $MPD_CONF — skipping."
else
    sudo sh -c "echo '' >> '$MPD_CONF' && echo '# Set this to your music library path, e.g.:' >> '$MPD_CONF' && echo '#music_directory \"/home/user/Music\"' >> '$MPD_CONF'"
    tput setaf 2; echo "Added music_directory example to $MPD_CONF."; tput sgr0
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
echo "MPD config: /etc/mpd.conf  ← set music_directory here"
echo "Connect:    rmpc  (default: localhost:6600)"
echo
tput sgr0
