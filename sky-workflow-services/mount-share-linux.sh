#!/usr/bin/env bash
set -euo pipefail
umask 077
: "${SHARED_ALIST_USERNAME:?missing WebDAV username}"
: "${SHARED_ALIST_PASSWORD:?missing WebDAV password}"
work="$HOME/.sky-share"
mount="$HOME/Desktop/AList共享"
mkdir -p "$work" "$mount"
unzip -oq "$RUNNER_TEMP/rclone-linux.zip" '*/rclone' -d "$work"
cp "$work"/rclone-*/rclone "$work/rclone"
chmod 700 "$work/rclone"
export RCLONE_CONFIG_SKYSHARE_TYPE=webdav
export RCLONE_CONFIG_SKYSHARE_URL='https://striking-rebecka-wxj3837-0de393a2.koyeb.app/alist/dav/'
export RCLONE_CONFIG_SKYSHARE_VENDOR=other
export RCLONE_CONFIG_SKYSHARE_USER="$SHARED_ALIST_USERNAME"
export RCLONE_CONFIG_SKYSHARE_PASS="$("$work/rclone" obscure "$SHARED_ALIST_PASSWORD")"
"$work/rclone" lsd skyshare: --max-depth 1 --timeout 30s >/dev/null
if ! mountpoint -q "$mount"; then
    "$work/rclone" mount skyshare: "$mount" --daemon --daemon-timeout 30s --vfs-cache-mode writes --log-file "$work/rclone.log"
fi
mountpoint -q "$mount"
echo 'Shared AList drive mounted on Linux desktop.'
