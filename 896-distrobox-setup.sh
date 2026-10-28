#!/bin/bash
source "$(dirname "$(readlink -f "$0")")/lib.sh"
##################################################################################################################################
# Author    : zythros
# Menu      : Install podman + distrobox; enable shared-root mount service
# Group     : optional
# Purpose   : Install podman + distrobox (rootless containers)
#             Artix/OpenRC port — adds a shared-root OpenRC service, since
#             OpenRC (unlike systemd) leaves "/" as a private mount at boot
##################################################################################################################################
#
#   DO NOT JUST RUN THIS. EXAMINE AND JUDGE. RUN AT YOUR OWN RISK.
#
##################################################################################################################################

script_start "Setting up podman + distrobox"

##################################################################################################################################
# 1. Install packages
##################################################################################################################################

ensure_pkgs podman distrobox || die "podman/distrobox missing — nothing to configure"

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
    if sudo usermod "--add-sub${kind}s" "$start-$end" "$USER"; then
        echo "  Added $USER:$start:65536 to $file"
        SUBIDS_CHANGED=true
    else
        err "could not add a sub${kind} range for $USER — rootless containers will fail"
    fi
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
    sudo tee "$SHARED_ROOT_SVC" > /dev/null <<'RCEOF' || die "could not write $SHARED_ROOT_SVC"
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

enable_service shared-root

##################################################################################################################################
# 4. Summary
##################################################################################################################################

script_done
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
