#!/bin/bash
#set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Check whether Chaotic AUR (and/or an AUR helper) is enabled on this
#             system, and remove it if so. Reverses what 801-chaotic-aur-setup.sh
#             does — safe to run even if 801 was never run (everything is
#             detect-then-act, nothing errors on a clean system).
#
#             Removes, if present:
#               - [chaotic-aur] section from /etc/pacman.conf
#               - chaotic-keyring / chaotic-mirrorlist packages
#               - the locally-signed Chaotic AUR GPG key
#               - yay / paru (AUR helpers)
#
#             Does NOT touch the Arch [extra] repo — that's an official Arch Linux
#             repo (needed by 880/881 for nvidia-utils), not AUR/Chaotic AUR.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

CHAOTIC_KEY="3056513887B78AEB"
PACMAN_CONF="/etc/pacman.conf"

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
echo "################### Chaotic AUR / AUR removal"
echo "########################################################################"
tput sgr0
echo

##################################################################################################################################
# Detect current state before touching anything
##################################################################################################################################

HAS_CHAOTIC_REPO=0
grep -q '^\[chaotic-aur\]' "$PACMAN_CONF" 2>/dev/null && HAS_CHAOTIC_REPO=1

HAS_CHAOTIC_KEYRING=0
pacman -Q chaotic-keyring &>/dev/null && HAS_CHAOTIC_KEYRING=1

HAS_CHAOTIC_MIRRORLIST=0
pacman -Q chaotic-mirrorlist &>/dev/null && HAS_CHAOTIC_MIRRORLIST=1

HAS_CHAOTIC_KEY=0
sudo pacman-key --list-keys "$CHAOTIC_KEY" &>/dev/null && HAS_CHAOTIC_KEY=1

HAS_YAY=0
command -v yay &>/dev/null && HAS_YAY=1

HAS_PARU=0
command -v paru &>/dev/null && HAS_PARU=1

echo "Detected:"
echo "  [chaotic-aur] in pacman.conf : $([ $HAS_CHAOTIC_REPO -eq 1 ] && echo yes || echo no)"
echo "  chaotic-keyring package      : $([ $HAS_CHAOTIC_KEYRING -eq 1 ] && echo yes || echo no)"
echo "  chaotic-mirrorlist package   : $([ $HAS_CHAOTIC_MIRRORLIST -eq 1 ] && echo yes || echo no)"
echo "  Chaotic AUR GPG key trusted  : $([ $HAS_CHAOTIC_KEY -eq 1 ] && echo yes || echo no)"
echo "  yay installed                : $([ $HAS_YAY -eq 1 ] && echo yes || echo no)"
echo "  paru installed                : $([ $HAS_PARU -eq 1 ] && echo yes || echo no)"
echo

if [ $HAS_CHAOTIC_REPO -eq 0 ] && [ $HAS_CHAOTIC_KEYRING -eq 0 ] && [ $HAS_CHAOTIC_MIRRORLIST -eq 0 ] \
    && [ $HAS_CHAOTIC_KEY -eq 0 ] && [ $HAS_YAY -eq 0 ] && [ $HAS_PARU -eq 0 ]; then
    tput setaf 2
    echo "Nothing to do — Chaotic AUR is not configured and no AUR helper is installed."
    tput sgr0
    echo
    exit 0
fi

read -r -p "Remove the above? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

##################################################################################################################################
# Authenticate sudo once; keepalive prevents expiry during removal
##################################################################################################################################

sudo -v
while true; do timeout 30 sudo -v; sleep 50; done &
SUDO_KEEPALIVE=$!

artix_pacman_nohook_setup
trap "artix_pacman_cleanup; kill $SUDO_KEEPALIVE 2>/dev/null" EXIT

WARNINGS=()

##################################################################################################################################
# 1. Remove yay / paru
##################################################################################################################################

if [ $HAS_YAY -eq 1 ]; then
    echo
    tput setaf 3
    echo "── Removing yay ──────────────────────────────────────────────"
    tput sgr0
    if sudo pacman --config "$NOHOOK_CONF" -Rns --noconfirm yay; then
        tput setaf 2; echo "yay removed."; tput sgr0
    else
        tput setaf 1; echo "WARNING: failed to remove yay." >&2; tput sgr0
        WARNINGS+=("yay: removal failed — check manually (sudo pacman -Rns yay)")
    fi
fi

if [ $HAS_PARU -eq 1 ]; then
    echo
    tput setaf 3
    echo "── Removing paru ─────────────────────────────────────────────"
    tput sgr0
    if sudo pacman --config "$NOHOOK_CONF" -Rns --noconfirm paru; then
        tput setaf 2; echo "paru removed."; tput sgr0
    else
        tput setaf 1; echo "WARNING: failed to remove paru." >&2; tput sgr0
        WARNINGS+=("paru: removal failed — check manually (sudo pacman -Rns paru)")
    fi
