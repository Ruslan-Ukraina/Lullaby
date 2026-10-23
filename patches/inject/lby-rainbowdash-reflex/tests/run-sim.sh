#!/bin/sh
# Runs reflex-sim.c against Lullaby's nvapi64.dll under the installed engine's Wine, with
# low latency mode off and on, and checks what Reflex by Lullaby is meant to do:
#   GPU-bound, with or without V-Sync: shorter latency, at most a little frame rate lost;
#   CPU-bound: nothing held, nothing changed.
#
#   patches/inject/lby-rainbowdash-reflex/tests/run-sim.sh [NVAPI_DLL]      (default out/lullaby-nvapi64.dll)
#
# Needs mingw-w64 and an installed engine (runners/current/lullaby-engine.env); with no
# engine it says so and exits 0 (SKIP), because a CI runner has none. The run takes about
# a minute: the first Wine start makes a prefix in a temporary directory.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
dll=${1:-$root/out/lullaby-nvapi64.dll}
envfile=${LB_ENGINE_ENV:-$HOME/Library/Application Support/lullaby/runners/current/lullaby-engine.env}

[ -f "$dll" ] || { echo "run-sim: $dll is missing (make nvapi-shim)" >&2; exit 1; }
if [ ! -f "$envfile" ]; then
  echo "run-sim: SKIP, no installed engine ($envfile)"
  exit 0
fi
# shellcheck disable=SC1090
. "$envfile"
wine=$LB_ENGINE_WINELOADER
[ -x "$wine" ] || { echo "run-sim: SKIP, $wine is not executable"; exit 0; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/lullaby-reflex-sim.XXXXXX")
cleanup() {
  WINEPREFIX="$tmp/prefix" "$LB_ENGINE_WINESERVER" -k >/dev/null 2>&1 || true
  rm -rf "${tmp:?}"
}
trap cleanup EXIT INT TERM

x86_64-w64-mingw32-gcc -O2 -Wall -o "$tmp/reflex-sim.exe" "$here/reflex-sim.c" -lwinmm -lm
mkdir -p "$tmp/dlls/x86_64-windows"
cp "$dll" "$tmp/dlls/x86_64-windows/nvapi64.dll"

export WINEPREFIX="$tmp/prefix" WINEMSYNC=1 WINEDEBUG=-all WINESERVER="$LB_ENGINE_WINESERVER"
export WINEDLLPATH="$LB_ENGINE_DLLPATH_X86_64/.." WINEDLLPATH_PREPEND="$tmp/dlls"
export WINEDLLOVERRIDES="nvapi64=b;winemenubuilder.exe=d;mscoree,mshtml="
"$wine" wineboot --init >/dev/null 2>&1 || true

# sim GPU_MS CPU_MS VSYNC_HZ LAG_MS MODE -> "fps latency"
sim() {
  out=$(SIM_GPU_MS=$1 SIM_CPU_MS=$2 SIM_VSYNC_HZ=$3 SIM_LAG_MS=$4 "$wine" "$tmp/reflex-sim.exe" "$5" 2>&1) || {
    echo "run-sim: the simulator failed:" >&2; echo "$out" >&2; exit 1; }
  echo "$out" | sed -n 's/.* fps \([0-9.]*\) latency \([0-9.]*\) ms.*/\1 \2/p' | tail -1
}

fail=0
# check NAME GPU CPU VSYNC LAG MAX_LATENCY_RATIO MIN_FPS_RATIO
check() {
  name=$1
  set -- "$2" "$3" "$4" "$5" "$6" "$7"
  off=$(sim "$1" "$2" "$3" "$4" 0)
  on=$(sim "$1" "$2" "$3" "$4" 1)
  [ -n "$off" ] && [ -n "$on" ] || { echo "run-sim: no result for $name" >&2; exit 1; }
  # $off is "fps latency", $on too: $1 $2 off, $3 $4 on, $5 and $6 the limits.
  if echo "$off $on $5 $6" | awk '{ exit !($4 / $2 <= $5 && $3 / $1 >= $6) }'; then
    verdict=ok
  else
    verdict=FAIL
    fail=1
  fi
  echo "$off $on" | awk -v n="$name" -v v="$verdict" -v lr="$5" -v fr="$6" \
    '{ printf "  %-4s %-34s off %5.1f fps %5.1f ms | on %5.1f fps %5.1f ms | latency x%.2f (max %.2f), fps x%.2f (min %.2f)\n", v, n, $1, $2, $3, $4, $4/$2, lr, $3/$1, fr }'
}

echo "==> reflex-sim ($dll)"
#     name                               GPU CPU HZ LAG  lat   fps
check "GPU-bound, no V-Sync"              20   8   0   0  0.60  0.95
check "GPU-bound, CPU close to GPU"       16  14   0   0  0.75  0.95
check "V-Sync 120 Hz, GPU 9 ms"            9   2 120   0  0.85  0.95
check "V-Sync 120 Hz, GPU 10, lag 8 ms"   10   2 120   8  0.85  0.95
check "CPU-bound: nothing to hold"         8  14   0   0  1.10  0.95
if [ "$fail" -ne 0 ]; then
  echo "==> reflex-sim: FAILED" >&2
  exit 1
fi
echo "==> reflex-sim: all scenarios hold"
