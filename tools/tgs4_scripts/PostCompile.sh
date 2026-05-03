#!/bin/bash
# TGS PostCompile event script — called after DM compilation succeeds.
# $1 = directory containing the freshly-compiled game files.
set -euo pipefail

GAME_DIR="$1"

# rust_g — dlopen("rust_g") searches LD_LIBRARY_PATH and the ldconfig cache,
# NOT the game directory, so we scatter it to /usr/local/lib.
cp "$GAME_DIR/rust_g" /usr/local/lib/rust_g.so
cp "$GAME_DIR/rust_g" /usr/local/lib/librust_g.so

# BSQL and quickwrite — same deal.
cp "$GAME_DIR/libBSQL.so"       /usr/local/lib/libBSQL.so
cp "$GAME_DIR/libquickwrite.so" /usr/local/lib/libquickwrite.so

ldconfig

# BYOND also tries plain names without the lib prefix in the game directory.
cp "$GAME_DIR/libBSQL.so"       "$GAME_DIR/BSQL.so"
cp "$GAME_DIR/libBSQL.so"       "$GAME_DIR/BSQL"
cp "$GAME_DIR/libquickwrite.so" "$GAME_DIR/quickwrite.so"
