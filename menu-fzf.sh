#!/bin/bash
##################################################################################################################################
# Author    : zythros
# Purpose   : fzf-based menu to select and run artix-nemesis setup scripts
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

if ! command -v fzf &>/dev/null; then
    echo "Installing fzf..."
    artix_pacman_nohook_setup
    sudo pacman --config "$NOHOOK_CONF" -S --noconfirm fzf || { echo "Could not install fzf — aborting" >&2; exit 1; }
fi

# Pairs: script filename, description — built from each numbered script's
# "# Menu      : <description>" header line, in filename (= run) order.
# Scripts without that line (e.g. 897) are deliberately left out of the menu.
ENTRIES=()
for path in "$SCRIPT_DIR"/[0-9][0-9][0-9]-*.sh; do
    desc="$(sed -n 's/^# Menu *: //p' "$path" | head -1)"
    [ -n "$desc" ] && ENTRIES+=("$(basename "$path")" "$desc")
done

[ ${#ENTRIES[@]} -eq 0 ] && { echo "No scripts with a '# Menu' header found in $SCRIPT_DIR" >&2; exit 1; }

##################################################################################################################################
# Build menu lines and prompt with fzf
##################################################################################################################################

MAX_LEN=0
for (( i=0; i<${#ENTRIES[@]}; i+=2 )); do
    (( ${#ENTRIES[i]} > MAX_LEN )) && MAX_LEN=${#ENTRIES[i]}
done

MENU_LINES=()
for (( i=0; i<${#ENTRIES[@]}; i+=2 )); do
    MENU_LINES+=("$(printf "%-${MAX_LEN}s  —  %s" "${ENTRIES[i]}" "${ENTRIES[i+1]}")")
done

SELECTED=$(printf '%s\n' "${MENU_LINES[@]}" | fzf \
    --multi \
    --prompt="artix-nemesis > " \
    --header="TAB to select/deselect  |  ENTER to confirm  |  ESC to cancel" \
    --header-first \
    --bind "tab:toggle+down" \
    --reverse \
    --no-sort) || exit 0

[ -z "$SELECTED" ] && { echo "Nothing selected."; exit 0; }

# Extract script filenames from selected lines (everything before the first space)
QUEUE=()
while IFS= read -r line; do
    script="${line%%  *}"
    QUEUE+=("$script")
done <<< "$SELECTED"

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
