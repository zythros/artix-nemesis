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
    # Run all three steps in one sudo bash invocation.
    # Reason: sudo sed -i replaces the file with a new root-owned inode; a
    # subsequent separate "sudo tee -a" then fails with Permission denied on
    # some Artix setups.  Keeping everything in one subshell avoids the issue.
    sudo bash -c "cp /etc/pacman.conf '$NOHOOK_CONF' && sed -i '/^\s*HookDir/d' '$NOHOOK_CONF' && printf 'HookDir = %s\n' '$NOHOOK_DIR' >> '$NOHOOK_CONF'"
    export NOHOOK_DIR NOHOOK_CONF
    trap "sudo rm -rf '$NOHOOK_DIR' '$NOHOOK_CONF'" EXIT
}
