#!/bin/bash
# TGS PreStartup event script.
# Symlinks the active game's data/logs into the persistent /tgstation/data/logs
# mount so logs.owo.fm (which Caddy serves from that volume) sees rounds the
# TGS-managed game writes.
#
# Idempotent across redeploys: if the symlink already points at the right place,
# do nothing. If it's a real directory (TGS just created a fresh Game/<uuid>),
# move any existing content into the persistent dir before replacing.
#
# $1 = game directory (the freshly-deployed Game/<uuid>/ that the watchdog will
# launch from). May be empty on some TGS versions; fall back to the Live
# symlink under the canonical instance path.
set -euo pipefail

PERSIST=/tgstation/data/logs
GAME_DIR="${1:-/tgs_instances/ResurgenceStation/Game/Live}"
LOGS="$GAME_DIR/data/logs"

mkdir -p "$PERSIST"
mkdir -p "$(dirname "$LOGS")"

if [ -L "$LOGS" ]; then
  ln -sfn "$PERSIST" "$LOGS"
elif [ -d "$LOGS" ]; then
  cp -an "$LOGS"/. "$PERSIST"/ 2>/dev/null || true
  rm -rf "$LOGS"
  ln -sfn "$PERSIST" "$LOGS"
else
  ln -sfn "$PERSIST" "$LOGS"
fi
