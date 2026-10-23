#!/bin/sh
# Whether Valve's CDN still serves every package Lullaby.app pins (INDEPENDENCE I5):
# Install fetches them on a player's Mac (bridge/fetch-valve.sh, ValveFetcher), so a
# pin that stopped answering breaks a clean install before any player notices.
#
#   release/valve-check.sh [manifest]
#
# A HEAD request per package and bundle, on each CDN host in turn; a package passes
# when one host answers 200. Nothing is downloaded. Prints one line per package and
# exits 1 when any package has no host left. The sha256 pins are not checked here:
# a full download is the Install path's job, and that still verifies every file.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
MANIFEST=${1:-$repo/app/Sources/LullabyApp/Resources/valve-packages.manifest}
[ -f "$MANIFEST" ] || { echo "==> valve-check: no package manifest at $MANIFEST" >&2; exit 2; }

bases=$(awk '$1 == "base" { print $2 }' "$MANIFEST")
names=$(awk '$1 == "package" { print $3 } $1 == "bundle" { print $2 }' "$MANIFEST")
[ -n "$bases" ] && [ -n "$names" ] || { echo "==> valve-check: $MANIFEST names no hosts or packages" >&2; exit 2; }

missing=0
for name in $names; do
	found=""
	for base in $bases; do
		code=$(curl -sS -o /dev/null -I -w '%{http_code}' --retry 2 --max-time 30 "$base/$name" 2>/dev/null) || code=000
		if [ "$code" = 200 ]; then found=$base; break; fi
	done
	if [ -n "$found" ]; then
		echo "ok       $name ($found)"
	else
		echo "MISSING  $name (no host answers 200)"
		missing=$((missing + 1))
	fi
done
[ "$missing" -eq 0 ] || { echo "==> valve-check: $missing pinned package(s) are gone from Valve's CDN"; exit 1; }
echo "==> valve-check: every pinned package is served"
