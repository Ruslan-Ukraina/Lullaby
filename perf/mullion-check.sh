#!/bin/sh
# Phase 7C check: PEAK and RE9 on Mullion against their recipe renderer, two launches per game,
# the game's own settings untouched. Restores each game to its recipe afterwards.
set -u
here=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:-$here/../scratch/perf}; mkdir -p "$OUT"
CLI="$HOME/Library/Application Support/notproton/notproton-settings"
api() { grep -a -A1 '^Direct3D:' "$HOME/Library/Application Support/Steam/steamapps/compatdata/3527290/pfx/drive_c/users/steamuser/AppData/LocalLow/LandCrab/PEAK/Player.log" | sed -n 's/.*Version: *//p' | head -1; }
lastrun() { sed -n '/=== notproton run/h; /=== notproton run/,$p' "$HOME/Library/Application Support/Steam/steamapps/compatdata/$1/notproton-run.log" | grep -E '^renderer:|^mullion:|unavailable|32-bit|not downloaded' | tail -3; }

"$CLI" set --app 3527290 renderer '"mullion"' > /dev/null || echo "PEAK: could not pick Mullion"
"$here/peak-matrix.sh" peak-mullion keep - 45 20 2>&1 | grep '^label\|first frame'; echo "  api: $(api)"; lastrun 3527290
"$CLI" set --app 3527290 renderer null > /dev/null
"$here/peak-matrix.sh" peak-dxmt keep - 45 20 2>&1 | grep '^label\|first frame'; echo "  api: $(api)"; lastrun 3527290

"$CLI" set --app 4022369388 renderer '"mullion"' > /dev/null || echo "RE9: could not pick Mullion"
"$here/re9-run.sh" re9-mullion 60 20 | grep -v '^$'; lastrun 4022369388
"$CLI" set --app 4022369388 renderer null > /dev/null
"$here/re9-run.sh" re9-d3dmetal 60 20 | grep -v '^$'; lastrun 4022369388
for a in 3527290 4022369388; do "$CLI" state --app $a | python3 -c 'import json,sys; s=json.load(sys.stdin); v=s["values"]["renderer"]; print(s.get("appID"), "renderer", v["effective"], "from", v["inheritedFrom"])'; done
