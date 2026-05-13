#!/bin/bash
# TGS PreCompile event script.
# $1 = staging game directory (TGS promotes this to Live after compile).
#
# Mirrors the upstream tgstation deployment shape: a single PreCompile script
# that sets up everything DreamDaemon needs on every deploy. Replaces the
# fork-imported PostCompile.sh (scatter, validation sweep, self-install loop)
# and DreamDaemonPreLaunch.sh (data symlink). RoundStart.sh and RoundEnd.sh
# are kept as proper TGS-6 event scripts — they fire on world.TgsTriggerEvent
# calls from DM and integrate with the public log parser via serverinfo.json.
set -euo pipefail

GAME_DIR="$1"

# ── Native libraries ─────────────────────────────────────────────────────────
# librust_g.so is committed to the repo root as `rust_g` (no .so extension)
# from the original fork import. BYOND's call_ext() on Linux resolves "rust_g"
# via dlopen, which expects either librust_g.so on LD_LIBRARY_PATH/ldconfig
# OR the bare name in CWD. We rename to librust_g.so in the game directory so
# either resolution path works without extra scatter to system lib dirs.
#
# libBSQL.so and libquickwrite.so are already committed with the correct names.
if [ -f "$GAME_DIR/rust_g" ]; then
    cp -f "$GAME_DIR/rust_g" "$GAME_DIR/librust_g.so"
    chmod +x "$GAME_DIR/librust_g.so"
fi

# ── Persistent data symlink ──────────────────────────────────────────────────
# The game writes player_saves, spritesheets, mode.txt, photo_albums, etc. to
# the relative `data/` directory under its CWD. TGS recreates the game dir
# fresh on every deploy, so a real data/ in the source tree gets wiped. We
# symlink $GAME_DIR/data → the persistent docker volume mount at /tgstation/data
# so the writes survive across deploys.
#
# The RoundStart.sh / RoundEnd.sh event scripts in this directory also write
# data/serverinfo.json (relative to the game dir, so through this symlink to
# /tgstation/data/serverinfo.json), which Caddy serves to the public log parser.
PERSIST=/tgstation/data
DATA_DIR="$GAME_DIR/data"
mkdir -p "$PERSIST"
if [ -d "$DATA_DIR" ] && [ ! -L "$DATA_DIR" ]; then
    # The source tree shipped a real `data/` directory (gitignored content
    # placeholder); replace it with the symlink so writes land in /tgstation/data.
    rm -rf "$DATA_DIR"
fi
ln -sfn "$PERSIST" "$DATA_DIR"
