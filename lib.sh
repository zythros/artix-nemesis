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

# Pacman hook suppression works in two layers:
#   1. HookDir in pacman.conf → suppresses /etc/pacman.d/hooks/
#   2. Moving /usr/share/libalpm/hooks aside → suppresses system hooks
#      (dbus-reload, dconf-update, gvfsd, etc.) which bypass HookDir and hang
#      on Artix/OpenRC because they try to talk to D-Bus as root.
SYSTEM_HOOKS_DIR="/usr/share/libalpm/hooks"
SYSTEM_HOOKS_BAK="/usr/share/libalpm/hooks.nohook-bak"

artix_pacman_cleanup() {
    sudo rm -rf "${NOHOOK_DIR:-}" "${NOHOOK_CONF:-}"
    if sudo test -d "$SYSTEM_HOOKS_BAK" 2>/dev/null; then
        sudo rm -rf "$SYSTEM_HOOKS_DIR"
        sudo mv "$SYSTEM_HOOKS_BAK" "$SYSTEM_HOOKS_DIR"
    fi
}

artix_pacman_nohook_setup() {
    NOHOOK_DIR="$(mktemp -d)"
    # Create the conf file as root so all subsequent writes stay root→root.
    NOHOOK_CONF="$(sudo mktemp)"
    sudo sh -c "grep -v '^\s*HookDir' /etc/pacman.conf | sed '/^\[options\]/a HookDir = $NOHOOK_DIR' > '$NOHOOK_CONF'"
    # Move system hooks aside; pacman always searches /usr/share/libalpm/hooks/
    # regardless of HookDir — this stops dbus-reload.hook etc. from hanging.
    sudo mv "$SYSTEM_HOOKS_DIR" "$SYSTEM_HOOKS_BAK"
    sudo mkdir -p "$SYSTEM_HOOKS_DIR"
    export NOHOOK_DIR NOHOOK_CONF
    trap "artix_pacman_cleanup" EXIT
}
