#!/bin/sh
# Behaviour of the run script's termination handler: the first TERM kills the
# prefix once, writes the closing line and exits 143, a repeated TERM changes
# nothing. The handler is cut out of compat_run.sh, so the real text is tested.
set -u
here=$(cd "$(dirname "$0")" && pwd)
src="$here/../feats/compat_run.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/termcheck.XXXXXX") || exit 1
trap 'rm -rf "${work:?}"' EXIT

log="$work/run.log"
count="$work/kills"
: > "$log"
: > "$count"

# stand-in wineserver: every -k is counted
cat > "$work/wineserver" <<SH
#!/bin/sh
[ "\$1" = "-k" ] && echo k >> "$count"
exit 0
SH
chmod +x "$work/wineserver"

{
  echo "log='$log'"
  echo "WINESERVER='$work/wineserver'"
  echo "open_pid="
  echo "prefix_server_dir() { return 1; }"
  sed -n '/^kill_wine_prefix() {/,/^}/p' "$src"
  sed -n '/^terminate() {/,/^}/p' "$src"
  echo "trap terminate TERM INT HUP"
  echo "echo ready > '$work/ready'"
  echo "while :; do sleep 1; done"
} > "$work/sim.sh"

sh "$work/sim.sh" &
pid=$!
i=0
while [ ! -f "$work/ready" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
kill -TERM "$pid"
kill -TERM "$pid" 2>/dev/null || true
wait "$pid"
status=$?

fail=0
[ "$status" -eq 143 ] || { echo "FAIL: exit status $status, want 143"; fail=1; }
grep -q 'termination signal, session ending' "$log" || { echo "FAIL: no closing line"; fail=1; }
n=$(grep -c k "$count")
[ "$n" -eq 1 ] || { echo "FAIL: wineserver -k ran $n times, want 1"; fail=1; }
if [ "$fail" -eq 0 ]; then echo "==> termcheck: TERM ends the session once with status 143"; fi
exit "$fail"
