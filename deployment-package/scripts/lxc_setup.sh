#!/usr/bin/env bash
# Quick helper to create a Debian 12 LXC for smb‑gateway

set -euo pipefail
SHARE_NAME=${1:-share}
CTID=$(pvesh get /cluster/nextid)
TEMPLATE=local:vztmpl/debian-12-standard_20240410_amd64.tar.zst
ROOTFS="local-lvm:2"

pct create "$CTID" "$TEMPLATE" --rootfs "$ROOTFS"             --hostname "smb-$SHARE_NAME" --unprivileged 1 --memory 128 --net0 name=eth0,bridge=vmbr0,ip=dhcp

mkdir -p "/srv/smb/$SHARE_NAME"
pct set "$CTID" -mp0 "/srv/smb/$SHARE_NAME,mp=/srv/share,ro=0"
pct start "$CTID"
echo "LXC $CTID created and started. Mountpoint /srv/smb/$SHARE_NAME shared."
