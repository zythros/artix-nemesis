#!/bin/bash
##################################################################################################################################
# Author    : zythros
# Purpose   : Plain numbered menu to select and run artix-nemesis setup scripts
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

TOTAL=$(( ${#ENTRIES[@]} / 2 ))

##################################################################################################################################
# Print menu
##################################################################################################################################

echo
echo "  artix-nemesis setup"
echo "  ==================="
echo
for (( i=0; i<${#ENTRIES[@]}; i+=2 )); do
    n=$(( i/2 + 1 ))
    printf "  %2d)  %-30s  %s\n" "$n" "${ENTRIES[i]}" "${ENTRIES[i+1]}"
done
echo
read -r -p "  Enter numbers to run (e.g. 1 3 5): " input

[ -z "$input" ] && { echo "Nothing selected."; exit 0; }

##################################################################################################################################
# Parse and validate input
##################################################################################################################################

QUEUE=()
for token in $input; do
    if ! [[ "$token" =~ ^[0-9]+$ ]] || (( token < 1 || token > TOTAL )); then
        echo "Invalid selection: $token — must be between 1 and $TOTAL"
        exit 1
    fi
    idx=$(( (token - 1) * 2 ))
    QUEUE+=("${ENTRIES[idx]}")
done

# Deduplicate while preserving order
declare -A seen
DEDUPED=()
for s in "${QUEUE[@]}"; do
    if [ -z "${seen[$s]+x}" ]; then
        DEDUPED+=("$s")
        seen[$s]=1
    fi
done
QUEUE=("${DEDUPED[@]}")

##################################################################################################################################
# Confirm
##################################################################################################################################

echo
echo "The following scripts will run in order:"
for s in "${QUEUE[@]}"; do
    echo "  $s"
done
echo
read -r -p "Proceed? [y/N] " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

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

        read -r -p "Continue with remaining scripts? [y/N] " cont
        [[ "$cont" =~ ^[Yy]$ ]] || break
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
