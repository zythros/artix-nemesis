#!/bin/bash
#set -e
##################################################################################################################################
# Author    : zythros
# Purpose   : Roll back the kernel to any version available in the pacman cache.
#             Lists linux + linux-headers pairs, lets you pick one with fzf,
#             then installs with pacman -U and rebuilds DKMS modules.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

CACHE=/var/cache/pacman/pkg
RUNNING=$(uname -r)

echo
tput setaf 2
echo "########################################################################"
echo "################### Kernel Rollback"
echo "########################################################################"
tput sgr0
echo
echo "Running kernel : $RUNNING"
echo "Cache          : $CACHE"
echo

if ! command -v fzf &>/dev/null; then
    echo "Installing fzf..."
    sudo pacman -S --noconfirm fzf || { echo "Could not install fzf" >&2; exit 1; }
fi

##################################################################################################################################
# Discover kernel packages in cache
##################################################################################################################################

mapfile -t PKG_PATHS < <(
    find "$CACHE" -maxdepth 1 -name 'linux-[0-9]*.pkg.tar.zst' | sort -rV
)

if [ ${#PKG_PATHS[@]} -eq 0 ]; then
    echo "No kernel packages found in $CACHE" >&2
    exit 1
fi

# Normalise running version for comparison (uname: 7.0.3-artix1-2 → all dots: 7.0.3.artix1.2)
running_norm="${RUNNING//-/.}"

DISPLAY_LINES=()
declare -A LINE_TO_PATH

for path in "${PKG_PATHS[@]}"; do
    base=$(basename "$path" .pkg.tar.zst)   # linux-7.0.3.artix1-2-x86_64
    ver="${base#linux-}"                     # 7.0.3.artix1-2-x86_64
    ver="${ver%-x86_64}"                     # 7.0.3.artix1-2

    headers="$CACHE/linux-headers-${ver}-x86_64.pkg.tar.zst"
    has_headers="no "
    [ -f "$headers" ] && has_headers="yes"

    ver_norm="${ver//-/.}"
    running_tag=""
    [ "$ver_norm" = "$running_norm" ] && running_tag="  ← running"

    line="$(printf "%-30s  headers: %s%s" "$ver" "$has_headers" "$running_tag")"
    DISPLAY_LINES+=("$line")
    LINE_TO_PATH["$line"]="$path"
done

##################################################################################################################################
# fzf selection
##################################################################################################################################

SELECTED=$(printf '%s\n' "${DISPLAY_LINES[@]}" | fzf \
    --prompt="kernel-rollback > " \
    --header="ENTER to select  |  ESC to cancel" \
    --header-first \
    --reverse \
    --no-sort) || exit 0

[ -z "$SELECTED" ] && { echo "Nothing selected."; exit 0; }

TARGET_PATH="${LINE_TO_PATH[$SELECTED]}"
TARGET_BASE=$(basename "$TARGET_PATH" .pkg.tar.zst)
TARGET_VER="${TARGET_BASE#linux-}"
TARGET_VER="${TARGET_VER%-x86_64}"

##################################################################################################################################
# Build install list
##################################################################################################################################

echo
echo "Selected: $TARGET_VER"

PKGS=("$TARGET_PATH")
HEADERS_PATH="$CACHE/linux-headers-${TARGET_VER}-x86_64.pkg.tar.zst"
if [ -f "$HEADERS_PATH" ]; then
    PKGS+=("$HEADERS_PATH")
fi

echo
echo "Packages to install:"
for p in "${PKGS[@]}"; do
    echo "  $(basename "$p")"
done
echo

read -r -p "Proceed? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

##################################################################################################################################
# Install
##################################################################################################################################

echo
sudo pacman -U "${PKGS[@]}"

##################################################################################################################################
# Rebuild DKMS modules for the target kernel
# Package version uses dots (7.0.3.artix1-2); modules dir uses a hyphen (7.0.3-artix1-2).
##################################################################################################################################

# Convert pkg ver → kernel ver: 7.0.3.artix1-2 → 7.0.3-artix1-2
KVER=$(echo "$TARGET_VER" | sed 's/\.\(artix[^.]*-[0-9]*\)$/-\1/')

if command -v dkms &>/dev/null; then
    echo
    tput setaf 3
    echo "Rebuilding DKMS modules for $KVER ..."
    tput sgr0
    sudo dkms autoinstall -k "$KVER" || {
        tput setaf 1
        echo "WARNING: dkms autoinstall reported errors — check 'dkms status' after reboot"
        tput sgr0
    }
fi

##################################################################################################################################

echo
tput setaf 2
echo "Done. Reboot to boot into $KVER."
tput sgr0
echo
