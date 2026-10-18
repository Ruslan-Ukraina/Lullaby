#!/bin/sh
# Shared by the stand's scripts (perf/syncbench.sh, perf/gfxbench.sh): pick an engine, make
# a throw-away prefix, stage a renderer from that engine's own files, keep the Wine server
# honest. Sourced, not run. Every name starts with perf_.
#
# An engine is described by a lullaby-engine.env: LB_ENGINE_WINELOADER, LB_ENGINE_WINESERVER,
# LB_ENGINE_DLLPATH_X86_64 (the installed engine's file has them), and, for a Wine tree whose
# layout is not Dormison's, LB_ENGINE_DXMT_WIN (a folder with d3d11.dll, d3d10core.dll,
# dxgi.dll, winemetal.dll) and LB_ENGINE_DXMT_UNIX (the winemetal.so that goes with them).
#
# Why a renderer is staged here and not taken from lullaby/renderers: that folder holds links
# into whichever engine launched last, and pointing a different engine at it loads two
# winemac.so into one process ("Class WineApplication is implemented in both ...").

# shellcheck disable=SC2034 # the perf_* variables are this file's output, read by the scripts that source it

perf_engine_load() {
  perf_envfile=${1:-${LB_ENGINE_ENV:-$HOME/Library/Application Support/lullaby/runners/current/lullaby-engine.env}}
  [ -f "$perf_envfile" ] || { echo "perf: no engine env file ($perf_envfile)" >&2; return 2; }
  # shellcheck disable=SC1090
  . "$perf_envfile"
  perf_wine=${LB_ENGINE_WINELOADER:?engine env has no LB_ENGINE_WINELOADER}
  perf_server=${LB_ENGINE_WINESERVER:?engine env has no LB_ENGINE_WINESERVER}
  perf_engine=${LB_ENGINE_VERSION:-unknown}
  [ -x "$perf_wine" ] || { echo "perf: $perf_wine is not executable" >&2; return 2; }
  perf_root=${perf_wine%/wine/bin/wine}
  perf_dxmt_win=${LB_ENGINE_DXMT_WIN:-$perf_root/dxmt}
  perf_dxmt_unix=${LB_ENGINE_DXMT_UNIX:-${LB_ENGINE_UNIX_DIR:-$perf_root/wine/lib/wine/x86_64-unix}/winemetal.so}
}

perf_require_no_wine() {
  if pgrep -f wineserver > /dev/null 2>&1; then
    echo "perf: a Wine server is running; close the game or session first" >&2
    return 2
  fi
}

# Sets perf_idle (seconds since the last key or mouse event) and perf_load (1-minute load).
perf_note_machine() {
  perf_idle=$(ioreg -c IOHIDSystem | awk '/HIDIdleTime/{printf "%.0f", $NF/1000000000; exit}')
  perf_load=$(sysctl -n vm.loadavg | awk '{gsub(",", ".", $2); print $2}')
  echo "==> machine: user idle ${perf_idle:-?} s, 1-minute load ${perf_load:-?}"
}

# perf_wait_quiet LOAD: waits (up to 10 minutes) until the 1-minute load average is under LOAD.
perf_wait_quiet() {
  perf_waited=0
  while [ "$perf_waited" -lt 600 ]; do
    perf_now=$(sysctl -n vm.loadavg | awk '{gsub(",", ".", $2); print $2}')
    awk -v c="$perf_now" -v q="$1" 'BEGIN { exit !(c < q) }' && break
    sleep 10; perf_waited=$((perf_waited + 10))
  done
  echo "==> waited $perf_waited s for the load average (now $perf_now, wanted under $1)"
}

perf_stop_server() {
  "$perf_server" -k > /dev/null 2>&1 || true
  perf_i=0
  while pgrep -f wineserver > /dev/null 2>&1 && [ "$perf_i" -lt 50 ]; do sleep 0.2; perf_i=$((perf_i + 1)); done
}

# perf_prefix_init: a temporary folder with a fresh prefix; the Wine environment of every
# later run. Call perf_cleanup from a trap.
perf_prefix_init() {
  perf_tmp=$(mktemp -d "${TMPDIR:-/tmp}/lullaby-perf.XXXXXX")
  export WINEPREFIX="$perf_tmp/prefix" WINEDEBUG="${WINEDEBUG:--all}" WINESERVER="$perf_server"
  export WINEDLLPATH="$LB_ENGINE_DLLPATH_X86_64/.."
  export WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree,mshtml="
  unset WINEMSYNC WINEESYNC WINEFSYNC WINEWFUSYNC WINEWFUSYNC_DEBUG WINEDLLPATH_PREPEND 2> /dev/null || true
  echo "==> a prefix in a temporary folder"
  "$perf_wine" wineboot --init > /dev/null 2>&1 || true
  perf_stop_server
}

perf_cleanup() {
  [ -n "${perf_server:-}" ] && WINEPREFIX="${perf_tmp:-/nonexistent}/prefix" "$perf_server" -k > /dev/null 2>&1 || true
  [ -n "${perf_tmp:-}" ] && rm -rf "${perf_tmp:?}"
}

# perf_stage_dxmt: DXMT out of this engine's own files. Sets perf_prepend (for
# WINEDLLPATH_PREPEND) and perf_overrides (for WINEDLLOVERRIDES). Wine takes a builtin off the
# dll path only for a name the prefix holds a file for, and winemetal is not one of Wine's, so
# its PE goes into system32 too (dylib/feats/compat_run.sh, stage_renderer, says the same).
perf_stage_dxmt() {
  perf_prepend="$perf_tmp/dxmt"
  mkdir -p "$perf_prepend/x86_64-windows" "$perf_prepend/x86_64-unix"
  for f in d3d11 d3d10core dxgi winemetal; do
    [ -f "$perf_dxmt_win/$f.dll" ] || { echo "perf: $perf_dxmt_win/$f.dll is missing" >&2; return 2; }
    ln -sfn "$perf_dxmt_win/$f.dll" "$perf_prepend/x86_64-windows/$f.dll"
  done
  [ -f "$perf_dxmt_unix" ] || { echo "perf: $perf_dxmt_unix is missing" >&2; return 2; }
  ln -sfn "$perf_dxmt_unix" "$perf_prepend/x86_64-unix/winemetal.so"
  cp -f "$perf_dxmt_win/winemetal.dll" "$WINEPREFIX/drive_c/windows/system32/winemetal.dll"
  perf_overrides="d3d10core,d3d11,dxgi,winemetal=b"
}
