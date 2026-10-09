#!/bin/sh
# One PEAK measurement: renderer + Unity API, launched through Steam, sampled in the main menu.
#   perf/peak-matrix.sh LABEL RENDERER ARG [SETTLE_SECONDS] [SAMPLE_SECONDS]
# RENDERER: dxmt | dxvk | d3dmetal; ARG: -force-d3d11 | -force-d3d12 | -
# Appends to $OUT/peak.csv, saves a window shot and the Unity API line. Restores nothing:
# the caller sets the renderer back.
set -u
label=$1; renderer=$2; arg=$3; settle=${4:-45}; sample=${5:-20}
here=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$here/../scratch/perf}
mkdir -p "$OUT"
app=3527290
C="$HOME/Library/Application Support/Steam/steamapps/compatdata/$app"
W="$HOME/Library/Application Support/notproton/launchers/app-$app/notproton-wine.log"
L="$C/pfx/drive_c/users/steamuser/AppData/LocalLow/LandCrab/PEAK/Player.log"
CLI="$HOME/Library/Application Support/notproton/notproton-settings"
WINID=${WINID:-/private/tmp/claude-501/-Users-ruslanukraina-Projects-NotProton/6c7dbf3e-b527-4911-8194-ae858ee758d0/scratchpad/winid}

[ "$renderer" = keep ] || "$CLI" set --app $app renderer "\"$renderer\"" > /dev/null || exit 1
before=$(grep -c '=== notproton run' "$C/notproton-run.log"); t0=$(date +%s)
if [ "$arg" = - ]; then open "steam://rungameid/$app"; else open "steam://run/$app//$arg/"; fi
i=0; while [ $i -lt 120 ]; do i=$((i+1))
	n=$(grep -c '=== notproton run' "$C/notproton-run.log")
	[ "$n" -gt "$before" ] && [ -f "$W" ] && [ "$(stat -f %m "$W")" -ge "$t0" ] && grep -aq 'first present' "$W" && break
	sleep 1; done
echo "$label: first frame after $i s; settling $settle s"
sleep "$settle"
api=$(grep -a -A1 '^Direct3D:' "$L" | sed -n 's/.*Version: *//p' | head -1)
[ "$(stat -f %m "$L")" -ge "$t0" ] || api="(stale Player.log)"
args=$(sed -n '/=== notproton run/h; /=== notproton run/,$p' "$C/notproton-run.log" | sed -n '/^args:/,/^cwd=/p' | grep -v 'PEAK.exe\]\|args:\|cwd=' | tr -d ' []' | tr '\n' ' ')
echo "$label: launched with args: ${args:-none}"
rline=$(sed -n '/=== notproton run/h; /=== notproton run/,$p' "$C/notproton-run.log" | grep '^renderer:' | tail -1)
python3 -I "$here/frames.py" "$C" --seconds "$sample" --label "$label" --csv "$OUT/peak.csv" | sed "s|\$| api=$api|"
echo "$label: $rline"
id=$("$WINID" PEAK | awk 'NR==1{print $1}'); [ -z "$id" ] && id=$("$WINID" Wine | awk 'NR==1{print $1}')
[ -n "$id" ] && screencapture -x -o -l"$id" "$OUT/$label.png" && sips -Z 1200 "$OUT/$label.png" --out "$OUT/$label-s.png" > /dev/null
bid=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$HOME/Library/Application Support/notproton/launchers/app-$app/PEAK.app/Contents/Info.plist")
osascript -e "tell application id \"$bid\" to quit" > /dev/null 2>&1
i=0; while [ $i -lt 90 ]; do i=$((i+1)); tail -3 "$C/notproton-run.log" | grep -q 'session ending' && break; sleep 1; done
echo "$label: ended after $i s"
# Steam marks the game stopped a few seconds after the bundle goes; launching before that is ignored.
sleep 12
