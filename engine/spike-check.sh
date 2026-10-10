#!/bin/sh
# Phase 1 evidence from one game's logs, for docs/SPIKE_TEST.md. Reads only.
#
#   engine/spike-check.sh            the game launched last
#   engine/spike-check.sh <appid>    a given game
#
# STEAM_LIBRARY points it at a library other than the default one.
#
# Run it after the game has been quit. It prints the log lines each GO
# criterion rests on and a verdict for the ones a log can settle; the window,
# fullscreen and overlay checks are by eye.

# Wine writes the console messages of a Russian or Ukrainian prefix in CP866, which
# awk and sed reject as UTF-8; the checks only need bytes.
LC_ALL=C
export LC_ALL

steam="$HOME/Library/Application Support/Steam"
support="$HOME/Library/Application Support/lullaby"
compat="${STEAM_LIBRARY:-$steam}/steamapps/compatdata"

appid=${1:-}
if [ -z "$appid" ]; then
	# The run log of the last launch is the newest one.
	newest=$(find "$compat" -mindepth 2 -maxdepth 2 -name lullaby-run.log \
		-exec stat -f '%m %N' {} + 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
	[ -n "$newest" ] || { echo "no lullaby-run.log under $compat, launch a game first" >&2; exit 1; }
	appid=$(basename "$(dirname "$newest")")
fi
case "$appid" in ''|*[!0-9]*) echo "not an app id: $appid" >&2; exit 1 ;; esac

run="$compat/$appid/lullaby-run.log"
wine="$support/launchers/app-$appid/lullaby-wine.log"
[ -f "$run" ] || { echo "no run log at $run" >&2; exit 1; }

pass=0
fail=0
verdict() {
	if [ "$1" = ok ]; then pass=$((pass + 1)); echo "  [ok]   $2"
	else fail=$((fail + 1)); echo "  [FAIL] $2"; fi
}
show() { sed 's/^/         /'; }

# Only the last session in the run log counts.
last_session() { awk '/^=== lullaby run /{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' "$run"; }
session=$(last_session)
# The run script writes its closing line up to ~11 s after Steam shows "Play"
# again: give an unfinished session 30 s. A stop from Steam ends it with the
# "termination signal, session ending" line, which is a clean end too.
ended() { printf '%s\n' "$session" | grep -a -q -E "^=== (wine prefix killed, session ending|termination signal, session ending) ==="; }
waited=0
while ! ended && [ "$waited" -lt 30 ]; do
	sleep 1; waited=$((waited + 1)); session=$(last_session)
done
name=$(printf '%s\n' "$session" | sed -n 's/^.*launchers\/app-[0-9]*\/\(.*\)\.app\/Contents\/MacOS\/wine$/\1/p' | head -1)
echo "app $appid${name:+ ($name)}"
echo "run log:  $run"
echo "wine log: $wine"
echo

echo "1. Steam Play started the game on Dormison"
printf '%s\n' "$session" | grep -a -E "^(engine:|=== launching)" | show
if printf '%s\n' "$session" | grep -a -q "^engine: dormison-"; then
	verdict ok "the run script ran on the Dormison engine"
else
	verdict fail "no 'engine: dormison-…' line in the last session"
fi

echo
echo "2. lsteamclient loaded and steamclient64 rerouted"
printf '%s\n' "$session" | grep -a -E "^runner:|patched copy|bridge is missing" | show
if [ -f "$wine" ]; then
	# B1 (docs/DECISIONS.md P3-1) says what it redirected, 64-bit steamclient64.dll
	# and 32-bit steamclient.dll alike; the spike's B2 only showed in the load order.
	hooked=$(grep -a "lead to lsteamclient" "$wine" | sed 's/.*\\\\//; s/".*: /: /' | sort -u)
	grep -a -E 'Loaded L".*(lsteamclient|steamclient64?)\.dll"' "$wine" | sed 's/^/         /' | head -8
	if [ -n "$hooked" ]; then
		printf '%s\n' "$hooked" | show
		verdict ok "the B1 loader hook led steamclient to lsteamclient"
	elif awk '
		/Loaded L".*\\lsteamclient\.dll"/ { split($0, t, ":"); lsc[t[1]] = 1; next }
		/Loaded L".*\\steamclient(64)?\.dll"/ { split($0, t, ":"); if (lsc[t[1]]) found = 1 }
		END { exit !found }' "$wine"; then
		verdict ok "lsteamclient.dll came in ahead of steamclient in the same thread (the detour fired)"
	else
		verdict fail "no sign that steamclient was led to lsteamclient"
	fi
	errors=$(grep -a -E "err:steamclient|unable to load native steamclient|_wassert" "$wine")
	if [ -n "$errors" ]; then
		printf '%s\n' "$errors" | head -5 | show
		verdict fail "lsteamclient reported errors (above)"
	else
		verdict ok "no lsteamclient errors"
	fi
else
	verdict fail "no wine log at $wine"
fi

