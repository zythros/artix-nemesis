#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install and configure spacenavd for 3Dconnexion SpaceNavigator on Artix Linux (OpenRC).
#             Builds spacenavd from source (github.com/FreeSpacenav/spacenavd) with a one-line patch
#             that adds the 3Dconnexion Universal Receiver (256f:c652) to the device blacklist.
#
#             Without the patch, spacenavd opens the Universal Receiver as a second SpaceMouse device.
#             Its dispatch filter then silently drops all wired SpaceNavigator events so FreeCAD gets nothing.
#
#             FreeCAD connects to spacenavd automatically via /var/run/spnav.sock — no extra FreeCAD config needed.
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

if [ "$DEBUG" = true ]; then
    echo
    echo "------------------------------------------------------------"
    echo "Running $(basename $0)"
    echo "------------------------------------------------------------"
    echo
    read -n 1 -s -r -p "Debug mode is on. Press any key to continue..."
    echo
fi

echo
tput setaf 2
echo "########################################################################"
echo "################### SpaceMouse / spacenavd setup"
echo "########################################################################"
tput sgr0
echo

##################################################################################################################################
# Authenticate sudo once; keepalive prevents expiry during build
##################################################################################################################################

sudo -v
while true; do timeout 30 sudo -v; sleep 50; done &
SUDO_KEEPALIVE=$!

artix_pacman_nohook_setup
trap "artix_pacman_cleanup; kill $SUDO_KEEPALIVE 2>/dev/null" EXIT

##################################################################################################################################
# Step 1: Build and runtime dependencies
##################################################################################################################################

echo
tput setaf 3
echo "── Installing build and runtime dependencies ────────────────────────────"
tput sgr0

DEPS=(git base-devel libx11 libxi libxtst)
for dep in "${DEPS[@]}"; do
    if pacman -Q "$dep" &>/dev/null; then
        echo "  $dep already installed."
    else
        echo "  Installing $dep ..."
        sudo pacman --config "$NOHOOK_CONF" -S --noconfirm --needed "$dep" || {
            tput setaf 1; echo "ERROR: failed to install $dep" >&2; tput sgr0; exit 1
        }
        tput setaf 2; echo "  $dep installed."; tput sgr0
    fi
done

# spnav (libspnav): FreeCAD's optional dep for /var/run/spnav.sock communication
if pacman -Q spnav &>/dev/null || pacman -Q libspnav &>/dev/null; then
    echo "  libspnav already installed."
else
    echo "  Installing spnav (libspnav) ..."
    sudo pacman --config "$NOHOOK_CONF" -S --noconfirm --needed spnav 2>/dev/null \
        || echo "  WARNING: could not install spnav — FreeCAD may not see the spacemouse" >&2
fi

##################################################################################################################################
# Step 2: Build spacenavd from source with patch
##################################################################################################################################

echo
tput setaf 3
echo "── Building spacenavd from source ───────────────────────────────────────"
tput sgr0

BUILD_DIR="$(mktemp -d)"
trap "artix_pacman_cleanup; rm -rf '$BUILD_DIR'; kill $SUDO_KEEPALIVE 2>/dev/null" EXIT

cat > "$BUILD_DIR/PKGBUILD" <<'PKGEOF'
pkgname=spacenavd
pkgver=1.3.1
pkgrel=1
pkgdesc="Free user-space driver for 6-dof space-mice"
arch=('x86_64')
url="https://github.com/FreeSpacenav/spacenavd"
license=('GPL3')
depends=('libx11' 'libxi' 'libxtst')
makedepends=('git')
source=("git+https://github.com/FreeSpacenav/spacenavd.git")
sha256sums=('SKIP')

prepare() {
    cd spacenavd
    # Add 256f:c652 (3Dconnexion Universal Receiver) to spacenavd's device blacklist.
    # Without this, spacenavd opens it as a second SpaceMouse device; the dispatch filter
    # in event.c then drops all wired SpaceNavigator events because get_client_device()
    # returns the first device in the list (the receiver) instead of the SpaceNavigator.
    python3 -c "
content = open('src/dev.c').read()
anchor = '\t{0x256f, 0xc641},\t/* scout(?) */'
addition = '\n\t{0x256f, 0xc652},\t/* Universal Receiver (non-SpaceMouse dongle) */'
if anchor not in content:
    raise SystemExit('patch anchor not found in src/dev.c — source may have changed')
if '0xc652' in content:
    print('patch already applied — skipping')
else:
    open('src/dev.c', 'w').write(content.replace(anchor, anchor + addition, 1))
    print('patch applied: Universal Receiver (256f:c652) blacklisted')
"
}

