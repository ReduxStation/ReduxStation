#!/bin/bash
# TGS PreStartup event script.
#
# Symlinks the active game directory's `data/` to the persistent
# /tgstation/data mount so EVERY game-state file (player_saves,
# npc_saves, spritesheets, photo albums, mode.txt, logs, etc.)
# survives across deploys.
#
# Each TGS deploy creates a fresh Game/<uuid>/ directory and points
# Live at it. Without this symlink, anything the game writes under
# data/ - including character saves - lives in the per-deploy
# directory and is lost the next time TGS hot-swaps. (Earlier
# revisions of this script only symlinked data/logs, which left
# player_saves and friends ephemeral.)
#
# Idempotent across redeploys: if the symlink already points at the
# right place, refresh it. If TGS just created data/ as a real
# directory, merge its contents into the persistent mount (preserving
# whatever's already there with newer timestamps wins) and then
# replace it with the symlink.
#
# $1 = game directory (the freshly-deployed Game/<uuid>/ that the
# watchdog will launch from). May be empty on some TGS versions;
# fall back to the Live symlink under the canonical instance path.
set -euo pipefail

PERSIST=/tgstation/data
GAME_DIR="${1:-/tgs_instances/ResurgenceStation/Game/Live}"
DATA_DIR="$GAME_DIR/data"
SERVERINFO="$PERSIST/serverinfo.json"

mkdir -p "$PERSIST/logs"

# Seed the public-log-parser's ongoing-round file if absent. The
# RoundStart / RoundEnd event scripts overwrite this with the live
# value during play; this block just makes sure the parser's first
# fetch succeeds on a brand new deploy (where the file would not
# exist yet) so it does not fall back to blocking every round.
if [ ! -f "$SERVERINFO" ]; then
  echo '{"servers":[]}' > "$SERVERINFO"
fi

# Make sure the parent of $DATA_DIR (Game/<uuid>/) exists. TGS creates
# it before invoking PreStartup, but on a brand-new instance where the
# script runs before any deploy has populated Game/, $GAME_DIR may not
# exist yet. Bail out cleanly in that case - nothing to symlink.
if [ ! -d "$GAME_DIR" ]; then
  echo "PreStartup: $GAME_DIR does not exist yet; skipping symlink."
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
    echo "PreStartup: rsync not found, falling back to cp -an (older files win on conflict)." >&2
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
