#!/usr/bin/env bash
# Walk logs.owo.fm, pull every recent round's runtime.log + game.log,
# collapse into deduplicated signatures, and print a frequency-sorted
# table so we know which BYOND runtimes are still uncovered.
#
# Why HTTPS and not docker/SSH:
#   The auth boundary already exists. Caddy + the public-log-parser
#   serve runtime.log over HTTPS with IP/CID scrubbing applied, the
#   per-round directory tree is browsable as plain HTML, and we don't
#   need a docker/host coupling to read the data. This script runs
#   from any machine that can reach logs.owo.fm.
#
# Usage:
#
#   ./tools/audit-runtimes.sh                 # last 7 days, top 0 (all signatures)
#   ./tools/audit-runtimes.sh --days 30       # widen the window
#   ./tools/audit-runtimes.sh --top 20        # truncate to top 20 signatures
#   ./tools/audit-runtimes.sh --raw           # dump every runtime line, no aggregation
#   ./tools/audit-runtimes.sh --base URL      # override base (default https://logs.owo.fm)
#   ./tools/audit-runtimes.sh --grep AUDIT    # only signatures whose message contains AUDIT
#
# Notes:
#   * `runtime.log` is in the public-log-parser's allowlist, so it is
#     served. Other log filenames (sql.log, hrefs.log) 404 by design;
#     the script ignores them.
#   * In-progress rounds are 404'd by the parser via serverinfo.json
#     until RoundEnd fires. The script reports their absence as zero
#     hits, not as an error.

set -euo pipefail

DAYS=7
TOP=0
RAW=0
BASE="https://logs.owo.fm"
MSG_GREP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days)  DAYS="$2"; shift 2;;
    --top)   TOP="$2"; shift 2;;
    --raw)   RAW=1; shift;;
    --base)  BASE="$2"; shift 2;;
    --grep)  MSG_GREP="$2"; shift 2;;
    -h|--help)
      sed -n '1,/^set -euo pipefail$/p' "$0" | sed 's/^# \?//'
      exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

# Caddy's file_server browse renders HTML directory listings. We pull
# subdirectory links via the './FOO/' href pattern. file requests under
# round-N go through the parser; directory requests at /YYYY/MM/DD
# level go through Caddy's browse UI. Both render as HTML with the
# same href shape.
list_subdirs() {
  local url="$1"
  curl -fsS "$url" 2>/dev/null \
    | grep -oE 'href="\./[^"]+/"' \
    | sed -E 's|^href="\./||; s|/"$||'
}

# Cutoff: anything older than $DAYS days ago skipped.
CUTOFF=$(date -u -d "$DAYS days ago" +%Y-%m-%d 2>/dev/null \
       || date -u -v-"${DAYS}"d +%Y-%m-%d)

echo "Walking $BASE for runtime.log files newer than $CUTOFF..." >&2

# Walk the year/month/day/round-N tree, accumulating runtime.log URLs.
ROUND_LOGS=()
for year in $(list_subdirs "$BASE/"); do
  [[ "$year" =~ ^[0-9]{4}$ ]] || continue
  for month in $(list_subdirs "$BASE/$year/"); do
    [[ "$month" =~ ^[0-9]{2}$ ]] || continue
    for day in $(list_subdirs "$BASE/$year/$month/"); do
      [[ "$day" =~ ^[0-9]{2}$ ]] || continue
      DAY_DATE="$year-$month-$day"
      if [[ "$DAY_DATE" < "$CUTOFF" ]]; then
        continue
      fi
      for round in $(list_subdirs "$BASE/$year/$month/$day/"); do
        [[ "$round" =~ ^round-[0-9]+$ ]] || continue
        ROUND_LOGS+=("$BASE/$year/$month/$day/$round")
      done
    done
  done
done