build() {
    cd spacenavd
    ./configure --prefix=/usr
    make
}

package() {
    cd spacenavd
    make DESTDIR="$pkgdir" install
    install -Dm644 doc/example-spnavrc "$pkgdir/etc/spnavrc.example"
}
PKGEOF

echo "  Cloning and building spacenavd (this will take a moment) ..."
(cd "$BUILD_DIR" && makepkg -f 2>&1) || {
    tput setaf 1; echo "ERROR: makepkg failed — check output above" >&2; tput sgr0; exit 1
}

PKG="$(ls "$BUILD_DIR"/spacenavd-*.pkg.tar.zst 2>/dev/null | head -1)"
[ -z "$PKG" ] && { tput setaf 1; echo "ERROR: built package not found in $BUILD_DIR" >&2; tput sgr0; exit 1; }

echo "  Installing $(basename "$PKG") ..."
sudo rm -f /var/lib/pacman/db.lck
sudo pacman --config "$NOHOOK_CONF" -U --noconfirm "$PKG" || {
    tput setaf 1; echo "ERROR: pacman -U failed" >&2; tput sgr0; exit 1
}
tput setaf 2; echo "  spacenavd installed."; tput sgr0

##################################################################################################################################
# Step 3: spnavcfg (interactive GUI for live sensitivity/axis tuning)
##################################################################################################################################

echo
tput setaf 3
echo "── Installing spnavcfg (spacenav GUI configurator) ──────────────────────"
tput sgr0

if pacman -Q spnavcfg &>/dev/null; then
    echo "  spnavcfg already installed."
elif command -v yay &>/dev/null; then
    echo "  Building spnavcfg from AUR ..."
    yay -S --noconfirm spnavcfg && { tput setaf 2; echo "  spnavcfg installed."; tput sgr0; } \
        || { tput setaf 1; echo "  WARNING: spnavcfg install failed — configure /etc/spnavrc manually" >&2; tput sgr0; }
else
    tput setaf 3
    echo "  WARNING: yay not found — skipping spnavcfg (run 801 first, then reinstall)" >&2
    tput sgr0
fi

##################################################################################################################################
# Step 4: OpenRC init script

##################################################################################################################################

echo
tput setaf 3
echo "── Installing OpenRC init script ─────────────────────────────────────────"
tput sgr0

sudo tee /etc/init.d/spacenavd > /dev/null <<'RCEOF'
#!/sbin/openrc-run

description="Free driver for 3Dconnexion 6dof devices"
pidfile="/var/run/spnavd.pid"

depend() {
    need localmount
    use logger
}

start() {
    ebegin "Starting spacenavd"
    /usr/bin/spacenavd -v
    eend $?
}

stop() {
    ebegin "Stopping spacenavd"
    start-stop-daemon --stop --quiet --pidfile "$pidfile"
    eend $?
}
RCEOF

sudo chmod 755 /etc/init.d/spacenavd
tput setaf 2; echo "  /etc/init.d/spacenavd written."; tput sgr0

##################################################################################################################################
# Step 5: Enable and start service
##################################################################################################################################

echo
tput setaf 3
echo "── Enabling and starting spacenavd ───────────────────────────────────────"
tput sgr0

sudo rc-update add spacenavd default 2>/dev/null || true
echo "  spacenavd enabled in default runlevel."

# Kill any manually-started spacenavd before handing off to rc-service
if pgrep -x spacenavd > /dev/null; then
    echo "  Stopping existing spacenavd process ..."
    sudo pkill -x spacenavd || true
    sleep 1
fi

sudo rc-service spacenavd start && { tput setaf 2; echo "  spacenavd started."; tput sgr0; } || {
    tput setaf 1; echo "ERROR: spacenavd failed to start" >&2; tput sgr0; exit 1
}

##################################################################################################################################
# Verify
##################################################################################################################################

sleep 1
if [ -S /var/run/spnav.sock ]; then
    tput setaf 2
    echo
    echo "  /var/run/spnav.sock present — daemon is ready."
    tput sgr0
else
    tput setaf 1
    echo "  WARNING: /var/run/spnav.sock not found — check: sudo spacenavd -d -vv" >&2
    tput sgr0
fi

##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
tput setaf 2
echo "SpaceMouse setup complete."
echo "Connect the SpaceNavigator and open FreeCAD — it connects automatically."
tput sgr0
echo
