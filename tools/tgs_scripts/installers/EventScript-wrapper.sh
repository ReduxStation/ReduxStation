#!/bin/bash
# TGS-6 EventScripts wrapper.
#
# Install this file once at /tgs_instances/<instance>/Configuration/EventScripts/<EventName>.sh
# via the TGS panel (Files & Scripts -> create/replace -> paste this content).
# Use the SAME content for every event script you want auto-updating from the
# repo (RoundStart.sh, RoundEnd.sh, etc.). The wrapper detects its own filename
# and forwards to the matching real script in the deployed game directory.
#
# TGS6 invokes event scripts as:  <script> <game_dir> <param1> <param2> ...
# So $1 is always the game directory; $0 is this wrapper's path.
#
# After install, this wrapper never needs updating. The real logic lives in
# the repo at tools/tgs_scripts/<EventName>.sh and is auto-deployed by every
# TGS compile into <game_dir>/tools/tgs_scripts/. The wrapper just forwards.

set -euo pipefail

GAME_DIR="$1"
EVENT_NAME="$(basename "$0" .sh)"
REAL_SCRIPT="$GAME_DIR/tools/tgs_scripts/${EVENT_NAME}.sh"

if [ -x "$REAL_SCRIPT" ]; then
    exec "$REAL_SCRIPT" "$@"
elif [ -f "$REAL_SCRIPT" ]; then
    exec bash "$REAL_SCRIPT" "$@"
else
    # The real script doesn't exist in this deploy. Probably means the repo
    # was checked out at a revision that doesn't have that event handler.
    # Don't fail the deploy — just no-op and log to stderr.
    echo "EventScript wrapper [${EVENT_NAME}]: real script not found at ${REAL_SCRIPT}" >&2
    exit 0
fi
