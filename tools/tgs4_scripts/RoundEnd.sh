#!/bin/bash
# TGS event script invoked when the game emits TgsTriggerEvent("RoundEnd", ...)
# from code/controllers/subsystem/dbcore.dm::SetRoundEnd after the round's
# end_datetime is recorded.
#
# Clears the active-round list in serverinfo.json so the public-log-parser
# stops hiding this round's directory at logs.owo.fm.
#
# TGS6 invokes custom event scripts as:
#   <script> <game_dir> <param1> <param2> ...
# DMAPI call: world.TgsTriggerEvent("RoundEnd", list("[GLOB.round_id]")) so:
#   $1 = game directory (unused here)
#   $2 = round_id as a string (informational only; we always clear)
set -euo pipefail

OUT=/tgstation/data/serverinfo.json
mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<'JSON'
{"servers":[]}
JSON
echo "RoundEnd: cleared ${OUT} (round ${2:-unknown} ended)"
