#!/bin/sh
# The run script tells a 32-bit program from a 64-bit one by its PE header (exe_machine), which
# decides display mode emulation. The function is cut out of compat_run.sh, so the real text is tested.
set -u
here=$(cd "$(dirname "$0")" && pwd)
src="$here/../feats/compat_run.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/bitnesscheck.XXXXXX") || exit 1
trap 'rm -rf "${work:?}"' EXIT

sed -n '/^exe_machine() {/,/^}/p' "$src" > "$work/fn.sh"
[ -s "$work/fn.sh" ] || { echo "bitnesscheck: exe_machine is not in the run script" >&2; exit 1; }
# shellcheck disable=SC1091 # cut out above
. "$work/fn.sh"

# A minimal PE: "MZ", the PE header offset 64 at byte 60, "PE\0\0", then the machine word.
pe() { # $1 file, $2 machine as two escaped bytes
  {
    printf 'MZ'; dd if=/dev/zero bs=1 count=58 2>/dev/null
    printf '\100\000\000\000'
    printf 'PE\000\000'
    # shellcheck disable=SC2059 # the machine word is an escape sequence passed as the format
    printf "$2"
  } > "$1"
}
fail=0
check() { # $1 name, $2 expected, $3 got
  [ "$2" = "$3" ] || { echo "bitnesscheck: $1: expected '$2', got '$3'" >&2; fail=1; }
}
pe "$work/x86.exe" '\114\001'
pe "$work/x64.exe" '\144\206'
printf 'MZ not a pe' > "$work/junk.exe"
: > "$work/empty.exe"
check "32-bit program" 014c "$(exe_machine "$work/x86.exe")"
check "64-bit program" 8664 "$(exe_machine "$work/x64.exe")"
check "not a PE" "" "$(exe_machine "$work/junk.exe")"
check "empty file" "" "$(exe_machine "$work/empty.exe")"
check "missing file" "" "$(exe_machine "$work/none.exe")"
[ "$fail" -eq 0 ] && echo "==> bitnesscheck: 32-bit and 64-bit programs told apart, anything else is neither"
exit "$fail"