fi

##################################################################################################################################
# 2. Remove chaotic-keyring / chaotic-mirrorlist packages
##################################################################################################################################

CHAOTIC_PKGS=()
[ $HAS_CHAOTIC_KEYRING -eq 1 ]    && CHAOTIC_PKGS+=(chaotic-keyring)
[ $HAS_CHAOTIC_MIRRORLIST -eq 1 ] && CHAOTIC_PKGS+=(chaotic-mirrorlist)

if [ ${#CHAOTIC_PKGS[@]} -gt 0 ]; then
    echo
    tput setaf 3
    echo "── Removing ${CHAOTIC_PKGS[*]} ──────────────────────────────"
    tput sgr0
    if sudo pacman --config "$NOHOOK_CONF" -Rns --noconfirm "${CHAOTIC_PKGS[@]}"; then
        tput setaf 2; echo "${CHAOTIC_PKGS[*]} removed."; tput sgr0
    else
        tput setaf 1; echo "WARNING: failed to remove ${CHAOTIC_PKGS[*]}." >&2; tput sgr0
        WARNINGS+=("${CHAOTIC_PKGS[*]}: removal failed — check manually")
    fi
fi

##################################################################################################################################
# 3. Remove [chaotic-aur] section from /etc/pacman.conf
##################################################################################################################################

if [ $HAS_CHAOTIC_REPO -eq 1 ]; then
    echo
    tput setaf 3
    echo "── Removing [chaotic-aur] from $PACMAN_CONF ──────────────────"
    tput sgr0

    TMP_CONF="$(sudo mktemp)"
    sudo chmod 644 "$TMP_CONF"
    # Strip the [chaotic-aur] section (from its header up to, but not including,
    # the next [section] or EOF), regardless of exactly what's inside it.
    sudo awk '
        /^\[chaotic-aur\]/ { skip=1; next }
        skip && /^\[/       { skip=0 }
        !skip
    ' "$PACMAN_CONF" | sudo tee "$TMP_CONF" > /dev/null
    # Collapse any now-doubled-up blank lines left behind
    sudo sed -i '/^$/N;/^\n$/D' "$TMP_CONF"
    sudo cp "$TMP_CONF" "$PACMAN_CONF"
    sudo rm -f "$TMP_CONF"

    if grep -q '^\[chaotic-aur\]' "$PACMAN_CONF"; then
        tput setaf 1
        echo "WARNING: [chaotic-aur] still present in $PACMAN_CONF — remove manually." >&2
        tput sgr0
        WARNINGS+=("[chaotic-aur]: still present in $PACMAN_CONF after edit attempt")
    else
        tput setaf 2
        echo "[chaotic-aur] removed from $PACMAN_CONF."
        tput sgr0
    fi
fi

##################################################################################################################################
# 4. Delete the Chaotic AUR GPG key
##################################################################################################################################

if [ $HAS_CHAOTIC_KEY -eq 1 ]; then
    echo
    tput setaf 3
    echo "── Deleting Chaotic AUR GPG key ($CHAOTIC_KEY) ────────────────"
    tput sgr0
    if sudo pacman-key --delete "$CHAOTIC_KEY"; then
        tput setaf 2; echo "Key deleted."; tput sgr0
    else
        tput setaf 1; echo "WARNING: failed to delete key $CHAOTIC_KEY." >&2; tput sgr0
        WARNINGS+=("GPG key $CHAOTIC_KEY: delete failed — check manually (sudo pacman-key --delete $CHAOTIC_KEY)")
    fi
fi

##################################################################################################################################
# 5. Refresh pacman databases now that pacman.conf changed
##################################################################################################################################

echo
tput setaf 3
echo "── Syncing package databases ─────────────────────────────────"
tput sgr0
sudo pacman --config "$NOHOOK_CONF" -Sy || {
    tput setaf 3
    echo "WARNING: pacman -Sy reported errors — check pacman.conf by hand." >&2
    tput sgr0
    WARNINGS+=("pacman -Sy: reported errors after removal — review $PACMAN_CONF")
}

##################################################################################################################################
# Summary
##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
tput setaf 2
echo "Chaotic AUR / AUR helper removal complete."
tput sgr0
echo
echo "Arch [extra] repo was left untouched (official Arch repo, unrelated to AUR)."
echo "Nothing else in this repo requires Chaotic AUR or an AUR helper — see"
echo "801-chaotic-aur-setup.sh if you ever want to re-enable it."
echo

if [ ${#WARNINGS[@]} -gt 0 ]; then
    tput setaf 3
    echo "########################################################################"
    echo "############################ WARNINGS ##################################"
    echo "########################################################################"
    echo
    for warning in "${WARNINGS[@]}"; do
        echo "  ! $warning"
    done
    echo
    tput sgr0
fi