if [[ ${#ROUND_LOGS[@]} -eq 0 ]]; then
  cat <<EOF
No round directories found at $BASE in the last $DAYS day(s).
Either no rounds have run yet, or logs.owo.fm is misconfigured.
Run a round and re-try, or hit $BASE/ in a browser to confirm Caddy
is serving the directory listing.
EOF
  exit 0
fi

echo "Found ${#ROUND_LOGS[@]} round directories. Fetching runtime.log + game.log from each..." >&2

# Pull runtime.log AND game.log from each round. game.log captures the
# AUDIT instrumentation lines (chem grenade, chem_splash). runtime.log
# captures the BYOND runtimes themselves.
RAW_DUMP=""
for ROUND_URL in "${ROUND_LOGS[@]}"; do
  ROUND_PATH="${ROUND_URL#$BASE/}"
  for LOG in runtime.log game.log; do
    BODY=$(curl -fsS "$ROUND_URL/$LOG" 2>/dev/null || true)
    if [[ -n "$BODY" ]]; then
      # Tag every line with its origin so we can show first/last seen.
      RAW_DUMP+=$(printf '%s\n' "$BODY" | sed "s|^|$ROUND_PATH\t$LOG\t|")
      RAW_DUMP+=$'\n'
    fi
  done
done

if [[ -z "$RAW_DUMP" ]]; then
  echo "No runtime.log or game.log content returned. The parser may be 404ing all rounds (in-progress lock?), or the rounds had no errors."
  exit 0
fi

if [[ "$RAW" == "1" ]]; then
  printf '%s' "$RAW_DUMP"
  exit 0
fi

# Aggregate. A runtime.log block looks like:
#   "runtime error: <message>"
#   "  proc name: <proc>"
#   "  source file: <file>,<line>"
#
# AUDIT instrumentation lines look like:
#   "AUDIT chem_grenade/prime: ..."
# These appear in game.log; we collapse them by their first 80 chars
# of message after the AUDIT prefix.
#
# Output TSV: count, first-seen path, source file, proc, message.

printf '%s' "$RAW_DUMP" | awk -F '\t' '
  $3 ~ /AUDIT/ {
    msg = $3
    sub(/^.*AUDIT[[:space:]]*/, "AUDIT ", msg)
    if (length(msg) > 100) { msg = substr(msg, 1, 97) "..." }
    sig = "AUDIT" "\t" msg
    count[sig]++
    if (!(sig in first_path)) first_path[sig] = $1
    last_path[sig] = $1
    next
  }
  /runtime error:/ {
    msg = $3
    sub(/^.*runtime error:[[:space:]]*/, "", msg)
    if (length(msg) > 100) { msg = substr(msg, 1, 97) "..." }
    cur_msg = msg
    cur_path = $1
    next
  }
  /proc name:/ {
    sub(/^.*proc name:[[:space:]]*/, "", $3)
    cur_proc = $3
    next
  }
  /source file:/ {
    sub(/^.*source file:[[:space:]]*/, "", $3)
    cur_src = $3
    if (cur_src != "" && cur_proc != "" && cur_msg != "") {
      sig = cur_src "\t" cur_proc "\t" cur_msg
      count[sig]++
      if (!(sig in first_path)) first_path[sig] = cur_path
      last_path[sig] = cur_path
    }
    cur_msg=""; cur_proc=""; cur_src=""
    next
  }
  END {
    for (sig in count) {
      printf "%d\t%s\t%s\n", count[sig], first_path[sig], sig
    }
  }
' | (
  if [[ -n "$MSG_GREP" ]]; then
    grep -- "$MSG_GREP"
  else
    cat
  fi
) | sort -k1,1 -nr -t$'\t' | (
  if [[ "$TOP" -gt 0 ]]; then
    head -n "$TOP"
  else
    cat
  fi
) | awk -F '\t' 'BEGIN {
  printf "%-5s  %-40s  %-50s  %s\n", "COUNT", "FIRST SEEN (round)", "PROC + SOURCE", "MESSAGE"
  printf "%-5s  %-40s  %-50s  %s\n", "-----", "----------------------------------------", "--------------------------------------------------", "-------"
}
{
  count = $1; path = $2
  if ($3 == "AUDIT") {
    proc_src = "(audit instrumentation)"
    msg = $4
  } else {
    proc_src = $4 " (" $3 ")"
    msg = $5
  }
  printf "%-5s  %-40s  %-50s  %s\n", count, path, proc_src, msg
}'

echo "" >&2
echo "Window: last $DAYS day(s). Source: $BASE." >&2
echo "Re-run with --days N to widen, --top N to truncate, --grep STR to filter, --raw to dump everything." >&2
