#!/bin/bash
# Shared helpers for artix-nemesis setup scripts.
# Source this at the top of every script:
#   source "$(dirname "$(readlink -f "$0")")/lib.sh"
#
# Typical script shape:
#   script_start "Setting up foo"      # DEBUG pause, banner, sudo keepalive
#   section "Packages"
#   ensure_pkgs foo foo-openrc         # installs what's missing, err() on failure
#   enable_service food
#   ... || err "what went wrong"       # recorded; script carries on
#   ... || die "can't continue"        # recorded; script exits 1
#   script_done                        # "done" banner; print a summary after it
#
# Exit status is honest: on exit, any err()/die() makes the script exit
# non-zero (menu-fzf.sh relies on this), and all warnings/errors are listed
# once at the very end so they don't scroll away.

##################################################################################################################################
# Output
##################################################################################################################################

LIB_ERRORS=()
LIB_WARNINGS=()

# tput is best-effort: with no TERM (ssh, cron) it fails, and that must never
# change a script's exit status.
_c() { tput "$@" 2>/dev/null || true; }

ok()   { _c setaf 2; echo "$*"; _c sgr0; }
info() { _c setaf 6; echo "$*"; _c sgr0; }
warn() { _c setaf 3; echo "WARNING: $*" >&2; _c sgr0; LIB_WARNINGS+=("$*"); }
err()  { _c setaf 1; echo "ERROR: $*" >&2; _c sgr0; LIB_ERRORS+=("$*"); }
die()  { err "$@"; exit 1; }

# Yellow sub-heading
section() {
    echo
    _c setaf 3
    echo "── $* ──────────────────────────────────────────────────────"
    _c sgr0
}

# DEBUG pause, start banner, and sudo authentication (+ keepalive)
script_start() {
    if [ "$DEBUG" = true ]; then
        echo
        echo "------------------------------------------------------------"
        echo "Running $(basename "$0")"
        echo "------------------------------------------------------------"
        echo
        read -n 1 -s -r -p "Debug mode is on. Press any key to continue..."
        echo
    fi
    echo
    _c setaf 2
    echo "########################################################################"
    echo "################### $*"
    echo "########################################################################"
    _c sgr0
    echo
    sudo_keepalive
}

# "done" banner; scripts print their own summary lines after it
script_done() {
    echo
    _c setaf 6
    echo "##############################################################"
    echo "###################  $(basename "$0") done"
    echo "##############################################################"
    _c sgr0
    echo
}

# Nothing to do on this machine (wrong filesystem, not a VM, ...): exit 0
script_skip() {
    _c setaf 3; echo "$*"; echo "Skipping $(basename "$0")."; _c sgr0
    echo
    exit 0
}

##################################################################################################################################
# Exit handling — cleanup, final warning/error report, honest exit status
##################################################################################################################################

