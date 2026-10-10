#!/bin/sh
# PEAK at a lowered resolution through fullscreen -> windowed -> fullscreen (Alt+Enter):
# what it renders at each step (frame rate, window shot) and what it saves.
#   perf/peak-toggle.sh LABEL MODE WIDTH HEIGHT EMULATE(true|false)
set -u
label=$1; mode=$2; w=$3; h=$4; emu=$5
here=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$here/../scratch/perf}; mkdir -p "$OUT"
C="$HOME/Library/Application Support/Steam/steamapps/compatdata/3527290"
W="$HOME/Library/Application Support/lullaby/launchers/app-3527290/lullaby-wine.log"
CLI="$HOME/Library/Application Support/lullaby/lullaby-settings"
"$CLI" set --app 3527290 emulateModeset "$emu" > /dev/null
"$here/peak-screen.sh" "$mode" "$w" "$h" > /dev/null
reg() { grep -a 'Fullscreen mode_h3630\|Resolution Width_h18\|Resolution Height_h26' "$C/pfx/user.reg" | sed 's/"Screenmanager //; s/_h[0-9]*"=dword:/=/' | tr '\n' ' '; }
step() { sleep 6; python3 -I "$here/frames.py" "$C" --seconds 4 --label "$label-$1" | sed -n 's/.*\(fps=[^ ]*\).*\(p50_ms=[^ ]*\).*/\1 \2/p' | sed "s/^/$label $1: /"
	screencapture -x "$OUT/$label-$1.png"; sips -Z 700 "$OUT/$label-$1.png" --out "$OUT/$label-$1-s.png" > /dev/null; }
t0=$(date +%s); open steam://rungameid/3527290
i=0; while [ $i -lt 90 ]; do i=$((i+1)); [ -f "$W" ] && [ "$(stat -f %m "$W")" -ge "$t0" ] && grep -aq 'first present' "$W" && break; sleep 1; done
sleep 30
step 1-start
osascript -e 'tell application "System Events" to key code 36 using option down'; step 2-toggled
osascript -e 'tell application "System Events" to key code 36 using option down'; step 3-back
osascript -e 'tell application id "com.ruslanukraina.lullaby.launcher.3527290" to quit'
i=0; while [ $i -lt 60 ]; do i=$((i+1)); tail -3 "$C/lullaby-run.log" | grep -q 'session ending' && break; sleep 1; done
echo "$label saved: $(reg)"; sleep 12
