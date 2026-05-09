#!/bin/bash
# Shared helpers for artix-nemesis setup scripts.
# Source this at the top of any script that calls pacman:
#   source "$(dirname "$(readlink -f "$0")")/lib.sh"

##################################################################################################################################
# artix_pacman_nohook_setup
#
# Creates a temporary pacman.conf with an empty HookDir and registers a
# cleanup trap.  Call once near the top of any script that runs pacman,
# then use:  sudo pacman --config "$NOHOOK_CONF" ...
#
# Why: post-install hooks hang on Artix/OpenRC because they try to talk to
# D-Bus as root — no session is available.  Skipping hooks avoids the hang.
# Run update-desktop-database / gtk-update-icon-cache manually if needed.
##################################################################################################################################

artix_pacman_nohook_setup() {
    NOHOOK_DIR="$(mktemp -d)"
    NOHOOK_CONF="$(mktemp)"
    sudo grep -v '^\s*HookDir' /etc/pacman.conf | sudo tee "$NOHOOK_CONF" > /dev/null
    echo "HookDir = $NOHOOK_DIR" | sudo tee -a "$NOHOOK_CONF" > /dev/null
    export NOHOOK_DIR NOHOOK_CONF
    trap "sudo rm -rf '$NOHOOK_DIR' '$NOHOOK_CONF'" EXIT
}
