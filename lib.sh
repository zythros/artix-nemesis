#!/bin/bash
# Shared helpers for artix-nemesis setup scripts.
# Source this at the top of any script that calls pacman:
#   source "$(dirname "$(readlink -f "$0")")/lib.sh"

##################################################################################################################################
# artix_pacman_nohook_setup
#
# Creates a temporary pacman.conf whose HookDir masks only the D-Bus hooks
# that hang, and registers a cleanup trap.  Call once near the top of any
# script that runs pacman, then use:  sudo pacman --config "$NOHOOK_CONF" ...
#
# Why: a few post-install hooks hang on Artix/OpenRC because they try to talk
# to D-Bus as root — no session is available.
##################################################################################################################################

# pacman always runs /usr/share/libalpm/hooks/, then HookDir; a HookDir entry
# that is a symlink to /dev/null masks the system hook of the same name
# (alpm-hooks(5)).  Only these are masked — everything else (glib schemas,
# icon/desktop caches, sysusers/tmpfiles, depmod, mkinitcpio, ...) still runs.
# Masking the whole hooks dir used to leave e.g. virt-manager unlaunchable
# (gsettings schema never compiled).
NOHOOK_MASKED_HOOKS=(
    dbus-reload.hook
    dconf-update.hook
    gvfsd.hook
    accounts-daemon-restart.hook
)

# Left over from the old whole-dir approach if a script was killed mid-run.
SYSTEM_HOOKS_DIR="/usr/share/libalpm/hooks"
SYSTEM_HOOKS_BAK="/usr/share/libalpm/hooks.nohook-bak"

artix_pacman_cleanup() {
    sudo rm -rf "${NOHOOK_DIR:-}" "${NOHOOK_CONF:-}"
}

artix_pacman_nohook_setup() {
    if sudo test -d "$SYSTEM_HOOKS_BAK" 2>/dev/null; then
        sudo rm -rf "$SYSTEM_HOOKS_DIR"
        sudo mv "$SYSTEM_HOOKS_BAK" "$SYSTEM_HOOKS_DIR"
    fi
    NOHOOK_DIR="$(mktemp -d)"
    local hook
    for hook in "${NOHOOK_MASKED_HOOKS[@]}"; do
        ln -s /dev/null "$NOHOOK_DIR/$hook"
    done
    # Create the conf file as root so all subsequent writes stay root→root.
    NOHOOK_CONF="$(sudo mktemp)"
    sudo chmod 644 "$NOHOOK_CONF"
    sudo sh -c "grep -v '^\s*HookDir' /etc/pacman.conf | sed '/^\[options\]/a HookDir = $NOHOOK_DIR' > '$NOHOOK_CONF'"
    export NOHOOK_DIR NOHOOK_CONF
    trap "artix_pacman_cleanup" EXIT
}

##################################################################################################################################
# pkg_install <pkg>
#
# Install a package via pacman (nohook conf) with a 120s timeout to guard
# against libalpm's built-in ldconfig runner hanging post-install on Artix.
# Official repos only — no AUR/yay fallback, by design (see 801/803 for the
# opt-in Chaotic AUR path). Cleans db.lck before each attempt. Returns
# non-zero if the package isn't available in a configured repo; callers
# should treat that as "not available without AUR" rather than a hard error.
# After calling, run `sudo ldconfig` manually if the package adds libraries.
##################################################################################################################################

pkg_install() {
    local pkg="$1"
    sudo rm -f /var/lib/pacman/db.lck
    if sudo timeout 120 pacman --config "$NOHOOK_CONF" -S --noconfirm --needed "$pkg"; then
        return 0
    fi
    local exit_code=$?
    # timeout exits 124 when the command times out — kill the stray pacman child
    if [ "$exit_code" -eq 124 ]; then
        sudo pkill -TERM -P "$(pgrep -x pacman | tail -1)" 2>/dev/null || true
        sudo rm -f /var/lib/pacman/db.lck
    fi
    return 1
}
