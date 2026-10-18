#!/bin/sh
# Do our patches still apply to a Wine tree's releases? A rehearsal of the update gate: for
# every tag of a git clone of the tree (WineForge, Dormison, ...), each patch of a folder is
# tried with `git apply --check` (strict) and, failing that, with `patch --dry-run -F3` (a
# shifted context). Nothing is built, nothing is changed: the tree is only checked out.
#
#   engine-fixes/rehearse.sh CLONE PATCH_DIR [TAG...]
#
#   CLONE      a git clone of the tree (a throw-away one: its files are overwritten by checkouts)
#   PATCH_DIR  searched for *.patch, any depth
#   TAG...     the tags to try, default all, oldest first
#
# Reading the table: OK = applies as it is; fuzz = applies with moved context (look at it);
# FAIL = does not apply. A patch that fails on the oldest release as well as the newest does
# not rot, it was never for this tree (it leans on code the tree does not have); a patch that
# is OK for a while and then FAILs is the one an update broke.
set -eu
clone=${1:?usage: rehearse.sh CLONE PATCH_DIR [TAG...]}
patches=${2:?usage: rehearse.sh CLONE PATCH_DIR [TAG...]}
shift 2
[ -d "$clone/.git" ] || { echo "rehearse: $clone is not a git clone" >&2; exit 2; }
if [ $# -gt 0 ]; then tags="$*"; else tags=$(git -C "$clone" tag | sort -V); fi
[ -n "$tags" ] || { echo "rehearse: no tags" >&2; exit 2; }

list=$(find "$patches" -name '*.patch' | sort)
[ -n "$list" ] || { echo "rehearse: no .patch files under $patches" >&2; exit 2; }

printf '%-44s' patch
for t in $tags; do printf ' %-7s' "${t##*.}"; done
echo
echo "$list" | while IFS= read -r p; do
  printf '%-44s' "$(basename "$p" .patch | cut -c1-43)"
  for t in $tags; do
    git -C "$clone" checkout -q -f "$t"
    if (cd "$clone" && git apply --check "$p") 2> /dev/null; then r=OK
    elif (cd "$clone" && patch -p1 --dry-run -F3 -s < "$p") > /dev/null 2>&1; then r=fuzz
    else r=FAIL; fi
    printf ' %-7s' "$r"
  done
  echo
done
