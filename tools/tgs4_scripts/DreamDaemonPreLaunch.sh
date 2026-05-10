#!/bin/bash
# TGS DreamDaemonPreLaunch event script.
#
# Fires immediately before tgstation-server launches the game's
# DreamDaemon process for production play. Per the TGS6 EventType
# enum (https://github.com/tgstation/tgstation-server/blob/master/
# src/Tgstation.Server.Host/Components/Events/EventType.cs), this
# event takes NO arguments - the script must derive the launch
# directory itself.
#
# What this script does: ensure the active game directory's `data/`
# is a symlink to the persistent /tgstation/data mount. Every TGS
# deploy creates a fresh Game/<uuid>/ with its own ephemeral data/
# subdir; without this symlink, every player_save, npc_save,
# spritesheet, mode.txt, and log file the game writes dies on the
# next compile + hot-swap.
#
# Caddy serves logs.owo.fm from the same /tgstation/data volume
# (read-only mount at /srv/logs/), so getting this symlink right
# also fixes "logs.owo.fm 404 even though the game is writing logs"
# - the issues are the same bug.
#
# This script was previously named "PreStartup" matching the TGS3/4
# event by that name. TGS6 dropped that event; the equivalent slot
# is DreamDaemonPreLaunch. Renaming let the script actually run.
#
# Idempotent across redeploys: if the symlink already points at the
# right place, refresh it. If TGS just created data/ as a real
# directory (typical right after a hot-swap), merge its contents
# into the persistent mount (rsync -au newer-wins, falling back to
# cp -an if rsync is unavailable) and then replace it with the symlink.
set -euo pipefail

PERSIST=/tgstation/data
# DreamDaemonPreLaunch has no arguments. Live is always the directory
# DreamDaemon launches from for production play on this instance.
GAME_DIR=/tgs_instances/ResurgenceStation/Game/Live
DATA_DIR="$GAME_DIR/data"
SERVERINFO="$PERSIST/serverinfo.json"

mkdir -p "$PERSIST/logs"

# Seed the public-log-parser's ongoing-round file if absent. RoundStart
# / RoundEnd event scripts overwrite this with the live value during
# play; this block just makes sure the parser's first fetch succeeds
# on a brand new deploy (where the file would not exist yet) so it
# does not fall back to blocking every round.
if [ ! -f "$SERVERINFO" ]; then
  echo '{"servers":[]}' > "$SERVERINFO"
fi

# On a brand-new instance with no deploy yet, $GAME_DIR may not exist.
# Bail cleanly - nothing to symlink, and the next deploy will hit
# this path again with the directory in place.
if [ ! -d "$GAME_DIR" ]; then
  echo "DreamDaemonPreLaunch: $GAME_DIR does not exist yet; skipping symlink."
  exit 0
fi

merge_real_dir_into_persistent() {
  # Merge the contents of an existing real $DATA_DIR into $PERSIST,
  # preserving newer files on either side. Skip data/logs because
  # it's almost always already a symlink to $PERSIST/logs and copying
  # the symlink would create a self-reference.
  local src="$1"
  if command -v rsync >/dev/null 2>&1; then
    rsync -au --exclude=logs "$src/" "$PERSIST/"
  else
    # Fall back to cp -an: never clobber, so any conflicts keep the
    # persistent (older) version. Loud about it so the operator knows
    # to install rsync if newer-wins matters for their setup.
    echo "DreamDaemonPreLaunch: rsync not found, falling back to cp -an (older files win on conflict)." >&2
    [ -L "$src/logs" ] && rm "$src/logs"
    cp -an "$src"/. "$PERSIST"/ 2>/dev/null || true
  fi
}

if [ -L "$DATA_DIR" ]; then
  # Already a symlink. Refresh in case TGS recreated the parent.
  ln -sfn "$PERSIST" "$DATA_DIR"
elif [ -d "$DATA_DIR" ]; then
  # Real dir created by TGS for this deploy. Fold its contents into
  # the persistent mount, then replace it with the symlink.
  merge_real_dir_into_persistent "$DATA_DIR"
  rm -rf "$DATA_DIR"
  ln -sfn "$PERSIST" "$DATA_DIR"
else
  # Neither exists. Just create the symlink; the game will write into
  # it on first round.
  ln -sfn "$PERSIST" "$DATA_DIR"
fi
