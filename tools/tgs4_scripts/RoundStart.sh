#!/bin/bash
# TGS event script invoked when the game emits TgsTriggerEvent("RoundStart", ...)
# from code/controllers/subsystem/dbcore.dm::SetRoundID after the round_id is
# assigned by the database.
#
# Writes the active round id into a serverinfo.json file on the game_data
# volume. The public-log-parser polls this file via caddy:8081/serverinfo.json
# every 60 seconds and 404s any /YYYY/MM/DD/round-N/ path whose round_id is
# in the list, so the in-progress round stays hidden from logs.owo.fm.
#
# $1 = round_id as a string.
set -euo pipefail

ROUND_ID="${1:-}"
if [ -z "$ROUND_ID" ]; then
  echo "RoundStart: no round_id passed in arg 1, doing nothing" >&2
  exit 0
fi

OUT=/tgstation/data/serverinfo.json
mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<JSON
{"servers":[{"data":{"round_id":"${ROUND_ID}","identifier":"owo"}}]}
JSON
echo "RoundStart: wrote round_id ${ROUND_ID} to ${OUT}"