echo
echo "3. msync on, and the session ended cleanly"
printf '%s\n' "$session" | grep -a -E "^sync:|^bottle.env:" | show
if printf '%s\n' "$session" | grep -a -q "^sync: WINEMSYNC=1"; then
	verdict ok "WINEMSYNC=1"
else
	verdict fail "WINEMSYNC is not 1 in the last session"
fi
if [ -f "$wine" ] && grep -a -q -E "msync: up and running|msync=1" "$wine"; then
	grep -a -m2 -E "msync: up and running|msync=1" "$wine" | show
	verdict ok "the engine reports msync running"
else
	verdict fail "the wine log does not show msync running"
fi
printf '%s\n' "$session" | grep -a -E "^=== (bundle exited|game exited|game tree gone|wine prefix killed|termination signal)" | show
if printf '%s\n' "$session" | grep -a -q -E "^=== (wine prefix killed|termination signal), session ending ==="; then
	verdict ok "the session ended and the prefix was shut down"
else
	verdict fail "the session has not ended (still running, or hung): quit the game and wait 15 s"
fi
# Ours: engine under lullaby/runners, launchers, or our compatdata. Other
# Wine (Sevoflurane bottles, CrossOver) is listed, never a failure.
all_wine=$(pgrep -fl "wineserver|steam\.exe|x86_64-unix/wine|MacOS/wine" 2>/dev/null)
left=$(printf '%s\n' "$all_wine" | grep -a -E "lullaby/(runners|launchers)|$compat" )
foreign=$(printf '%s\n' "$all_wine" | grep -a -v -E "lullaby/(runners|launchers)|$compat" | grep -a .)
if [ -n "$foreign" ]; then
	echo "         Wine processes that are not ours (ignored):"
	printf '%s\n' "$foreign" | show
fi
if [ -n "$left" ]; then
	printf '%s\n' "$left" | show
	verdict fail "our Wine processes are still running"
else
	verdict ok "no Wine processes of ours left"
fi

echo
echo "4. The game ran from its own bundle (Dock name, icon, Game Mode)"
if [ -f "$wine" ]; then
	grep -a "loader=bundle" "$wine" | sed 's/=\/.*\/launchers\//=…\/launchers\//' | head -4 | show
	if grep -a -q "loader=bundle" "$wine"; then
		verdict ok "Dormison re-executed the game through the bundle's loader"
	else
		verdict fail "no 'loader=bundle' line: the Dock may show 'wine' for the game"
	fi
fi
echo "         The window checks are by eye: resize, fullscreen and back, the View menu."

echo
echo "5. Renderer"
printf '%s\n' "$session" | grep -a -E "^renderer:" | show
if [ -f "$wine" ]; then
	grep -a -E "sevo:gfx pid=[0-9]+ (renderer=|first present)" "$wine" | head -4 | show
	# A process that named DXMT and then presented a frame; naming it alone is not drawing.
	drew=$(awk '
		/sevo:gfx pid=[0-9]+ renderer=dxmt/ { match($0, /pid=[0-9]+/); named[substr($0, RSTART, RLENGTH)] = 1 }
		/sevo:gfx pid=[0-9]+ first present/ { match($0, /pid=[0-9]+/); k = substr($0, RSTART, RLENGTH); if (named[k]) print k }' "$wine" | head -1)
	if [ -n "$drew" ]; then
		verdict ok "a process drew a frame through DXMT ($drew)"
	elif grep -a -q "sevo:gfx pid=[0-9]* renderer=dxmt" "$wine"; then
		verdict fail "DXMT was chosen but no process presented a frame"
	else
		echo "         no process reported renderer=dxmt (expected for a D3D9, OpenGL or Vulkan game)"
	fi
fi
printf '%s\n' "$session" | grep -a -E "overlay (injected|disabled)" | show

echo
echo "S1. Nothing called Sevoflurane"
if [ -s "$support/lullaby-sevo.log" ]; then
	tail -3 "$support/lullaby-sevo.log" | show
	echo "         (View menu settings went to Lullaby's stand-in, as they should)"
fi
sevo_pid=$(pgrep -f "Sevoflurane.app/Contents/MacOS/" 2>/dev/null | head -1)
if [ -n "$sevo_pid" ]; then
	sevo_start=$(date -j -f '%a %b %e %T %Y' "$(ps -o lstart= -p "$sevo_pid")" +%s 2>/dev/null || echo 0)
	# the log is appended to across sessions: the session starts at its own header line
	run_start=$(date -j -f '%a %b %e %T %Y' "$(printf '%s\n' "$session" | sed -n 's/^=== lullaby run \(.*\) [A-Z]* \([0-9]*\) ===$/\1 \2/p' | head -1)" +%s 2>/dev/null || echo 0)
	if [ "$sevo_start" -le "$run_start" ]; then
		verdict ok "Sevoflurane.app was already open before this session (not started by us)"
	else
		verdict fail "Sevoflurane.app started during this session ($(ps -o lstart= -p "$sevo_pid")): check who opened it"
	fi
else
	verdict ok "Sevoflurane.app is not running"
fi

echo
echo "$pass ok, $fail failed"
[ "$fail" -eq 0 ]
