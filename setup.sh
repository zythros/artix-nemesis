#!/bin/bash
##################################################################################################################################
# Author    : zythros
# Purpose   : TUI menu to select and run artix-nemesis setup scripts
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v whiptail &>/dev/null; then
    TUI=whiptail
elif command -v dialog &>/dev/null; then
    TUI=dialog
else
    echo "Installing dialog..."
    sudo pacman -S --noconfirm dialog || { echo "Could not install dialog — aborting" >&2; exit 1; }
    TUI=dialog
fi

# Pairs: script filename, menu description (in desired run order)
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
# Build checklist and prompt
##################################################################################################################################

CHECKLIST_ARGS=()
for (( i=0; i<${#ENTRIES[@]}; i+=2 )); do
    CHECKLIST_ARGS+=("${ENTRIES[i]}" "${ENTRIES[i+1]}" "OFF")
done

SELECTED=$($TUI \
    --title "artix-nemesis setup" \
    --checklist "Select scripts to run (SPACE to toggle, ENTER to confirm):" \
    22 82 12 \
    "${CHECKLIST_ARGS[@]}" \
    3>&1 1>&2 2>&3) || exit 0

[ -z "$SELECTED" ] && { echo "Nothing selected."; exit 0; }

# whiptail returns space-separated quoted strings — eval into array
eval "QUEUE=($SELECTED)"

##################################################################################################################################
# Confirm
##################################################################################################################################

CONFIRM_MSG="Run the following scripts in order?\n"
for s in "${QUEUE[@]}"; do
    CONFIRM_MSG+="\n  $s"
done

$TUI \
    --title "Confirm" \
    --yesno "$CONFIRM_MSG" \
    20 82 || { echo "Aborted."; exit 0; }

##################################################################################################################################
# Run selected scripts in order
##################################################################################################################################

PASS=()
FAIL=()

for script in "${QUEUE[@]}"; do
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

        if ! $TUI \
            --title "Script failed" \
            --yesno "$script exited with an error.\n\nContinue with remaining scripts?" \
            12 82; then
            break
        fi
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
