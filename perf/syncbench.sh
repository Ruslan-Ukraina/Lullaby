#!/bin/sh
# Thread-waiting benchmark (perf/syncbench.c) under one engine, in several sync modes, in a
# throw-away prefix. Rounds go mode by mode, round after round, so heat and background
# load hit every mode alike. One CSV row per case, round and mode.
#
#   perf/syncbench.sh [--engine-env FILE] [--runs N] [--mode LABEL:VAR=v,VAR=v]... [--out CSV]
#                     [--wait-quiet PERCENT]
#
#   --engine-env  a lullaby-engine.env (see perf/common.sh); default: the installed engine
#   --runs        rounds per mode, default 3
#   --mode        a label and the environment of that mode; the default pair is
#                 "server:" (the wineserver does the waiting) and "msync:WINEMSYNC=1".
#                 WineForge: "wfusync:WINEWFUSYNC=1".
#   --out         CSV to append to, default scratch/perf/syncbench.csv
#   --wait-quiet  wait (up to 10 minutes) until at least PERCENT of the processors are idle (this Mac idles at 80 % with nothing of ours running)
#
# Round 0 of each mode is a warm-up: it is written to the CSV (round 0) and report.py leaves
# it out. Refuses to run while a Wine server is alive: a game or a session would make the
# numbers mean nothing. Needs mingw-w64.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
# shellcheck source=perf/common.sh
. "$here/common.sh"

envfile=""
runs=3
out=$root/scratch/perf/syncbench.csv
modes=""
quiet=""

while [ $# -gt 0 ]; do
  case $1 in
    --engine-env) envfile=$2; shift 2 ;;
    --runs) runs=$2; shift 2 ;;
    --mode) modes="$modes
$2"; shift 2 ;;
    --out) out=$2; shift 2 ;;
    --wait-quiet) quiet=$2; shift 2 ;;
    *) echo "syncbench: unknown option $1" >&2; exit 2 ;;
  esac
done
[ -n "$modes" ] || modes="
server:
msync:WINEMSYNC=1"

perf_engine_load "$envfile"
perf_require_no_wine
[ -z "$quiet" ] || perf_wait_quiet "$quiet"
perf_note_machine
echo "==> syncbench: engine $perf_engine, $runs rounds"
[ "${perf_idle:-0}" -ge 10 ] 2> /dev/null || echo "    (the Mac is in use: expect noise; the spread between rounds says how much)"

trap perf_cleanup EXIT INT TERM
perf_prefix_init
x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -Wno-unused-parameter -o "$perf_tmp/syncbench.exe" "$here/syncbench.c" -static-libgcc

mkdir -p "$(dirname "$out")"
[ -s "$out" ] || echo "engine,mode,round,case,ops_per_s,p50_us,p99_us,p999_us,n,idle_s,load" > "$out"

round=0
while [ "$round" -le "$runs" ]; do
  echo "$modes" | while IFS= read -r spec; do
    [ -n "$spec" ] || continue
    label=${spec%%:*}
    vars=${spec#*:}
    perf_stop_server
    spaced=$(printf '%s' "$vars" | tr ',' ' ')
    (
      # shellcheck disable=SC2086 # the mode's VAR=value pairs, one word each, by design
      env $spaced "$perf_wine" "$perf_tmp/syncbench.exe" 2> "$perf_tmp/stderr.txt" | tr -d '\r' | while IFS= read -r line; do
        case $line in
          *,*) echo "$perf_engine,$label,$round,$line,${perf_idle:-},${perf_load:-}" >> "$out" ;;
        esac
      done
    ) || echo "syncbench: round $round, mode $label failed" >&2
    if [ "$round" -eq 0 ]; then echo "    warm-up, $label: done"; else echo "    round $round, $label: done"; fi
  done
  round=$((round + 1))
done
perf_stop_server
echo "==> rows appended to $out"
