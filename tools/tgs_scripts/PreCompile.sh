#!/bin/bash
# TGS PreCompile event script.
# $1 = staging game directory (TGS will promote this to Live after compile).
#
# Mirrors the upstream tgstation deployment model: one script, runs at deploy
# time, sets up everything DreamDaemon needs and exits. No PostCompile.sh,
# no DreamDaemonPreLaunch.sh, no RoundStart/RoundEnd.sh. TGS's own GameStaticFiles
# feature handles persistent data linking; the only thing left for a script to
# do is rename the committed librust_g.so binary to the BYOND-discoverable name.
set -euo pipefail

GAME_DIR="$1"

# ── Native libraries ─────────────────────────────────────────────────────────
# librust_g.so is committed to the repo root as `rust_g` (no .so extension)
# from when the fork's native-lib pipeline was hand-rolled. BYOND's call_ext()
# on Linux resolves "rust_g" via dlopen, which expects either `librust_g.so`
# on LD_LIBRARY_PATH/ldconfig OR the bare name in CWD. The simplest deploy is
# to make a `librust_g.so` available in the game directory itself.
#
# libBSQL.so and libquickwrite.so are committed with the correct names already
# so they need no renaming.
if [ -f "$GAME_DIR/rust_g" ]; then
    cp -f "$GAME_DIR/rust_g" "$GAME_DIR/librust_g.so"
    chmod +x "$GAME_DIR/librust_g.so"
fi

# ── Persistent data ──────────────────────────────────────────────────────────
# The game writes player_saves, spritesheets, mode.txt, photo_albums etc. into
# the relative `data/` directory under its CWD. TGS recreates the game dir
# fresh on every deploy, so any `data/` in the source tree gets wiped. We
# symlink `$GAME_DIR/data` to the persistent docker volume mount at
# /tgstation/data so the writes survive across deploys.
#
# This is the one TGS-native-feature alternative we're not using: TGS6's
# GameStaticFiles could handle this, but it requires the operator to manually
# link Configuration/GameStaticFiles/data -> /tgstation/data on first setup.
# Doing it in this script is one less manual step and works the same way.
PERSIST=/tgstation/data
DATA_DIR="$GAME_DIR/data"
mkdir -p "$PERSIST"
if [ -d "$DATA_DIR" ] && [ ! -L "$DATA_DIR" ]; then
    # The source tree shipped a real `data/` directory (gitignored content
    # placeholder); replace it with the symlink.
    rm -rf "$DATA_DIR"
fi
ln -sfn "$PERSIST" "$DATA_DIR"
