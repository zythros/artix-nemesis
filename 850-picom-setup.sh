#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Menu      : picom compositor for dwm (real GPU only; --force for VMs)
# Group     : optional
# Purpose   : Install picom (X11 compositor: tear-free vsync, optional
#             transparency), write ~/.config/picom/picom.conf and start it
#             from ~/.xprofile. dwm has no compositor of its own.
#             Checks the GPU first: picom on a software-rendered display
#             (plain VM, no driver yet) lags and tears, so it skips there
#             unless run with --force, which uses the xrender backend.
#             Undo: remove the picom line from ~/.xprofile.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

# Kernel DRM drivers that mean a real, OpenGL-capable GPU. Anything else
# (virtio_gpu, qxl, bochs-drm, vmwgfx, cirrus, simpledrm, ...) is treated
# as software rendering.
REAL_GPU_DRIVERS="nvidia amdgpu radeon i915 xe nouveau"

##################################################################################################################################

FORCE=false
[ "${1:-}" = "--force" ] && FORCE=true

script_start "Setting up picom"

##################################################################################################################################
# 1. GPU check — glx backend on a real GPU, skip (or xrender with --force) otherwise
#    Reads the kernel driver behind each /sys/class/drm/cardN, so it works
#    from a TTY or ssh with no X running (glxinfo would need a display).
##################################################################################################################################

section "GPU check"
GPU_DRIVERS=""
for card in /sys/class/drm/card[0-9]*; do
    [[ "$card" == *-* ]] && continue    # connectors (card1-DP-1), not cards
    [ -e "$card/device/driver" ] || continue
    GPU_DRIVERS+="$(basename "$(readlink -f "$card/device/driver")") "
done
GPU_DRIVERS=${GPU_DRIVERS% }
echo "DRM drivers: ${GPU_DRIVERS:-none}"

BACKEND=""
for drv in $GPU_DRIVERS; do
    [[ " $REAL_GPU_DRIVERS " == *" $drv "* ]] && { BACKEND=glx; break; }
done

if [ -n "$BACKEND" ]; then
    ok "Real GPU found — using the glx backend with vsync."
elif $FORCE; then
    BACKEND=xrender
    warn "no real GPU driver ($GPU_DRIVERS) — --force given, using the xrender backend; expect lag/tearing"
else
    script_skip "No real GPU driver loaded (${GPU_DRIVERS:-none}) — picom would run in software and lag/tear.
Run with --force to install it anyway (xrender backend)."
fi

##################################################################################################################################
# 2. Package
##################################################################################################################################

section "Package"
ensure_pkgs picom || die "picom not installed"

##################################################################################################################################
# 3. ~/.config/picom/picom.conf — only written if missing, so edits survive re-runs
##################################################################################################################################

section "Config"
PICOM_CONF="$HOME/.config/picom/picom.conf"
if [ -f "$PICOM_CONF" ]; then
    echo "$PICOM_CONF exists — leaving it alone (backend for this machine: $BACKEND)."
else
    mkdir -p "$(dirname "$PICOM_CONF")"
    cat > "$PICOM_CONF" <<EOF
# Written by artix-nemesis 850-picom-setup.sh — edit freely, re-runs keep it.
# glx needs a real GPU; xrender is the software fallback.
backend = "$BACKEND";
vsync = true;

# Full-screen windows (games, video) bypass the compositor
unredir-if-possible = true;

# Off by default on a tiling WM; turn on to taste
shadow = false;
fading = false;

# Transparency is per app, e.g. alacritty: [window] opacity = 0.9
EOF
    ok "Wrote $PICOM_CONF (backend $BACKEND)."
fi

##################################################################################################################################
# 4. Start at login (~/.xprofile, sourced by LightDM) and now if in X
##################################################################################################################################

section "Autostart"
XPROFILE="$HOME/.xprofile"
if grep -qF 'picom' "$XPROFILE" 2>/dev/null; then
    echo "$XPROFILE already starts picom — skipping."
else
    echo 'command -v picom >/dev/null && picom -b  # compositor (850-picom-setup.sh)' >> "$XPROFILE"
    ok "picom added to $XPROFILE (starts at next login)."
fi

if [ -n "${DISPLAY:-}" ] && ! pgrep -x picom &>/dev/null; then
    if picom -b; then
        ok "picom started in this session."
    else
        err "picom failed to start — try: picom --log-level=debug"
    fi
fi

##################################################################################################################################

script_done
echo "picom:   backend $BACKEND, vsync on"
echo "Config:  $PICOM_CONF"
echo "Start:   $XPROFILE (picom -b at login)"
echo "Stop:    pkill picom; remove the line from $XPROFILE to disable"
echo
