#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Menu      : Build slstatus; write datetime to DWM bar
# Purpose   : Build slstatus from zythros fork; autostart via ~/.xprofile
#
# Artix/dwm differences vs arch-nemesis 830:
#   - Clone to ~/.local/src/slstatus (not ~/.config/arco-chadwm/slstatus)
#   - Autostart via ~/.xprofile (LightDM sources unconditionally for dwm)
#   - Volume component stripped from config.h at build time (not needed)
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

script_start "Setting up slstatus (zythros fork)"
pkg_sync

##################################################################################################################################
# 1. Build dependencies
##################################################################################################################################

section "Dependencies"
ensure_pkgs base-devel libx11

##################################################################################################################################
# 2. Remove pacman-installed slstatus (replaced by fork)
##################################################################################################################################

if pacman -Qi slstatus &>/dev/null; then
    _c setaf 3
    echo
    echo "Removing pacman slstatus (will be replaced by zythros fork) ..."
    _c sgr0
    if sudo pacman -Rns --noconfirm slstatus; then
        ok "Pacman slstatus removed."
    else
        err "could not remove pacman slstatus — the fork's install may be shadowed"
    fi
fi

##################################################################################################################################
# 3. Clone or update zythros/slstatus
##################################################################################################################################

SLSTATUS_SRC="$HOME/.local/src/slstatus"

echo
git_sync https://github.com/zythros/slstatus.git "$SLSTATUS_SRC" \
    || die "no up-to-date slstatus source — not building with stale/uncertain source"

##################################################################################################################################
# 4. Strip volume component from config.h
#    The fork's config.h includes a pamixer-based volume entry; remove it so
#    the bar shows only CPU, RAM, and datetime.
##################################################################################################################################

echo
echo "Patching config.h (removing volume, cpu, ram components) ..."
sed -i '/pamixer/d; /cpu_perc/d; /ram_perc/d' "$SLSTATUS_SRC/config.h" || die "config.h patch failed"
ok "config.h patched."

##################################################################################################################################
# 5. Build and install
##################################################################################################################################

echo
make_install "$SLSTATUS_SRC" || die "slstatus build/install failed"

command -v slstatus &>/dev/null || die "slstatus not found after install"

##################################################################################################################################
# 6. Autostart via ~/.xprofile
##################################################################################################################################

XPROFILE="$HOME/.xprofile"

echo
if grep -qF 'slstatus &' "$XPROFILE" 2>/dev/null; then
    ok "~/.xprofile already starts slstatus — skipping."
else
    _c setaf 3
    echo "Adding slstatus autostart to ~/.xprofile ..."
    _c sgr0
    cat >> "$XPROFILE" <<'XPROFILE_ENTRY'

# slstatus — writes CPU/RAM/datetime to DWM status bar
slstatus &
XPROFILE_ENTRY
    ok "~/.xprofile updated."
fi

##################################################################################################################################
# 7. Best-effort live restart (only if already running in this session)
##################################################################################################################################

if [ -n "${DISPLAY:-}" ] && pgrep -x slstatus &>/dev/null; then
    _c setaf 3
    echo
    echo "Restarting running slstatus ..."
    _c sgr0
    pkill -x slstatus || true
    slstatus &
    ok "slstatus restarted."
fi

##################################################################################################################################
# Summary
##################################################################################################################################

script_done
echo "slstatus (zythros fork) installed:"
echo "  Source:  $SLSTATUS_SRC"
echo "  Binary:  $(which slstatus)"
echo
echo "Status bar components:"
echo "  Datetime — datetime  (bg #222222 black, fg #eeeeee white)"
echo "  Update interval: 1000ms"
echo
echo "Autostart: ~/.xprofile → slstatus & (takes effect at next login)"
echo "Requires status2d patch in dwm fork for colored segments."
echo
