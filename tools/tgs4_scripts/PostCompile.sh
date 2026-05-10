#!/bin/bash
# TGS PostCompile event script — called after DM compilation succeeds.
# $1 = directory containing the freshly-compiled game files.
#
# BYOND's call_ext() resolution on Linux is finicky: it checks the game
# working directory under several name variants (bare, .so, lib- prefix),
# falls back to LD_LIBRARY_PATH and the ldconfig cache, and fails closed
# with a confusing "libbyond.so: undefined symbol: <fn>" runtime error if
# none of the expected paths satisfy. We scatter every native lib to
# every location BYOND has historically searched (game dir, BYOND bin
# dir, /usr/local/lib, /usr/lib/i386-linux-gnu) so call_ext succeeds
# regardless of which path BYOND tries first.
set -euo pipefail

GAME_DIR="$1"

# Locate the active BYOND install dir under the TGS instance volume so we
# can scatter alongside DreamDaemon. The path includes the version number
# (e.g. /tgs_instances/ResurgenceStation/Byond/516.1680/byond/bin).
BYOND_BIN=""
if [ -f "/tgs_instances/ResurgenceStation/Byond/ActiveVersion.txt" ]; then
    ACTIVE_VERSION=$(cat /tgs_instances/ResurgenceStation/Byond/ActiveVersion.txt)
    CANDIDATE="/tgs_instances/ResurgenceStation/Byond/$ACTIVE_VERSION/byond/bin"
    [ -d "$CANDIDATE" ] && BYOND_BIN="$CANDIDATE"
fi

scatter() {
    # scatter <source> <basename without prefix or extension>
    local SRC="$1"
    local BASE="$2"
    local DEST
    local DESTS=(
        "$GAME_DIR/$BASE"
        "$GAME_DIR/$BASE.so"
        "$GAME_DIR/lib$BASE.so"
        "/usr/local/lib/$BASE.so"
        "/usr/local/lib/lib$BASE.so"
        "/usr/lib/i386-linux-gnu/$BASE.so"
        "/usr/lib/i386-linux-gnu/lib$BASE.so"
    )
    if [ -n "$BYOND_BIN" ]; then
        DESTS+=(
            "$BYOND_BIN/$BASE"
            "$BYOND_BIN/$BASE.so"
            "$BYOND_BIN/lib$BASE.so"
        )
    fi
    for DEST in "${DESTS[@]}"; do
        # Skip when source and destination are the same file (cp errors otherwise).
        if [ "$(readlink -f "$SRC")" = "$(readlink -f "$DEST" 2>/dev/null || echo "")" ]; then
            continue
        fi
        mkdir -p "$(dirname "$DEST")"
        # ATOMIC REPLACE, not in-place truncate.
        #
        # The active DreamDaemon process has these .so files mmap'd into its
        # address space. Plain `cp -f $SRC $DEST` opens $DEST with O_TRUNC and
        # rewrites the bytes in place — the kernel reuses the same inode, so
        # the running process's mmap'd pages now point at half-written content.
        # Next time DD page-faults on a code page (e.g. the next call into
        # rust_g), it reads garbage and segfaults with BYOND printing
        # "BUG: Crashing due to an illegal operation!".
        #
        # Copy to a sibling tempfile, then `mv` to atomically swap inodes.
        # The old inode stays alive for any process that already had it open;
        # new opens see the new file. No corrupted code pages.
        cp -f "$SRC" "$DEST.tmp.$$"
        mv -f "$DEST.tmp.$$" "$DEST"
    done
}

scatter "$GAME_DIR/rust_g"           rust_g
scatter "$GAME_DIR/libBSQL.so"       BSQL
scatter "$GAME_DIR/libquickwrite.so" quickwrite

# Refresh the ldconfig cache so dlopen-by-soname (librust_g.so etc.) finds
# the freshly scattered files in /usr/local/lib and /usr/lib/i386-linux-gnu.
ldconfig

