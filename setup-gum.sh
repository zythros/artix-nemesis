#!/bin/bash
##################################################################################################################################
# Author    : zythros
# Purpose   : gum-based menu to select and run artix-nemesis setup scripts
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v gum &>/dev/null; then
    echo "Installing gum..."
    sudo pacman -S --noconfirm gum || { echo "Could not install gum — aborting" >&2; exit 1; }
fi

# Pairs: script filename, description (in desired run order)
ENTRIES=(
    "801-chaotic-aur-setup.sh"  "Add Chaotic AUR pre-built repo to pacman"
    "802-dwm-setup.sh"          "Build and install dwm window manager"
    "810-wallpaper-setup.sh"    "Set up wallpaper cycling system"
    "820-dmenu-setup.sh"        "Build dmenu; wire j4-dmenu-desktop into dwm"
    "840-snapper-setup.sh"      "Configure Snapper for BTRFS snapshots"
    "870-vm-clipboard-setup.sh" "SPICE clipboard sharing (VM guests only)"
    "880-nvidia-bm-setup.sh"    "NVIDIA drivers — bare metal (dual GPU)"
    "881-nvidia-vm-setup.sh"    "NVIDIA drivers — VM guest (3090 passthrough)"
    "890-vfio-passthrough.sh"   "Configure VFIO passthrough for RTX 3090"
    "895-virt-manager-setup.sh" "Install virt-manager / QEMU-KVM"
)

##################################################################################################################################
# Build menu items and prompt with gum
##################################################################################################################################

MENU_LINES=()
for (( i=0; i<${#ENTRIES[@]}; i+=2 )); do
    MENU_LINES+=("${ENTRIES[i]}  —  ${ENTRIES[i+1]}")
done

mapfile -t SELECTED < <(gum choose \
    --no-limit \
    --header "artix-nemesis setup  |  SPACE to select  |  ENTER to confirm" \
    "${MENU_LINES[@]}") || exit 0

[ ${#SELECTED[@]} -eq 0 ] && { echo "Nothing selected."; exit 0; }

# Extract script filenames from selected lines (everything before the first double-space)
QUEUE=()
for line in "${SELECTED[@]}"; do
    QUEUE+=("${line%%  *}")
done

# Re-order queue to match original script order (gum preserves selection order, not list order)
ORDERED=()
for (( i=0; i<${#ENTRIES[@]}; i+=2 )); do
    script="${ENTRIES[i]}"
    for q in "${QUEUE[@]}"; do
        [ "$q" = "$script" ] && ORDERED+=("$script") && break
    done
done

##################################################################################################################################
# Confirm
##################################################################################################################################

echo
echo "The following scripts will run in order:"
for s in "${ORDERED[@]}"; do
    echo "  $s"
done
echo
gum confirm "Proceed?" || { echo "Aborted."; exit 0; }

##################################################################################################################################
# Run selected scripts in order
##################################################################################################################################

PASS=()
FAIL=()

for script in "${ORDERED[@]}"; do
    path="$SCRIPT_DIR/$script"

    if [ ! -f "$path" ]; then
        echo "WARNING: $script not found in $SCRIPT_DIR — skipping"
        FAIL+=("$script (not found)")
        continue
    fi

    echo
    tput setaf 6
    echo "========================================================================"
    echo "  Running: $script"
    echo "========================================================================"
    tput sgr0
    echo

    if bash "$path"; then
        PASS+=("$script")
    else
        tput setaf 1
        echo "ERROR: $script exited non-zero"
        tput sgr0
        FAIL+=("$script")

        gum confirm "Continue with remaining scripts?" || break
    fi
done

##################################################################################################################################
# Summary
##################################################################################################################################

echo
tput setaf 6
echo "========================================================================"
echo "  Summary"
echo "========================================================================"
tput sgr0
echo

if [ ${#PASS[@]} -gt 0 ]; then
    tput setaf 2
    echo "Passed (${#PASS[@]}):"
    for s in "${PASS[@]}"; do echo "  $s"; done
    tput sgr0
fi

if [ ${#FAIL[@]} -gt 0 ]; then
    tput setaf 1
    echo "Failed (${#FAIL[@]}):"
    for s in "${FAIL[@]}"; do echo "  $s"; done
    tput sgr0
fi

echo
