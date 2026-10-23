#!/bin/sh
# The synthetic Direct3D 11 scene (tools/perf/d3d11bench.c) through DXMT under one engine, in several
# configurations, with the processor time of the game's threads sampled beside it
# (tools/perf/threadcpu.c). Rounds go configuration by configuration, round after round, so drift
# in the Mac's load hits all alike. A window opens on the screen for each run.
#
#   tools/perf/gfxbench.sh [--engine-env FILE] [--runs N] [--config LABEL:VAR=v,VAR=v]...
#                    [--bench cpu|gpu]... [--seconds S] [--out CSV] [--wait-quiet PERCENT]
#                    [--min-idle S] [--no-threads] [--no-tap] [--renderer dxmt|d3dmetal]
#
#   --config      a label and the environment of that configuration; default
#                 "dxmt-msync:WINEMSYNC=1". WineForge: "dxmt-wfusync:WINEWFUSYNC=1".
#                 BENCH_DRAWS, BENCH_FILL, BENCH_VSYNC ... go here too (see d3d11bench.c).
#   --renderer    dxmt (default) or d3dmetal: Apple's D3DMetal from the Game Porting Toolkit Lullaby holds
#                 (LB_D3DMETAL), for a Dormison or a WineForge engine (LB_ENGINE_KIND in its env file)
#   --bench       cpu (many small draws), gpu (heavy pixels); default both
#   --seconds     measured seconds a run, default 12 (after 3 s of warm-up)
#   --out         CSV to append to, default scratch/perf/gfxbench.csv; the thread rows go to
#                 the same name with -threads before .csv
#   --min-idle    refuse unless the user has been idle this many seconds (default 20): a
#                 window pops up, and a user at the keyboard disturbs the numbers
#   --no-threads  skip the thread sampling
#   --no-tap      skip the frame tap (tools/perf/frametap.m): the frames then come from the program's
#                 own count only; with it, tap_* columns carry what reached the screen
#
# Round 0 of each configuration is a warm-up (in the CSV, left out of the report).
# Needs mingw-w64 and Xcode's clang. Refuses to run while a Wine server is alive.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
# shellcheck source=tools/perf/common.sh
. "$here/common.sh"

envfile=""
runs=3
out=$root/scratch/perf/gfxbench.csv
configs=""
benches=""
seconds=12
quiet=""
min_idle=20
threads=1
tap=1
renderer=dxmt

while [ $# -gt 0 ]; do
  case $1 in
    --engine-env) envfile=$2; shift 2 ;;
    --runs) runs=$2; shift 2 ;;
    --config) configs="$configs
$2"; shift 2 ;;
    --bench) benches="$benches $2"; shift 2 ;;
    --seconds) seconds=$2; shift 2 ;;
    --out) out=$2; shift 2 ;;
    --wait-quiet) quiet=$2; shift 2 ;;
    --min-idle) min_idle=$2; shift 2 ;;
    --no-threads) threads=0; shift ;;
    --no-tap) tap=0; shift ;;
    --renderer) renderer=$2; shift 2 ;;
    *) echo "gfxbench: unknown option $1" >&2; exit 2 ;;
  esac
done
[ -n "$configs" ] || configs="
dxmt-msync:WINEMSYNC=1"
[ -n "$benches" ] || benches="cpu gpu"
threads_csv=${out%.csv}-threads.csv

perf_engine_load "$envfile"
perf_require_no_wine
[ -z "$quiet" ] || perf_wait_quiet "$quiet"
perf_note_machine
if [ "${perf_idle:-0}" -lt "$min_idle" ] 2> /dev/null; then
  echo "gfxbench: the user was active ${perf_idle:-0} s ago (need $min_idle s idle): a window pops up and input disturbs the numbers" >&2
  exit 2
fi
echo "==> gfxbench: engine $perf_engine, renderer $renderer, $runs rounds, benches:$benches, $seconds s a run"

trap perf_cleanup EXIT INT TERM
tc=$root/out/threadcpu
tapdylib=$root/out/frametap.dylib
if [ ! -x "$tc" ] || [ ! -f "$tapdylib" ]; then "$here/build.sh"; fi
perf_prefix_init
case $renderer in
  dxmt) perf_stage_dxmt ;;
  d3dmetal) perf_stage_d3dmetal ;;
  *) echo "gfxbench: --renderer is dxmt or d3dmetal" >&2; exit 2 ;;
esac
x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -Wno-unused-parameter -o "$perf_tmp/d3d11bench.exe" "$here/d3d11bench.c" \
  -ld3d11 -ldxgi -ld3dcompiler_47 -luuid -static-libgcc

