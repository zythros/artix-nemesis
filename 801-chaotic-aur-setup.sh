#!/bin/bash
#set -e
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Add the Chaotic AUR pre-built repository to pacman and install yay.
#             Chaotic AUR provides pre-built AUR packages (e.g. bridge-utils, many others).
#             https://aur.chaotic.cx
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
echo "################### Setting up Chaotic AUR"
echo "########################################################################"
tput sgr0
echo

##################################################################################################################################
# 1. Import and locally sign the Chaotic AUR master key
##################################################################################################################################

CHAOTIC_KEY="3056513887B78AEB"

echo "Importing Chaotic AUR signing key ($CHAOTIC_KEY) ..."
sudo pacman-key --recv-key "$CHAOTIC_KEY" --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key "$CHAOTIC_KEY"

tput setaf 2
echo "Key imported and signed."
tput sgr0

##################################################################################################################################
# 2. Install the keyring and mirrorlist packages
##################################################################################################################################

artix_pacman_nohook_setup

echo
echo "Installing chaotic-keyring and chaotic-mirrorlist ..."

sudo pacman --config "$NOHOOK_CONF" -U --noconfirm \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

tput setaf 2
echo "keyring + mirrorlist installed."
tput sgr0

##################################################################################################################################
# 3. Add [chaotic-aur] to /etc/pacman.conf (idempotent)
##################################################################################################################################

echo
PACMAN_CONF="/etc/pacman.conf"

if grep -q "^\[chaotic-aur\]" "$PACMAN_CONF"; then
    echo "[chaotic-aur] already present in $PACMAN_CONF — skipping."
else
    echo "Adding [chaotic-aur] to $PACMAN_CONF ..."
    sudo tee -a "$PACMAN_CONF" > /dev/null <<'EOF'

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
    tput setaf 2
    echo "[chaotic-aur] added to $PACMAN_CONF"
    tput sgr0
fi

# Refresh NOHOOK_CONF so it includes [chaotic-aur] — it was snapshotted before
# the section was added above, so pacman wouldn't find yay without this.
sudo sh -c "grep -v '^\s*HookDir' /etc/pacman.conf | sed '/^\[options\]/a HookDir = $NOHOOK_DIR' > '$NOHOOK_CONF'"

##################################################################################################################################
# 4. Sync package databases
##################################################################################################################################

echo
echo "Syncing package databases ..."
sudo pacman --config "$NOHOOK_CONF" -Sy

tput setaf 2
echo "Sync complete."
tput sgr0

##################################################################################################################################
# 5. Install yay (AUR helper, available from Chaotic AUR)
##################################################################################################################################

echo
if pacman -Q yay &>/dev/null; then
    echo "yay already installed — skipping."
else
    echo "Installing yay ..."
    sudo pacman --config "$NOHOOK_CONF" -S --noconfirm yay || true
    if pacman -Q yay &>/dev/null; then
        tput setaf 2
        echo "yay installed."
        tput sgr0
    else
        tput setaf 1
        echo "ERROR: yay installation failed." >&2
        tput sgr0
        exit 1
    fi
fi

##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
echo "Chaotic AUR is now available and yay is installed."
echo "Install AUR packages directly with pacman or yay, e.g.:"
echo "  sudo pacman -S bridge-utils"
echo "  yay -S some-aur-package"
echo
tput sgr0
