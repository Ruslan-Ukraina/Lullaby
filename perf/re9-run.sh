#!/bin/sh
# One RE9 measurement (non-Steam shortcut 4022369388): launch, wait, sample, full-screen shot, quit.
#   perf/re9-run.sh LABEL [SETTLE_SECONDS] [SAMPLE_SECONDS]
# config.ini edits are the caller's (perf/re9-config.sh); the game must not run.
set -u
label=$1; settle=${2:-60}; sample=${3:-20}
here=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$here/../scratch/perf}; mkdir -p "$OUT"
C="$HOME/Library/Application Support/Steam/steamapps/compatdata/4022369388"
W="$HOME/Library/Application Support/lullaby/launchers/app-4022369388/lullaby-wine.log"
t0=$(date +%s); open "steam://rungameid/17275944973925089280"
i=0; while [ $i -lt 180 ]; do i=$((i+1)); [ -f "$W" ] && [ "$(stat -f %m "$W")" -ge "$t0" ] && grep -aq 'first present' "$W" && break; sleep 1; done
echo "$label: first frame after $i s; settling $settle s"
sleep "$settle"
python3 -I "$here/frames.py" "$C" --seconds "$sample" --label "$label" --csv "$OUT/re9.csv"
screencapture -x "$OUT/$label.png"; sips -Z 1200 "$OUT/$label.png" --out "$OUT/$label-s.png" > /dev/null
osascript -e 'tell application id "com.ruslanukraina.lullaby.launcher.4022369388" to quit' > /dev/null 2>&1
i=0; while [ $i -lt 90 ]; do i=$((i+1)); tail -3 "$C/lullaby-run.log" | grep -q 'session ending' && break; sleep 1; done
echo "$label: ended after $i s"; sleep 12
