#!/bin/bash
##################################################################################################################################
# Author    : zythros
# Purpose   : fzf-based menu to select and run artix-nemesis setup scripts
#
#   Usage:  ./menu-fzf.sh                 pick scripts with fzf (TAB to multi-select)
#           ./menu-fzf.sh --list          print the menu and exit
#           ./menu-fzf.sh --run 800 802   run those scripts in order, no prompts
#
#   Exits non-zero if any script failed.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Triples: script filename, group, description — built from each numbered
# script's "# Menu      : <description>" and "# Group     : <group>" header
# lines, in filename (= run) order.
# Scripts without a Menu line (e.g. 897) are deliberately left out of the menu.
ENTRIES=()
for path in "$SCRIPT_DIR"/[0-9][0-9][0-9]-*.sh; do
    desc="$(sed -n 's/^# Menu *: //p' "$path" | head -1)"
    group="$(sed -n 's/^# Group *: //p' "$path" | head -1)"
    [ -n "$desc" ] && ENTRIES+=("$(basename "$path")" "${group:-other}" "$desc")
done

[ ${#ENTRIES[@]} -eq 0 ] && { echo "No scripts with a '# Menu' header found in $SCRIPT_DIR" >&2; exit 1; }

MAX_LEN=0
for (( i=0; i<${#ENTRIES[@]}; i+=3 )); do
    (( ${#ENTRIES[i]} > MAX_LEN )) && MAX_LEN=${#ENTRIES[i]}
done

MENU_LINES=()
for (( i=0; i<${#ENTRIES[@]}; i+=3 )); do
    MENU_LINES+=("$(printf "%-${MAX_LEN}s  %-10s  —  %s" "${ENTRIES[i]}" "[${ENTRIES[i+1]}]" "${ENTRIES[i+2]}")")
done

##################################################################################################################################
# Pick scripts: --list, --run, or interactively with fzf
##################################################################################################################################

QUEUE=()
INTERACTIVE=true

case "${1:-}" in
    --list)
        printf '%s\n' "${MENU_LINES[@]}"
        exit 0
        ;;
    --run)
        shift
        [ $# -gt 0 ] || { echo "Usage: $(basename "$0") --run <number>..." >&2; exit 2; }
        INTERACTIVE=false
        for n in "$@"; do
            match=("$SCRIPT_DIR/$n"-*.sh)
            if [ ! -f "${match[0]}" ]; then
                echo "No script numbered $n in $SCRIPT_DIR" >&2
                exit 2
            fi
            QUEUE+=("$(basename "${match[0]}")")
        done
        ;;
    "")
        ;;
    *)
        echo "Usage: $(basename "$0") [--list | --run <number>...]" >&2
        exit 2
        ;;
esac

if [ "$INTERACTIVE" = true ]; then
    if ! command -v fzf &>/dev/null; then
        echo "Installing fzf..."
        ensure_pkgs fzf || exit 1
    fi

    SELECTED=$(printf '%s\n' "${MENU_LINES[@]}" | fzf \
        --multi \
        --prompt="artix-nemesis > " \
        --header="TAB to select/deselect  |  ENTER to confirm  |  ESC to cancel" \
        --header-first \
        --bind "tab:toggle+down" \
        --reverse \
        --no-sort) || exit 0

    [ -z "$SELECTED" ] && { echo "Nothing selected."; exit 0; }

    # Extract script filenames from selected lines (everything before the first double space)
    while IFS= read -r line; do
        QUEUE+=("${line%%  *}")
    done <<< "$SELECTED"

    echo
    echo "The following scripts will run in order:"
    for s in "${QUEUE[@]}"; do
        echo "  $s"
    done
    echo
    read -r -p "Proceed? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

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
    _c setaf 6
    echo "========================================================================"
    echo "  Running: $script"
    echo "========================================================================"
    _c sgr0
    echo

    if bash "$path"; then
        PASS+=("$script")
    else
        _c setaf 1
        echo "ERROR: $script exited non-zero"
        _c sgr0
        FAIL+=("$script")

        # Unattended runs carry on; the summary and exit status report it
        if [ "$INTERACTIVE" = true ]; then
            read -r -p "Continue with remaining scripts? [y/N] " cont
            [[ "$cont" =~ ^[Yy]$ ]] || break
        fi
    fi
done

##################################################################################################################################
# Summary
##################################################################################################################################

echo
_c setaf 6
echo "========================================================================"
echo "  Summary"
echo "========================================================================"
_c sgr0
echo

if [ ${#PASS[@]} -gt 0 ]; then
    _c setaf 2
    echo "Passed (${#PASS[@]}):"
    for s in "${PASS[@]}"; do echo "  $s"; done
    _c sgr0
fi

if [ ${#FAIL[@]} -gt 0 ]; then
    _c setaf 1
    echo "Failed (${#FAIL[@]}):"
    for s in "${FAIL[@]}"; do echo "  $s"; done
    _c sgr0
fi

echo
[ ${#FAIL[@]} -eq 0 ]
