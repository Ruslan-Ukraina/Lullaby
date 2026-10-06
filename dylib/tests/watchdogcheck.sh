#!/bin/sh
# The test-run watchdog: with NOTPROTON_WATCHDOG=<n> a game that has drawn no
# frame after n seconds is screenshotted and its prefix killed; one that has
# drawn a frame, or a run without the variable, is left alone. The function is
# cut out of compat_run.sh, so the real text is tested.
set -u
here=$(cd "$(dirname "$0")" && pwd)
src="$here/../feats/compat_run.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/watchdogcheck.XXXXXX") || exit 1
trap 'rm -rf "${work:?}"' EXIT

mkdir -p "$work/bin" "$work/loader" "$work/compat"
# shellcheck disable=SC2016 # the stand-in expands its own $2
printf '#!/bin/sh\ntouch "$2"\n' > "$work/bin/screencapture"
chmod +x "$work/bin/screencapture"
PATH="$work/bin:$PATH"; export PATH

{
  echo "log='$work/run.log'"
  echo "loader_root='$work/loader'"
  echo "STEAM_COMPAT_DATA_PATH='$work/compat'"
  echo "kills=0"
  echo "kill_wine_prefix() { echo k >> '$work/kills'; }"
  sed -n '/^start_watchdog() {/,/^}/p' "$src"
  echo 'start_watchdog'
  # shellcheck disable=SC2016 # written into the script as text
  echo '[ -n "$watchdog_pid" ] && wait "$watchdog_pid"'
} > "$work/sim.sh"

run() { : > "$work/kills"; : > "$work/run.log"; rm -f "$work/compat/notproton-watchdog.png"; env "$@" sh "$work/sim.sh"; }
fail=0

: > "$work/loader/notproton-wine.log"
run NOTPROTON_WATCHDOG=2
[ "$(grep -c k "$work/kills")" = 1 ] || { echo "FAIL: no frame, prefix not killed once"; fail=1; }
grep -q "watchdog: no first frame in 2s" "$work/run.log" || { echo "FAIL: no log line"; fail=1; }
[ -f "$work/compat/notproton-watchdog.png" ] || { echo "FAIL: no screenshot"; fail=1; }

echo "sevo:gfx pid=1 first present +10ms" > "$work/loader/notproton-wine.log"
run NOTPROTON_WATCHDOG=3
[ "$(grep -c k "$work/kills")" = 0 ] || { echo "FAIL: killed a game that drew"; fail=1; }

: > "$work/loader/notproton-wine.log"
run NOTPROTON_WATCHDOG=
[ "$(grep -c k "$work/kills")" = 0 ] || { echo "FAIL: watchdog ran without the variable"; fail=1; }
run NOTPROTON_WATCHDOG=abc
[ "$(grep -c k "$work/kills")" = 0 ] || { echo "FAIL: watchdog ran on a bad value"; fail=1; }

[ "$fail" -eq 0 ] && echo "==> watchdogcheck: a game with no first frame is ended, others are not"
exit "$fail"
