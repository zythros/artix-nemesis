#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Menu      : Set up wallpaper cycling system
# Purpose   : Set up wallpaper cycling system (can be run standalone)
#
# Artix/dwm differences vs arch-nemesis 810:
#   - wallpaper.sh embedded (no installed_dir / local checkout dep)
#   - autostart via ~/.xprofile instead of chadwm run.sh
#   - no sxhkd keybind wiring (not used with this dwm setup)
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

script_start "Setting up wallpaper system"

##################################################################################################################################
# 1. Install feh
##################################################################################################################################

ensure_pkgs feh

##################################################################################################################################
# 2. Install wallpaper.sh to ~/.local/bin/
##################################################################################################################################

DEST_DIR="$HOME/.local/bin"
mkdir -p "$DEST_DIR"

echo
echo "Installing wallpaper.sh to $DEST_DIR ..."

cat > "$DEST_DIR/wallpaper.sh" <<'WALLPAPER_SCRIPT'
#!/bin/bash
#
# Wallpaper cycler for dwm
# Usage: wallpaper.sh [next|prev|restore]
#
# Cycles through wallpapers in order, persists state across reboots.
#

WALLPAPER_DIR="$HOME/.local/share/wallpapers"
STATE_FILE="$HOME/.local/share/wallpaper-state"

get_wallpapers() {
    find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" \) | sort
}

get_index() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo 0
    fi
}

save_index() {
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$1" > "$STATE_FILE"
}

set_wallpaper() {
    local file="$1"
    if [ -f "$file" ]; then
        feh --bg-fill "$file"
    fi
}

main() {
    local action="${1:-next}"

    mapfile -t wallpapers < <(get_wallpapers)
    local count=${#wallpapers[@]}

    if [ "$count" -eq 0 ]; then
        echo "No wallpapers found in $WALLPAPER_DIR"
        exit 1
    fi

    local index=$(get_index)

    case "$action" in
        next)
            index=$(( (index + 1) % count ))
            ;;
        prev)
            index=$(( (index - 1 + count) % count ))
            ;;
        restore)
            ;;
        *)
            echo "Usage: $0 [next|prev|restore]"
            exit 1
            ;;
    esac

    save_index "$index"
    set_wallpaper "${wallpapers[$index]}"
}

main "$@"
WALLPAPER_SCRIPT

chmod +x "$DEST_DIR/wallpaper.sh"

ok "wallpaper.sh installed."

##################################################################################################################################
# 3. Clone or update wallpaper repository
##################################################################################################################################

WALLPAPER_DIR="$HOME/.local/share/wallpapers"
WALLPAPER_REPO="https://github.com/zythros/wallpaper.git"

echo
git_sync "$WALLPAPER_REPO" "$WALLPAPER_DIR" && ok "Wallpapers at $WALLPAPER_DIR"

##################################################################################################################################
# 4. Configure autostart via ~/.xprofile
#    LightDM sources ~/.xprofile before launching any session.
##################################################################################################################################

XPROFILE="$HOME/.xprofile"
WALLPAPER_LINE='~/.local/bin/wallpaper.sh restore &'

# Ensure ~/.local/bin is in PATH for the X session. LightDM sources ~/.xprofile
# unconditionally regardless of login shell, so this covers fish, bash, sh, etc.
# Without this, dwm cannot find binaries like dmenu-desktop or wallpaper.sh via
# execvp when the login shell is anything other than fish (fish exports its PATH
# via a special fish --login hook in LightDM's Xsession script).
PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

echo
if grep -qF 'export PATH="$HOME/.local/bin' "$XPROFILE" 2>/dev/null; then
    ok "~/.xprofile already exports ~/.local/bin PATH — skipping."
else
    echo "Adding PATH export to $XPROFILE ..."
    # Prepend so PATH is set before wallpaper.sh is called
    if [ -f "$XPROFILE" ]; then
        tmp=$(mktemp)
        echo "$PATH_LINE" > "$tmp"
        cat "$XPROFILE" >> "$tmp"
        mv "$tmp" "$XPROFILE"
    else
        echo "$PATH_LINE" > "$XPROFILE"
    fi
    ok "~/.xprofile PATH updated."
fi

if grep -qF "wallpaper.sh restore" "$XPROFILE" 2>/dev/null; then
    ok "~/.xprofile already contains wallpaper.sh restore — skipping."
else
    echo "Adding wallpaper.sh restore to $XPROFILE ..."
    echo "$WALLPAPER_LINE" >> "$XPROFILE"
    ok "~/.xprofile updated."
fi

##################################################################################################################################
# Summary
##################################################################################################################################

WALLPAPER_COUNT=$(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" -o -iname "*.gif" \) 2>/dev/null | wc -l)

script_done
echo "Wallpaper system installed:"
echo "  Script:     ~/.local/bin/wallpaper.sh"
echo "  Wallpapers: $WALLPAPER_DIR ($WALLPAPER_COUNT images)"
echo "  Autostart:  ~/.xprofile (wallpaper.sh restore, runs on LightDM login)"
echo "  PATH:       ~/.xprofile exports ~/.local/bin (works for any login shell)"
echo
[ "$WALLPAPER_COUNT" -eq 0 ] && warn "No wallpapers found in $WALLPAPER_DIR"
echo "Usage:"
echo "  wallpaper.sh next     - Next wallpaper"
echo "  wallpaper.sh prev     - Previous wallpaper"
echo "  wallpaper.sh restore  - Restore last wallpaper (run at login)"
echo
echo "Keybinds (wired in by 802-dwm-setup.sh):"
echo "  Mod+w           next wallpaper"
echo "  Mod+Shift+w     previous wallpaper"
echo
