#!/bin/bash
#set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install MPD (Music Player Daemon) + rmpc TUI client; configure
#             MPD as a system service (OpenRC) running as the desktop user so
#             it can reach the PipeWire/PulseAudio socket.
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
# Process them now so the mpd user and /var/lib/mpd exist before we configure.
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
# 3. /etc/mpd.conf — write a complete, ready-to-use config
##################################################################################################################################

echo
tput setaf 3
echo "── mpd.conf ──────────────────────────────────────────────────"
tput sgr0

sudo tee /etc/mpd.conf > /dev/null << 'EOF'
# MPD configuration — managed by 861-mpd-setup.sh
# Full reference: https://mpd.readthedocs.io/en/stable/user.html#configuration

# Set this to your music library path, then restart MPD:
#music_directory "/path/to/music"

playlist_directory  "/var/lib/mpd/playlists"
db_file             "/var/lib/mpd/tag_cache"
state_file          "/var/lib/mpd/state"
sticker_file        "/var/lib/mpd/sticker.sql"

log_file            "syslog"
log_level           "notice"

# TCP for remote clients; Unix socket for local clients (required for
# rmpc add / and other commands that use the MPD config command).
bind_to_address     "any"
bind_to_address     "/run/mpd/socket"
port                "6600"

# Automatically update the database when music files change (Linux inotify).
auto_update         "yes"

input {
    plugin "curl"
}

audio_output {
    type   "pulse"
    name   "PipeWire"
    server "unix:/run/user/1000/pulse/native"
}
EOF

tput setaf 2; echo "Wrote /etc/mpd.conf."; tput sgr0

##################################################################################################################################
# 4. OpenRC init — run MPD as zythros, not the mpd system user
##################################################################################################################################

echo
tput setaf 3
echo "── OpenRC command_user ───────────────────────────────────────"
tput sgr0

MPD_INIT="/etc/init.d/mpd"
if grep -q 'command_user="zythros' "$MPD_INIT" 2>/dev/null; then
    echo "command_user already set to zythros — skipping."
else
    sudo sed -i 's/command_user="mpd[^"]*"/command_user="zythros:audio"/' "$MPD_INIT"
    if grep -q 'command_user="zythros' "$MPD_INIT"; then
        tput setaf 2; echo "command_user set to zythros:audio in $MPD_INIT."; tput sgr0
    else
        tput setaf 1; echo "WARNING: could not patch command_user in $MPD_INIT — check manually." >&2; tput sgr0
    fi
fi

##################################################################################################################################
# 5. Permissions — /var/lib/mpd and home directory
##################################################################################################################################

echo
tput setaf 3
echo "── Permissions ───────────────────────────────────────────────"
tput sgr0

sudo mkdir -p /var/lib/mpd/playlists
sudo chown -R zythros:audio /var/lib/mpd
tput setaf 2; echo "chown zythros:audio /var/lib/mpd (recursive)."; tput sgr0

# MPD running as zythros must traverse /home/zythros to reach the music library.
# 711 allows execute (directory traverse) without exposing file listings.
sudo chmod 711 /home/zythros
tput setaf 2; echo "chmod 711 /home/zythros."; tput sgr0

##################################################################################################################################
# 6. rmpc — bootstrap default config
##################################################################################################################################

echo
tput setaf 3
echo "── rmpc config ───────────────────────────────────────────────"
tput sgr0

RMPC_CONF="$HOME/.config/rmpc/config.ron"
if [ -f "$RMPC_CONF" ]; then
    echo "rmpc config already exists — skipping."
else
    mkdir -p "$(dirname "$RMPC_CONF")"
    rmpc config > "$RMPC_CONF" 2>/dev/null && \
        { tput setaf 2; echo "Bootstrapped $RMPC_CONF."; tput sgr0; } || \
        { tput setaf 1; echo "WARNING: rmpc config bootstrap failed — run 'rmpc config > $RMPC_CONF' manually." >&2; tput sgr0; }
fi

##################################################################################################################################
# 7. Enable and start MPD (OpenRC)
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
# Use restart so OpenRC correctly handles the case where it thinks mpd is already
# running (e.g. after a command_user change) but the process is actually dead.
if sudo rc-service mpd restart 2>/dev/null; then
    tput setaf 2; echo "mpd started."; tput sgr0
else
    echo "mpd start failed — check: sudo rc-service mpd status"
fi

##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
echo "MPD config:    /etc/mpd.conf  ← uncomment and set music_directory"
echo "MPD data:      /var/lib/mpd/"
echo "Connect:       rmpc  (localhost:6600)"
echo "rmpc config:   $HOME/.config/rmpc/config.ron"
echo
tput sgr0
