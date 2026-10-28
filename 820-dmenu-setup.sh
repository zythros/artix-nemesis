#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Menu      : Build dmenu; wire j4-dmenu-desktop into dwm
# Group     : core
# Purpose   : Build dmenu from zythros fork; wire j4-dmenu-desktop into dwm
#
# Artix/dwm differences vs arch-nemesis 820:
#   - Clone to ~/.local/src/dmenu (not ~/.config/arco-chadwm/dmenu)
#   - No sxhkdrc — patches dwm config.h dmenucmd[] to call a wrapper script,
#     then rebuilds dwm (same pattern as 802's wallpaper keybind patch)
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

script_start "Setting up dmenu (zythros fork)"
pkg_sync

##################################################################################################################################
# 1. Build dependencies + j4-dmenu-desktop
##################################################################################################################################

section "Dependencies"
ensure_pkgs base-devel libx11 libxft libxinerama j4-dmenu-desktop

##################################################################################################################################
# 2. Remove pacman-installed dmenu (replaced by fork)
##################################################################################################################################

if pacman -Qi dmenu &>/dev/null; then
    _c setaf 3
    echo
    echo "Removing pacman dmenu (will be replaced by zythros fork) ..."
    _c sgr0
    if sudo pacman -Rns --noconfirm dmenu; then
        ok "Pacman dmenu removed."
    else
        err "could not remove pacman dmenu — the fork's install may be shadowed"
    fi
fi

##################################################################################################################################
# 3. Clone or update zythros/dmenu
##################################################################################################################################

DMENU_SRC="$HOME/.local/src/dmenu"

echo
git_sync https://github.com/zythros/dmenu.git "$DMENU_SRC" || die "no dmenu source — nothing to build"

##################################################################################################################################
# 4. Build and install dmenu fork
##################################################################################################################################

echo
make_install "$DMENU_SRC" || die "dmenu build/install failed"

##################################################################################################################################
# 5. Write dmenu-desktop wrapper script
#    dwm spawns binaries via execvp — a wrapper is the cleanest way to pass
#    the j4-dmenu-desktop --dmenu="..." flag without embedding shell escaping
#    inside a C string array in config.h.
##################################################################################################################################

WRAPPER="$HOME/.local/bin/dmenu-desktop"
mkdir -p "$HOME/.local/bin"

echo
echo "Writing $WRAPPER ..."
# Colors match the dwm bar (zythros/dwm config.h): col_gray1/col_gray3 for
# normal, col_cyan/col_gray4 for the selected entry.
cat > "$WRAPPER" <<'EOF'
#!/bin/bash
exec j4-dmenu-desktop --dmenu="dmenu -i -c -l 8 -fn 'monospace:size=12' -nb '#222222' -nf '#bbbbbb' -sb '#005577' -sf '#eeeeee'"
EOF
chmod +x "$WRAPPER"

ok "Wrapper written."

##################################################################################################################################
# 6. Patch dwm config.h — replace dmenucmd[] to call dmenu-desktop wrapper
##################################################################################################################################

DWM_SRC="$HOME/.local/src/dwm"

[ -f "$DWM_SRC/config.h" ] || die "$DWM_SRC/config.h not found — run 802-dwm-setup.sh first"

echo
echo "Patching dwm config.h ..."

# Use the absolute path so dwm's execvp finds the wrapper regardless of
# what PATH LightDM passes to the X session (fish PATH is not inherited).
python3 - "$DWM_SRC/config.h" "$WRAPPER" <<'PYPATCH'
import sys, re
path, wrapper = sys.argv[1], sys.argv[2]
text = open(path).read()

if wrapper in text:
    print("dmenucmd already patched — skipping.")
    sys.exit(0)

new_line = f'static const char *dmenucmd[] = {{ "{wrapper}", NULL }};'
new_text = re.sub(r'static const char \*dmenucmd\[\][^;]*;', new_line, text, count=1)

if new_text == text:
    print("ERROR: dmenucmd line not found in config.h")
    sys.exit(1)

open(path, 'w').write(new_text)
print(f"dmenucmd patched → {wrapper}")
PYPATCH

[ $? -eq 0 ] || die "config.h patch failed"

ok "config.h patched."

##################################################################################################################################
# 7. Rebuild and reinstall dwm
##################################################################################################################################

echo
make_install "$DWM_SRC" || die "dwm rebuild failed — Mod+d still runs the old launcher"

##################################################################################################################################
# Summary
##################################################################################################################################

DMENU_VERSION=$(dmenu -v 2>&1 | head -1)

script_done
echo "dmenu (zythros fork) installed:"
echo "  Source:  $DMENU_SRC"
echo "  Binary:  $(which dmenu)"
echo "  Version: $DMENU_VERSION"
echo
echo "j4-dmenu-desktop installed:"
echo "  Reads .desktop files — shows apps by display name"
echo
echo "Launcher wrapper: $WRAPPER"
echo "  j4-dmenu-desktop with centered grid style (-c -l 8), dwm bar colors"
echo
echo "dwm rebuilt: Mod+d → dmenu-desktop (j4 + zythros fork), Mod+Shift+d → rofi"
echo
echo "Patches in zythros/dmenu fork:"
echo "  -c    center on screen"
echo "  -l N  grid/list layout"
echo
