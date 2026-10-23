#!/bin/sh
# Is every engine patch in the registry, and does every patch the registry names exist?
#   patches/engine/check-registry.sh
# Patches are *.patch under patches/engine/, apart from experiments/ and rejected-*, which are
# not built into anything and need no entry (the registry may name them). The registry is
# docs/PATCH_REGISTRY.md: a patch is "in" it when its file name appears there in backticks.
# Also: every patch must start with a header (text before the first diff line).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
reg=$repo/docs/PATCH_REGISTRY.md
[ -f "$reg" ] || { echo "patchcheck: $reg is missing" >&2; exit 1; }

all=$(find "$here" -name '*.patch' | sed 's#.*/##' | sort -u)
need=$(find "$here" -name '*.patch' -not -path '*/experiments/*' -not -name 'rejected-*' | sed 's#.*/##' | sort -u)
# shellcheck disable=SC2016 # the backticks are literal: a name in the registry is written between them
named=$(grep -o '`[A-Za-z0-9._-]*\.patch`' "$reg" | tr -d '`' | sort -u)

fail=0
for p in $need; do
  echo "$named" | grep -qx "$p" || { echo "patchcheck: $p is not in docs/PATCH_REGISTRY.md" >&2; fail=1; }
done
for p in $named; do
  echo "$all" | grep -qx "$p" || { echo "patchcheck: the registry names $p, which does not exist" >&2; fail=1; }
done
find "$here" -name '*.patch' -not -path '*/experiments/*' -not -name 'rejected-*' | sort | while IFS= read -r f; do
  head=$(awk '/^(diff |--- |Index: )/{exit} {print}' "$f" | grep -c '[A-Za-z]' || true)
  [ "$head" -ge 3 ] || echo "patchcheck: $(basename "$f") has no header (the text before the diff)" >&2
done > "${TMPDIR:-/tmp}/patchcheck.$$" 2>&1
if [ -s "${TMPDIR:-/tmp}/patchcheck.$$" ]; then cat "${TMPDIR:-/tmp}/patchcheck.$$" >&2; fail=1; fi
rm -f "${TMPDIR:-/tmp}/patchcheck.$$"
[ "$fail" -eq 0 ] || exit 1
echo "==> patchcheck: $(echo "$need" | wc -l | tr -d ' ') patches, all in the registry, none missing, all with a header"
