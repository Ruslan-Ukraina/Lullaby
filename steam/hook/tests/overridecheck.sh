#!/bin/sh
# Launch options that switch a default off for one run (LULLABY_AVX=0, LULLABY_DLSS=0) reach
# bottle.env, where the engine reads them over the process environment. The functions are cut
# out of compat_run.sh, so the real text is tested.
set -u
here=$(cd "$(dirname "$0")" && pwd)
src="$here/../feats/compat_run.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/overridecheck.XXXXXX") || exit 1
trap 'rm -rf "${work:?}"' EXIT

for fn in env_file_set launch_overrides; do
  sed -n "/^$fn() {/,/^}/p" "$src" >> "$work/fn.sh"
done
[ -s "$work/fn.sh" ] || { echo "overridecheck: the functions are not in the run script" >&2; exit 1; }
# shellcheck disable=SC1091 # cut out above
. "$work/fn.sh"

fail=0
check() { # $1 name, $2 expected, $3 got
  [ "$2" = "$3" ] || { echo "overridecheck: $1: expected '$2', got '$3'" >&2; fail=1; }
}
fresh() {
  printf '%s\n' '# written by Lullaby' 'ROSETTA_ADVERTISE_AVX=1' 'DXMT_ENABLE_NVEXT=1' 'D3DM_ENABLE_METALFX=1' 'SEVO_FPS_LIMIT=0' > "$work/bottle.env"
}

fresh; ( LULLABY_AVX='' LULLABY_DLSS='' launch_overrides "$work/bottle.env" )
check "no option changes nothing" "$(printf '%s\n' '# written by Lullaby' 'ROSETTA_ADVERTISE_AVX=1' 'DXMT_ENABLE_NVEXT=1' 'D3DM_ENABLE_METALFX=1' 'SEVO_FPS_LIMIT=0')" "$(cat "$work/bottle.env")"

fresh; ( LULLABY_AVX=0 launch_overrides "$work/bottle.env" )
check "AVX off" "ROSETTA_ADVERTISE_AVX=0" "$(grep ROSETTA "$work/bottle.env")"
check "AVX off leaves DLSS" "DXMT_ENABLE_NVEXT=1" "$(grep NVEXT "$work/bottle.env")"

fresh; ( LULLABY_DLSS=0 launch_overrides "$work/bottle.env" )
check "DLSS off, NVEXT removed" "DXMT_ENABLE_NVEXT=" "$(grep NVEXT "$work/bottle.env")"
check "DLSS off, MetalFX removed" "D3DM_ENABLE_METALFX=" "$(grep METALFX "$work/bottle.env")"
check "DLSS off leaves AVX" "ROSETTA_ADVERTISE_AVX=1" "$(grep ROSETTA "$work/bottle.env")"

fresh; ( LULLABY_AVX=1 launch_overrides "$work/bottle.env" )
check "only 0 switches AVX off" "ROSETTA_ADVERTISE_AVX=1" "$(grep ROSETTA "$work/bottle.env")"
check "the file keeps its other lines" "5" "$(grep -c . "$work/bottle.env")"

[ "$fail" -eq 0 ] && echo "==> overridecheck: launch options turn AVX and DLSS off for one run"
exit "$fail"
