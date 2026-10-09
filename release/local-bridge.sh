#!/bin/sh
# The dormison-bridge workflow on this Mac: a Steam bridge for a Dormison release, built,
# tested in Wine and signed with the TEST key into a local feed that a dev or test build
# of the app installs from. Nothing is published, and a release build refuses the TEST
# key (docs/RELEASING.md). For a new Dormison before the owner's keys exist (Amendment
# 09.10, docs/ROADMAP.md §13.3а).
#
#   release/local-bridge.sh        the channel's release, bridge rev 1
#
# Everything goes under $WORK/<engine>/: the engine (runners/, checked by
# engine/fetch-dormison.sh), the wine source and build trees, the B1 ntdll.dll pair, the
# bridge files, the hook test logs, keys/ (TEST) and feed/. The trees of the release the
# app runs now (scratch/dormison-src, scratch/dormison-build) are not touched.
# Overridable: CHANNEL, REV, WORK.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
CHANNEL=${CHANNEL:-beta}
REV=${REV:-1}
WORK=${WORK:-$repo/scratch/local-bridge}

say() { echo "==> local-bridge: $*"; }
die() { echo "==> local-bridge: $*" >&2; exit 1; }

say "engine of the $CHANNEL channel"
mkdir -p "$WORK"
CHANNEL="$CHANNEL" RUNNERS="$WORK/runners" CACHE="$WORK/cache" "$repo/engine/fetch-dormison.sh" --activate
eng=$(cd -P "$WORK/runners/current" && pwd)
json() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$eng/engine-info.json" "$1"; }
version=$(json version)
commit=$(json commit)
W="$WORK/$version"
mkdir -p "$W"
say "$version ($commit), bridge rev $REV, in $W"

export WINE_SRC="$W/dormison-src" WINE_BUILD="$W/dormison-build"
say "wine tree at $commit"
WINE_COMMIT="$commit" "$repo/bridge/setup-wine-tree.sh"

say "B1 ntdll.dll pair"
ENGINE="$eng" OUT="$W/ntdll-b1" "$repo/ntdll-patch/b1/build-b1.sh" --check-base

say "lsteamclient and steam.exe"
"$repo/lsteamclient/build.sh"
"$repo/steam-shim/build.sh"
files="$W/bridge-files"
mkdir -p "$files"
cp "$WINE_BUILD/programs/steam.exe/x86_64-windows/steam.exe" "$files/steam.exe"
cp "$WINE_BUILD/dlls/lsteamclient/x86_64-windows/lsteamclient.dll" "$files/x86_64-windows-lsteamclient.dll"
cp "$WINE_BUILD/dlls/lsteamclient/lsteamclient.so" "$files/x86_64-unix-lsteamclient.so"
cp "$WINE_BUILD/dlls/lsteamclient/i386-windows/lsteamclient.dll" "$files/i386-windows-lsteamclient.dll"

say "the hook in Wine, x86_64 and i386"
t="$W/bridge-test"
BRIDGE_DIR="$t" "$repo/bridge/fetch-valve.sh" --install
mkdir -p "$t/x86_64-windows" "$t/i386-windows" "$t/x86_64-unix"
cp "$files/x86_64-windows-lsteamclient.dll" "$t/x86_64-windows/lsteamclient.dll"
cp "$files/i386-windows-lsteamclient.dll" "$t/i386-windows/lsteamclient.dll"
cp "$files/x86_64-unix-lsteamclient.so" "$t/x86_64-unix/lsteamclient.so"
cp "$files/x86_64-windows-lsteamclient.dll" "$t/lsteamclient.dll"
cp "$files/x86_64-unix-lsteamclient.so" "$t/lsteamclient.so"
ENGINE="$eng" BRIDGE_DIR="$t" WORK="$W/b1-test" "$repo/ntdll-patch/b1/test-b1.sh" "$W/ntdll-b1" | tee "$W/b1-test.log"
# The control: the release's own ntdll.dll must not lead to lsteamclient.
if ENGINE="$eng" BRIDGE_DIR="$t" WORK="$W/b1-test" "$repo/ntdll-patch/b1/test-b1.sh" --clean > "$W/b1-clean.log" 2>&1; then
	die "the release's ntdll.dll passed the hook test, so the test proves nothing"
fi

say "package, sign with the TEST key"
keys="$W/keys"
pub=$("$here/ci-keys.sh" dry-run "$keys" | sed -n 's/^NP_RELEASE_KEY=//p')
[ -n "$pub" ] || die "no TEST release key"
feed="$W/feed"
id="bridge-$version-$REV"
rm -rf "${feed:?}"
python3 -I "$here/feed.py" bridge-artifact --files-dir "$files" --b1-dir "$W/ntdll-b1" \
	--engine "$version" --commit "$commit" --rev "$REV" --feed "file://$feed/" --out "$feed"
python3 -I "$here/feed.py" publish-bridges --repo "$repo/bridge/bridge-manifest.json" \
	--out "$feed/manifest/bridge-manifest.json" "$feed/$id.entry.json"
swift "$here/sign.swift" "$keys/release.key" "$feed/$id/$id.tar.xz" "$feed/manifest/bridge-manifest.json"
"$here/gh-publish.sh" verify "$pub" "$feed/$id/$id.tar.xz"
"$here/gh-publish.sh" verify "$pub" "$feed/manifest/bridge-manifest.json"
printf '%s\n' "$pub" > "$W/test-public-key.txt"
say "done: $feed (TEST key $pub)"
