#!/bin/sh
# Shared by the stand's scripts (tools/perf/syncbench.sh, tools/perf/gfxbench.sh): pick an engine, make
# a throw-away prefix, stage a renderer from that engine's own files, keep the Wine server
# honest. Sourced, not run. Every name starts with perf_.
#
# An engine is described by a lullaby-engine.env: LB_ENGINE_WINELOADER, LB_ENGINE_WINESERVER,
# LB_ENGINE_DLLPATH_X86_64 (the installed engine's file has them), and, for a Wine tree whose
# layout is not Dormison's, LB_ENGINE_DXMT_WIN (a folder with d3d11.dll, d3d10core.dll,
# dxgi.dll, winemetal.dll) and LB_ENGINE_DXMT_UNIX (the winemetal.so that goes with them) and
# LB_ENGINE_KIND=wineforge (default: dormison), which says how D3DMetal reaches the game.
# The D3DMetal runtime is Apple's Game Porting Toolkit as Lullaby holds it (LB_D3DMETAL, default
# the newest folder of lullaby/d3dmetal); nothing of it is copied into an engine.
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

# perf_cpu_idle: the share of the processors that are idle right now, in whole per cent (two
# samples of top, a second apart; the second is the one that counts).
perf_cpu_idle() {
  top -l 2 -n 0 -s 1 2> /dev/null | sed -n 's/.* \([0-9][0-9.,]*\)% idle.*/\1/p' | tail -1 | tr ',' '.' | awk '{printf "%.0f", $1}'
}

# perf_wait_quiet PERCENT: waits (up to 10 minutes) until at least PERCENT of the processors are
# idle. The 1-minute load average is no use for this: it counts runnable threads, and this Mac
# keeps four or five of them busy by itself (WindowServer, a VPN, the session's client).
perf_wait_quiet() {
  perf_waited=0
  while [ "$perf_waited" -lt 600 ]; do
    perf_now=$(perf_cpu_idle)
    [ "${perf_now:-0}" -ge "$1" ] && break
    sleep 5; perf_waited=$((perf_waited + 6))
  done
  echo "==> waited $perf_waited s for the processors (now ${perf_now:-?}% idle, wanted $1%)"
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
# its PE goes into system32 too (steam/hook/feats/compat_run.sh, stage_renderer, says the same).
perf_stage_dxmt() {
  perf_renderer_env=""
  if [ "${LB_ENGINE_KIND:-dormison}" = wineforge ]; then
    # Its loader finds DXMT through DXMT_RUNTIME_DIR (i386-windows, x86_64-windows, x86_64-unix
    # beside each other); WINEDLLPATH_PREPEND is Dormison's and does not exist there.
    perf_dxmt_dir=${perf_dxmt_win%/x86_64-windows}
    perf_prepend=""
    perf_overrides="dxgi,d3d10,d3d10core,d3d11,d3d12,winemetal=b"
    perf_renderer_env="GRAPHICS_BACKEND=dxmt DXMT_RUNTIME_DIR=$perf_dxmt_dir"
    cp -f "$perf_dxmt_win/winemetal.dll" "$WINEPREFIX/drive_c/windows/system32/winemetal.dll"
    return 0
  fi
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

# perf_stage_d3dmetal: Apple's D3DMetal for this engine. Sets perf_prepend, perf_overrides (as
# perf_stage_dxmt does) and perf_renderer_env, a list of VAR=value words for `env`.
#  dormison:  the engine's own x86_64-unix links lead into its lib/external (where Lullaby put the
#             toolkit's libraries); the toolkit's Windows DLLs come from a folder of links made here.
#             Refuses when the engine's lib/external is not the toolkit's: running Lullaby once with
#             D3DMetal fixes that, the stand does not write into an engine.
#  wineforge: GRAPHICS_BACKEND=d3dmetal and D3DMETAL_RUNTIME_DIR=<toolkit>/lib (its loader looks for
#             wine/x86_64-windows and wine/x86_64-unix there, the toolkit's own layout).
perf_stage_d3dmetal() {
  perf_tk=${LB_D3DMETAL:-}
  if [ -z "$perf_tk" ]; then
    perf_tk=$(find "$HOME/Library/Application Support/lullaby/d3dmetal" -mindepth 1 -maxdepth 1 -type d 2> /dev/null | sort | tail -1)
  fi
  [ -f "$perf_tk/lib/external/libd3dshared.dylib" ] || { echo "perf: no Game Porting Toolkit at '$perf_tk' (LB_D3DMETAL)" >&2; return 2; }
  if [ "${LB_ENGINE_KIND:-dormison}" = wineforge ]; then
    perf_prepend=""
    perf_overrides="dxgi,d3d10,d3d10core,d3d11,d3d12=n,b"
    perf_renderer_env="GRAPHICS_BACKEND=d3dmetal D3DMETAL_RUNTIME_DIR=$perf_tk/lib"
    return 0
  fi
  perf_ext="$perf_root/wine/lib/external"
  if ! cmp -s "$perf_tk/lib/external/libd3dshared.dylib" "$perf_ext/libd3dshared.dylib"; then
    echo "perf: $perf_ext does not hold the toolkit's libd3dshared; start a D3DMetal game from Lullaby once" >&2
    return 2
  fi
  perf_prepend="$perf_tmp/d3dmetal"
  mkdir -p "$perf_prepend/x86_64-windows" "$perf_prepend/x86_64-unix"
  perf_names=""
  for f in "$perf_tk/lib/wine/x86_64-windows"/*.dll; do
    [ -f "$f" ] || continue
    b=$(basename "$f" .dll)
    n=$b
    [ "$b" = nvngx-on-metalfx ] && n=nvngx
    ln -sfn "$f" "$perf_prepend/x86_64-windows/$n.dll"
    u="${LB_ENGINE_UNIX_DIR:-$perf_root/wine/lib/wine/x86_64-unix}/$b.so"
    [ -e "$u" ] || u="$perf_ext/libd3dshared.dylib"
    ln -sfn "$u" "$perf_prepend/x86_64-unix/$n.so"
    perf_names="${perf_names:+$perf_names,}$n"
  done
  perf_overrides="$perf_names=b"
  perf_renderer_env="SEVO_LIBD3DSHARED_PATH=$perf_ext/libd3dshared.dylib D3DM_WINE_UNIX_CALL=1"
}