# ── Symlink the staging deployment's data/ to the persistent mount ───────────
# TGS6 promotes the staging uuid dir to Live during a hot-swap (round-end
# soft-restart). The promotion does NOT fire DreamDaemonPreLaunch, so any
# data-dir setup that script does only takes effect on watchdog cold starts.
# To make persistence survive hot-swaps, we set up the symlink HERE on the
# staging uuid - whichever swap mechanism TGS uses (rename/symlink/copy),
# Live/data ends up pointing at /tgstation/data the moment the hot-swap
# completes.
#
# Trade-off: TGS may launch its API-validation DreamDaemon (port 1339) AFTER
# PostCompile returns, with the staging uuid as cwd. With this symlink in
# place, that validation DD's transient `data/logs/config_error.{<guid>}.log`
# lands in /tgstation/data/logs/. DreamDaemonPreLaunch.sh's sweep cleans
# those on every cold start, and we mirror the sweep here to keep the
# persistent volume tidy on hot-swap-only paths where DreamDaemonPreLaunch
# does not run.
PERSIST=/tgstation/data
DATA_DIR="$GAME_DIR/data"
mkdir -p "$PERSIST/logs"
if [ -L "$DATA_DIR" ]; then
    ln -sfn "$PERSIST" "$DATA_DIR"
elif [ -d "$DATA_DIR" ]; then
    # Real dir from the deployed source tree (data/ is gitignored so it
    # should be empty, but be safe and merge anything in there forward
    # before replacing it). Skip data/logs to avoid copying a self-loop
    # if a previous PreLaunch already symlinked it.
    if command -v rsync >/dev/null 2>&1; then
        rsync -au --exclude=logs "$DATA_DIR/" "$PERSIST/" 2>/dev/null || true
    else
        for entry in "$DATA_DIR"/* "$DATA_DIR"/.[!.]*; do
            [ -e "$entry" ] || continue
            [ "$(basename "$entry")" = "logs" ] && continue
            cp -an "$entry" "$PERSIST/" 2>/dev/null || true
        done
    fi
    rm -rf "$DATA_DIR"
    ln -sfn "$PERSIST" "$DATA_DIR"
else
    ln -sfn "$PERSIST" "$DATA_DIR"
fi

# Sweep any leftover validation-DD config_error.{<guid>}.log files from
# previous deploys that escaped the persistent volume root before we
# fixed the merge logic. Mirrors the same defensive sweep in
# DreamDaemonPreLaunch.sh so hot-swap-only deploy chains do not let
# them accumulate.
find "$PERSIST/logs" -maxdepth 1 -type f -name 'config_error.{*}.log' -delete 2>/dev/null || true

# ── Self-install sibling event scripts ───────────────────────────────────────
# Every TGS deploy hot-swaps a fresh copy of the source tree into the game
# directory. Use that to keep Configuration/EventScripts/ in lockstep with
# tools/tgs4_scripts/ in the repo: copy each sibling script into the
# instance's EventScripts dir, KEEPING the .sh extension.
#
# TGS6 only enumerates event scripts whose filename matches `<EventName>*.<ext>`
# where `<ext>` is `.sh` on Linux / `.bat` on Windows. See:
#   https://github.com/tgstation/tgstation-server/blob/master/src/Tgstation.Server.Host/System/PlatformIdentifier.cs
# An earlier revision of this loop dropped the .sh, which made the auto-installed
# siblings invisible to TGS even though PostCompile was running. Preserving the
# extension is what actually makes the chain work.
#
# Without this self-install, every change to one of the sibling scripts requires
# a manual `docker cp` into the instance volume. With it, an update merged to
# master takes effect on the next deploy automatically (with a one-deploy lag
# for PostCompile itself, since the currently running PostCompile installs the
# new one).
EVENT_DST="$(dirname "$(dirname "$GAME_DIR")")/Configuration/EventScripts"
if [ -d "$EVENT_DST" ]; then
    for SCRIPT in PostCompile DreamDaemonPreLaunch RoundStart RoundEnd; do
        SRC="$GAME_DIR/tools/tgs4_scripts/$SCRIPT.sh"
        if [ -f "$SRC" ]; then
            cp -f "$SRC" "$EVENT_DST/$SCRIPT.sh"
            chmod +x "$EVENT_DST/$SCRIPT.sh"
        fi
    done
fi
