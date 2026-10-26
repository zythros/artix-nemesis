#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Purpose   : Install podman + distrobox (rootless containers)
#             Artix/OpenRC port — adds a shared-root OpenRC service, since
#             OpenRC (unlike systemd) leaves "/" as a private mount at boot
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
echo "################### Setting up podman + distrobox"
echo "########################################################################"
tput sgr0
echo

artix_pacman_nohook_setup

##################################################################################################################################
# 1. Install packages
##################################################################################################################################

echo "Installing packages..."

FAILED=()
for pkg in podman distrobox; do
    if pacman -Q "$pkg" &>/dev/null; then
        echo "  $pkg already installed — skipping."
    else
        pkg_install "$pkg" || true  # timeout/hook failures don't abort — check pacman -Q as truth
        if pacman -Q "$pkg" &>/dev/null; then
            echo "  $pkg installed."
        else
            tput setaf 1
            echo "  ERROR: $pkg installation failed." >&2
            tput sgr0
            FAILED+=("$pkg")
        fi
    fi
done

if [ ${#FAILED[@]} -gt 0 ]; then
    tput setaf 1
    echo "Could not install: ${FAILED[*]} — aborting." >&2
    tput sgr0
    exit 1
fi

##################################################################################################################################
# 2. subuid/subgid ranges for rootless podman
##################################################################################################################################

# Rootless podman maps container UIDs/GIDs onto a range of host IDs listed
# in /etc/subuid and /etc/subgid. Without an entry for $USER, rootless
# containers fail ("cannot find mappings for user"). Allocate 65536 IDs
# starting past the highest range already in use, so we never overlap
# another user's allocation.

echo
echo "Checking subuid/subgid ranges for $USER..."

SUBIDS_CHANGED=false
for kind in uid gid; do
    file="/etc/sub$kind"
    if grep -q "^$USER:" "$file" 2>/dev/null; then
        echo "  $file already has an entry for $USER — skipping."
        continue
    fi
    start=$(awk -F: 'BEGIN { max = 100000 } { end = $2 + $3; if (end > max) max = end } END { print max }' "$file" 2>/dev/null)
    end=$((start + 65535))
    sudo usermod "--add-sub${kind}s" "$start-$end" "$USER"
    echo "  Added $USER:$start:65536 to $file"
    SUBIDS_CHANGED=true
done

# Existing podman storage was built without the new mapping — refresh it
if [ "$SUBIDS_CHANGED" = true ]; then
    podman system migrate 2>/dev/null || true
fi

##################################################################################################################################
# 3. shared-root OpenRC service
##################################################################################################################################

# Rootless podman/distrobox need "/" to have shared mount propagation.
# systemd sets this automatically at boot; OpenRC does not, so podman
# warns `"/" is not a shared mount` and host mounts made after a container
# starts (USB drives, shares) don't show up inside it. Fix: a small custom
# OpenRC service that runs `mount --make-rshared /` at boot.

echo
echo "Configuring shared-root service..."

SHARED_ROOT_SVC="/etc/init.d/shared-root"
if [ -f "$SHARED_ROOT_SVC" ]; then
    echo "  $SHARED_ROOT_SVC already exists — skipping."
else
    sudo tee "$SHARED_ROOT_SVC" > /dev/null <<'RCEOF'
#!/sbin/openrc-run

description="Mark / as a shared mount (required for podman/distrobox rootless mounts)"

depend() {
    need localmount
}

start() {
    ebegin "Marking / as a shared mount"
    mount --make-rshared /
    eend $?
}
RCEOF
    sudo chmod 755 "$SHARED_ROOT_SVC"
    echo "  Wrote $SHARED_ROOT_SVC"
fi

sudo rc-update add shared-root default 2>/dev/null || true
echo "  shared-root enabled at default runlevel."

if sudo rc-service shared-root start 2>/dev/null; then
    echo "  / is now a shared mount."
else
    echo "  shared-root already applied (or start failed — check: sudo rc-service shared-root status)."
fi

##################################################################################################################################
# 4. Summary
##################################################################################################################################

echo
tput setaf 6
echo "##############################################################"
echo "###################  $(basename $0) done"
echo "##############################################################"
echo
echo "Installed:"
echo "  - podman (rootless container engine)"
echo "  - distrobox (run other distros' containers as if native)"
echo
echo "Services enabled (OpenRC):"
echo "  - shared-root (mount --make-rshared / at boot)"
echo
echo "Try it:  distrobox create -i ubuntu:24.04 -n testbox && distrobox enter testbox"
echo
echo "Known upstream bug (distrobox#1983): distrobox stop/rm can hang on"
echo "non-systemd distros. If a container gets stuck in 'Stopping':"
echo "  podman rm -f <name>"
echo
tput sgr0
