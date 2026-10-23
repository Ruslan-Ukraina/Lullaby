#!/bin/sh
# Assemble the headers the shim compiles against, into proton-headers/ next to the
# sources so the whole include set sits under srcdir once build.sh syncs it across.
#
# One of them comes from a Proton submodule, which a codeload tarball does not carry: it records
# wine as an empty directory. heap.h is fetched individually at the commit Proton pins on
# proton_9.0, which is the branch this shim's steam.cpp comes from, and checked against its
# recorded hash. Nothing else in the submodule is used: heap.h needs winbase.h, which the wine
# tree supplies. (The OpenVR headers went with the VR code: bridge/ELEMENTS.md.)
#
# The Steamworks SDK headers are Valve's too but arrive with lsteamclient, so they
# are copied from the tree its fetch.sh assembles rather than fetched again.
#
# Usage:
#   ./fetch-headers.sh            assemble if needed
#   ./fetch-headers.sh --refetch  discard the cache first
#
# Overridable: VALVE_WINE_COMMIT, CACHE, OUT, LSC_TREE

set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)

# The submodule pin as recorded by Proton at proton_9.0; its url is ../wine relative to Proton,
# so ValveSoftware/wine.
# Not WINE_COMMIT: that names Dormison's commit for setup-wine-tree.sh, which runs
# this script, and an exported one would send this fetch to the wrong repository.
VALVE_WINE_COMMIT=${VALVE_WINE_COMMIT:-015230dc0f78a543032dea0907f6c97304b25ca3}

CACHE=${CACHE:-$repo/scratch/proton-headers}
OUT=${OUT:-$here/proton-headers}
LSC_TREE=${LSC_TREE:-$repo/build/lsteamclient}

# repo, commit, path in that repo, destination under OUT, sha256.
wanted="wine $VALVE_WINE_COMMIT include/wine/heap.h wine/include/wine/heap.h e51df7c87744e3cbea4cd03d1e08573205252eb275166c0d01f87340991550e7"

if [ "${1:-}" = "--refetch" ]; then
	rm -rf "${CACHE:?}" "${OUT:?}"
elif [ $# -ne 0 ]; then
	echo "==> unknown argument $1" >&2
	exit 1
fi

mkdir -p "$CACHE"

echo "$wanted" | while read -r proj commit path dest want; do
	[ -n "$proj" ] || continue
	cached=$CACHE/$proj-$commit-$(echo "$path" | LC_ALL=C tr '/' '_')

	if [ ! -f "$cached" ]; then
		echo "==> fetching $proj/$path at $(echo "$commit" | LC_ALL=C cut -c1-12)"
		curl -fsSL -o "$cached.part" \
			"https://raw.githubusercontent.com/ValveSoftware/$proj/$commit/$path"
		mv "$cached.part" "$cached"
	fi

	got=$(shasum -a 256 "$cached" | LC_ALL=C awk '{print $1}')
	if [ "$got" != "$want" ]; then
		echo "==> hash mismatch for $proj/$path at $commit" >&2
		echo "    expected $want" >&2
		echo "    got      $got" >&2
		exit 1
	fi

	mkdir -p "$OUT/$(dirname "$dest")"
	cp -f "$cached" "$OUT/$dest"
done

[ -d "$LSC_TREE/steamworks_sdk_142" ] || {
	echo "==> no $LSC_TREE/steamworks_sdk_142, run lsteamclient/fetch.sh first" >&2
	exit 1
}
rm -rf "${OUT:?}/steamworks_sdk_142"
mkdir -p "$OUT"
cp -c -R "$LSC_TREE/steamworks_sdk_142" "$OUT/steamworks_sdk_142" 2>/dev/null \
	|| cp -R "$LSC_TREE/steamworks_sdk_142" "$OUT/steamworks_sdk_142"

echo "==> assembled $OUT"
