#!/bin/sh
# What DXGI tells a game about memory, through D3DMetal and through the engine's own DXGI, in a throw-away prefix.
#   perf/dxgiprobe.sh [VAR=value ...]    the variables go to the probe's environment (e.g. SEVO_GPU_MEMORY_MB=12288)
set -u
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=perf/common.sh
. "$here/common.sh"
perf_engine_load "${LB_ENGINE_ENV:-}" || exit 2
perf_require_no_wine || exit 2
trap perf_cleanup EXIT INT TERM
perf_prefix_init
x86_64-w64-mingw32-gcc -O2 -Wall -o "$perf_tmp/dxgiprobe.exe" "$here/dxgiprobe.c" -ldxgi -luuid -static-libgcc || exit 2
perf_stage_d3dmetal || exit 2
perf_stop_server
echo "--- through D3DMetal${*:+ ($*)}"
env WINEDLLPATH_PREPEND="$perf_prepend" WINEDLLOVERRIDES="$perf_overrides;${WINEDLLOVERRIDES:-}" \
  SEVO_LIBD3DSHARED_PATH="$perf_ext/libd3dshared.dylib" D3DM_WINE_UNIX_CALL=1 "$@" "$perf_wine" "$perf_tmp/dxgiprobe.exe" 2>&1 | grep -E '^(adapter|  local|  non-local|no DXGI)'

perf_stop_server
echo "--- the engine's own DXGI"
env "$@" "$perf_wine" "$perf_tmp/dxgiprobe.exe" 2>&1 | grep -E '^(adapter|  local|  non-local|no DXGI)' 