mkdir -p "$(dirname "$out")"
[ -s "$out" ] || echo "engine,config,bench,round,frames,fps,avg_ms,p50_ms,p95_ms,p99_ms,p999_ms,low1_fps,low01_fps,tap_fps,tap_p99_ms,tap_low1_fps,tap_low01_fps,tap_dropped,idle_s,load_before,load_after" > "$out"
[ "$threads" -eq 0 ] || [ -s "$threads_csv" ] || echo "engine,config,bench,round,group,threads,cpu_pct" > "$threads_csv"

# field NAME LINE: the value of NAME=value in a d3d11bench result line
field() { printf '%s\n' "$2" | tr ' ' '\n' | sed -n "s/^$1=//p"; }

warmup=3
round=0
while [ "$round" -le "$runs" ]; do
  echo "$configs" | while IFS= read -r spec; do
    [ -n "$spec" ] || continue
    label=${spec%%:*}
    vars=${spec#*:}
    spaced=$(printf '%s' "$vars" | tr ',' ' ')
    for bench in $benches; do
      perf_stop_server
      load_before=$(sysctl -n vm.loadavg | awk '{gsub(",", ".", $2); print $2}')
      result="$perf_tmp/result.txt"
      : > "$result"
      rm -rf "$perf_tmp/ft"
      mkdir -p "$perf_tmp/ft"
      tapenv=""
      [ "$tap" -eq 0 ] || tapenv="DYLD_INSERT_LIBRARIES=$tapdylib LULLABY_FRAMETAP=$perf_tmp/ft LULLABY_FRAMETAP_LABEL=$label/$bench/$round"
      (
        # shellcheck disable=SC2086 # the configuration's VAR=value pairs, one word each, by design
        # shellcheck disable=SC2086 # tapenv is VAR=value pairs, one word each, by design
        # shellcheck disable=SC2086 # perf_renderer_env: VAR=value words, by design
        env ${perf_prepend:+WINEDLLPATH_PREPEND="$perf_prepend"} WINEDLLOVERRIDES="$perf_overrides;$WINEDLLOVERRIDES" \
          $perf_renderer_env BENCH_MODE="$bench" BENCH_SECONDS="$seconds" BENCH_WARMUP="$warmup" $tapenv $spaced \
          "$perf_wine" "$perf_tmp/d3d11bench.exe" > "$result" 2> "$perf_tmp/stderr.txt"
      ) &
      bench_pid=$!
      if [ "$threads" -eq 1 ] && [ "$round" -gt 0 ]; then
        sleep $((warmup + 1))
        game=$(pgrep -f 'd3d11bench\.exe' | head -1 || true)
        if [ -n "$game" ]; then
          "$tc" --seconds $((seconds - 2)) --interval 1 --csv "$perf_tmp/threads.csv" --label "$perf_engine" "$game" > /dev/null 2>&1 || true
          if [ -s "$perf_tmp/threads.csv" ]; then
            tail -n +2 "$perf_tmp/threads.csv" | while IFS=, read -r _ _ grp n pct; do
              echo "$perf_engine,$label,$bench,$round,$grp,$n,$pct" >> "$threads_csv"
            done
          fi
          rm -f "$perf_tmp/threads.csv"
        fi
      fi
      wait "$bench_pid" || true
      load_after=$(sysctl -n vm.loadavg | awk '{gsub(",", ".", $2); print $2}')
      line=$(grep '^d3d11bench ' "$result" | tail -1 || true)
      if [ -z "$line" ]; then
        echo "gfxbench: round $round, $label, $bench: no result" >&2
        tail -3 "$perf_tmp/stderr.txt" >&2 2> /dev/null || true
        continue
      fi
      tapline=""
      if [ "$tap" -eq 1 ]; then
        tapline=$(python3 -I "$here/frametap-stats.py" "$perf_tmp"/ft/*.csv --skip "$warmup" 2> /dev/null || true)
        [ -n "$tapline" ] || echo "gfxbench: the frame tap saw no frames (DYLD_INSERT_LIBRARIES refused, or no CAMetalLayer drawable)" >&2
      fi
      echo "$perf_engine,$label,$bench,$round,$(field frames "$line"),$(field fps "$line"),$(field avg_ms "$line"),$(field p50_ms "$line"),$(field p95_ms "$line"),$(field p99_ms "$line"),$(field p999_ms "$line"),$(field low1_fps "$line"),$(field low01_fps "$line"),$(field tap_fps "$tapline"),$(field tap_p99_ms "$tapline"),$(field tap_low1_fps "$tapline"),$(field tap_low01_fps "$tapline"),$(field tap_dropped "$tapline"),${perf_idle:-},$load_before,$load_after" >> "$out"
      if [ "$round" -eq 0 ]; then
        echo "    warm-up, $label, $bench: $(field fps "$line") fps"
      else
        echo "    round $round, $label, $bench: $(field fps "$line") fps, p99 $(field p99_ms "$line") ms, 1% low $(field low1_fps "$line"); screen: $(field tap_fps "$tapline") fps"
      fi
    done
  done
  round=$((round + 1))
done
perf_stop_server
echo "==> rows appended to $out"