_lib_on_exit() {
    local rc=$?
    [ -n "${LIB_SUDO_KEEPALIVE:-}" ] && kill "$LIB_SUDO_KEEPALIVE" 2>/dev/null
    artix_pacman_cleanup
    local m
    if [ ${#LIB_WARNINGS[@]} -gt 0 ]; then
        echo
        _c setaf 3
        echo "Warnings (${#LIB_WARNINGS[@]}):"
        for m in "${LIB_WARNINGS[@]}"; do echo "  ! $m"; done
        _c sgr0
    fi
    if [ ${#LIB_ERRORS[@]} -gt 0 ]; then
        echo
        _c setaf 1
        echo "Errors (${#LIB_ERRORS[@]}) — $(basename "$0") did not fully succeed:"
        for m in "${LIB_ERRORS[@]}"; do echo "  ✗ $m"; done
        _c sgr0
        echo
        [ "$rc" -eq 0 ] && rc=1
    fi
    exit "$rc"
}
trap _lib_on_exit EXIT

sudo_keepalive() {
    [ -n "${LIB_SUDO_KEEPALIVE:-}" ] && return 0
    sudo -v || die "sudo authentication failed"
    # -n: never prompt from the background loop; the cached ticket is refreshed.
    # Detached from the terminal so a leftover `sleep` can't hold ssh/pipes open.
    while true; do sudo -n -v; sleep 50; done </dev/null &>/dev/null &
    LIB_SUDO_KEEPALIVE=$!
}

##################################################################################################################################
# artix_pacman_nohook_setup
#
# Creates a temporary pacman.conf whose HookDir masks only the D-Bus hooks
# that hang.  Called automatically by the package helpers below; scripts that
# run pacman themselves call it once, then use:
#   sudo pacman --config "$NOHOOK_CONF" ...
# Cleanup happens in the EXIT trap above.
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
    [ -n "${NOHOOK_DIR:-}${NOHOOK_CONF:-}" ] || return 0
    sudo rm -rf "${NOHOOK_DIR:-}" "${NOHOOK_CONF:-}"
}

artix_pacman_nohook_setup() {
    [ -n "${NOHOOK_CONF:-}" ] && return 0
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
    export NOHOOK_DIR NOHOOK_CONF
    nohook_regen
}

# (Re)generate NOHOOK_CONF from the current /etc/pacman.conf — call again
# after adding a repo to pacman.conf, or pacman won't see the new repo.
nohook_regen() {
    [ -n "${NOHOOK_CONF:-}" ] || { artix_pacman_nohook_setup; return; }
    sudo sh -c "grep -v '^\s*HookDir' /etc/pacman.conf | sed '/^\[options\]/a HookDir = $NOHOOK_DIR' > '$NOHOOK_CONF'"
}

##################################################################################################################################
# Package helpers
##################################################################################################################################

# pkg_sync — refresh package databases
pkg_sync() {
    artix_pacman_nohook_setup
    echo "Syncing package databases ..."
    sudo pacman --config "$NOHOOK_CONF" -Sy || { err "pacman -Sy failed"; return 1; }
}

# pkg_install <pkg>
#
# Install one package via pacman (nohook conf) with a 120s timeout to guard
# against libalpm's built-in ldconfig runner hanging post-install on Artix.
# Official repos only — no AUR/yay fallback, by design (see 801/803 for the
# opt-in Chaotic AUR path). Cleans db.lck before each attempt. Returns
# non-zero if the package isn't available in a configured repo; callers
# should treat that as "not available without AUR" rather than a hard error.
# After calling, run `sudo ldconfig` manually if the package adds libraries.
pkg_install() {
    local pkg="$1" exit_code=0
    artix_pacman_nohook_setup
    sudo rm -f /var/lib/pacman/db.lck
    sudo timeout 120 pacman --config "$NOHOOK_CONF" -S --noconfirm --needed "$pkg" || exit_code=$?
    [ "$exit_code" -eq 0 ] && return 0
    # timeout exits 124 when the command times out — kill the stray pacman child
    if [ "$exit_code" -eq 124 ]; then
        sudo pkill -TERM -P "$(pgrep -x pacman | tail -1)" 2>/dev/null || true
        sudo rm -f /var/lib/pacman/db.lck
    fi
    return 1
}

# ensure_pkgs [--optional] <pkg>...
#
# Installs whichever of <pkg>... aren't installed yet: one pacman transaction
# first, then (if that fails, e.g. one package isn't in any repo) one at a
# time so everything that *is* available still gets installed.  Each package
# still missing afterwards is an err() — or a warn() with --optional.
# Returns non-zero if anything is missing.
ensure_pkgs() {
    local report=err
    if [ "$1" = --optional ]; then report=warn; shift; fi
    local pkg missing=() rc=0
    for pkg in "$@"; do
        if pacman -Q "$pkg" &>/dev/null; then
            echo "$pkg already installed — skipping."
        else
            missing+=("$pkg")
        fi
    done
    [ ${#missing[@]} -eq 0 ] && return 0

    artix_pacman_nohook_setup
    echo "Installing ${missing[*]} ..."
    sudo rm -f /var/lib/pacman/db.lck
    if ! sudo pacman --config "$NOHOOK_CONF" -S --noconfirm --needed "${missing[@]}"; then
        if [ ${#missing[@]} -gt 1 ]; then
            echo "Retrying one package at a time ..."
            for pkg in "${missing[@]}"; do
                pacman -Q "$pkg" &>/dev/null || pkg_install "$pkg" || true
            done
        fi
    fi
    for pkg in "${missing[@]}"; do
        if pacman -Q "$pkg" &>/dev/null; then
            ok "$pkg installed."
        else
            "$report" "$pkg could not be installed"
            rc=1
        fi
    done
    return $rc
}

##################################################################################################################################
# Services (OpenRC)
##################################################################################################################################

# enable_service <svc> [runlevel] — add to runlevel (default: default) and start
enable_service() {
    local svc="$1" lvl="${2:-default}"
    if rc-update show "$lvl" 2>/dev/null | awk '{print $1}' | grep -qx "$svc"; then
        echo "$svc already enabled at $lvl runlevel."
    elif sudo rc-update add "$svc" "$lvl"; then
        ok "$svc enabled at $lvl runlevel."
    else
        err "could not enable $svc (rc-update add $svc $lvl)"
        return 1
    fi
    if sudo rc-service "$svc" status &>/dev/null; then
        echo "$svc already running."
    elif sudo rc-service "$svc" start; then
        ok "$svc started."
    else
        err "$svc failed to start — check: sudo rc-service $svc status"
        return 1
    fi
}

##################################################################################################################################
# Source checkouts
##################################################################################################################################

# git_sync <url> <dir> — clone, or pull if already a checkout.  A non-git
# <dir> that already has content is moved aside to <dir>.backup.<epoch>.
git_sync() {
    local url="$1" dir="$2"
    if [ -d "$dir/.git" ]; then
        echo "Updating $dir ..."
        git -C "$dir" pull || { err "git pull failed in $dir — check: git -C $dir status"; return 1; }
    else
        if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
            echo "Backing up existing $dir ..."
            mv "$dir" "${dir}.backup.$(date +%s)"
        fi
        echo "Cloning $url to $dir ..."
        mkdir -p "$(dirname "$dir")"
        git clone "$url" "$dir" || { err "git clone $url failed — check internet connection"; return 1; }
    fi
}

# make_install <dir> — clean, build, and sudo make install
make_install() {
    local dir="$1"
    echo "Building $(basename "$dir") ..."
    make -C "$dir" clean >/dev/null || { err "make clean failed in $dir"; return 1; }
    make -C "$dir"                 || { err "build failed in $dir"; return 1; }
    echo "Installing $(basename "$dir") ..."
    sudo make -C "$dir" install    || { err "make install failed in $dir"; return 1; }
    ok "$(basename "$dir") installed."
}
