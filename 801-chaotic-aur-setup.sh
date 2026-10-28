#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Menu      : Add Chaotic AUR pre-built repo to pacman + install yay (optional — nothing else here requires it)
# Group     : optional
# Purpose   : Add the Chaotic AUR pre-built repository to pacman and install yay.
#             Chaotic AUR provides pre-built AUR packages (e.g. bridge-utils, many others).
#             https://aur.chaotic.cx
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

script_start "Setting up Chaotic AUR"

##################################################################################################################################
# 1. Import and locally sign the Chaotic AUR master key
##################################################################################################################################

CHAOTIC_KEY="3056513887B78AEB"

echo "Importing Chaotic AUR signing key ($CHAOTIC_KEY) ..."
sudo pacman-key --recv-key "$CHAOTIC_KEY" --keyserver keyserver.ubuntu.com \
    || die "could not fetch Chaotic AUR key $CHAOTIC_KEY from keyserver.ubuntu.com"
sudo pacman-key --lsign-key "$CHAOTIC_KEY" || die "could not locally sign key $CHAOTIC_KEY"
ok "Key imported and signed."

##################################################################################################################################
# 2. Install the keyring and mirrorlist packages
##################################################################################################################################

artix_pacman_nohook_setup

echo
echo "Installing chaotic-keyring and chaotic-mirrorlist ..."

sudo pacman --config "$NOHOOK_CONF" -U --noconfirm \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' \
    || die "chaotic-keyring / chaotic-mirrorlist install failed"
ok "keyring + mirrorlist installed."

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
    ok "[chaotic-aur] added to $PACMAN_CONF"
fi

# Also set up Arch [extra] here so that scripts running after 801 (803, 802, 820, etc.)
# can install packages like freecad, libx11, libxft without depending on 880 having run.
ensure_arch_extra

# NOHOOK_CONF was snapshotted before [chaotic-aur] and [extra] were added above
nohook_regen

##################################################################################################################################
# 4. Sync package databases
##################################################################################################################################

echo
pkg_sync || die "could not sync package databases (check the new repos above)"
ok "Sync complete."

##################################################################################################################################
# 5. Install yay (AUR helper, available from Chaotic AUR)
##################################################################################################################################

echo
ensure_pkgs yay

##################################################################################################################################

script_done
echo "Chaotic AUR and Arch [extra] are now available; yay is installed."
echo "Install AUR packages directly with pacman or yay, e.g.:"
echo "  sudo pacman -S bridge-utils"
echo "  yay -S some-aur-package"
echo
