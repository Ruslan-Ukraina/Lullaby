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
# With RELEASE_KEY=<path to lullaby-release.key> the bridge is signed with the owner's release key
# instead of the TEST key (the feed still goes only to $WORK/<engine>/feed: nothing is uploaded here;
# release/local-publish.sh does that, and only when told to). FEED_BASE is the URL the app will read
# the bridge from (default: the local feed folder).
# Overridable: CHANNEL, REV, WORK, RELEASE_KEY, FEED_BASE, B1_REUSE (a published bridge's folder: its ntdll pair is used, not rebuilt).
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
# ENGINE: the release's own ntdll.so and libraries decide the install prefix and freetype (bridge/setup-wine-tree.sh)
ENGINE="$eng" WINE_COMMIT="$commit" "$repo/bridge/setup-wine-tree.sh"

if [ -n "${B1_REUSE:-}" ]; then
	# A release whose B1 pair is already published: the compiler of today (mingw gcc) no longer
	# rebuilds the release's unpatched ntdll.dll instruction for instruction, so --check-base would
	# refuse. The published pair (a bridge's ntdll/ folder, the bytes that were played) is used
	# instead: the same patch, the same source, and the hook test below still has to pass.
	say "B1 ntdll.dll pair: the published one from $B1_REUSE"
	[ -f "$B1_REUSE/ntdll/x86_64-ntdll.dll" ] && [ -f "$B1_REUSE/ntdll/i386-ntdll.dll" ] || die "no ntdll pair in $B1_REUSE"
	mkdir -p "$W/ntdll-b1"
	cp "$B1_REUSE/ntdll/x86_64-ntdll.dll" "$B1_REUSE/ntdll/i386-ntdll.dll" "$W/ntdll-b1/"
	python3 -I - "$B1_REUSE/bridge.json" "$W/ntdll-b1" "$repo/patches/engine/lby-discord-ntdllhook" "$version" "$commit" <<'PY'
import hashlib, json, sys
src, out, b1dir, version, commit = sys.argv[1:]
bridge = json.load(open(src))
patch = "0001-ntdll-redirect-steamclient-to-lsteamclient.patch"
files = {}
for item in bridge["ntdll"]:
    got = hashlib.sha256(open(f"{out}/{item['arch']}-ntdll.dll", "rb").read()).hexdigest()
    if got != item["b1"]:
        raise SystemExit(f"{item['arch']}: {got} is not the published {item['b1']}")
    files[item["path"]] = {"clean": item["clean"], "b1": item["b1"]}
patch_sha = hashlib.sha256(open(f"{b1dir}/{patch}", "rb").read()).hexdigest()
json.dump({"engine": version, "commit": commit, "patch": patch, "patchSha256": patch_sha, "files": files},
          open(f"{out}/b1.json", "w"), indent=2)
PY
else
say "B1 ntdll.dll pair"
ENGINE="$eng" OUT="$W/ntdll-b1" "$repo/patches/engine/lby-discord-ntdllhook/build-b1.sh" --check-base
fi

say "engine fixes (patches/engine/build-fixes.sh)"
ENGINE="$eng" OUT="$W/engine-fixes" "$repo/patches/engine/build-fixes.sh"

say "lsteamclient and steam.exe"
"$repo/bridge/lsteamclient/build.sh"
"$repo/bridge/steam-shim/build.sh"
files="$W/bridge-files"
mkdir -p "$files"
cp "$WINE_BUILD/programs/steam.exe/x86_64-windows/steam.exe" "$files/steam.exe"
cp "$WINE_BUILD/dlls/lsteamclient/x86_64-windows/lsteamclient.dll" "$files/x86_64-windows-lsteamclient.dll"
cp "$WINE_BUILD/dlls/lsteamclient/lsteamclient.so" "$files/x86_64-unix-lsteamclient.so"
cp "$WINE_BUILD/dlls/lsteamclient/i386-windows/lsteamclient.dll" "$files/i386-windows-lsteamclient.dll"
# Shipped without debug information (OPTIMIZATION O1); the unstripped copies stay in $W/bridge-debug.
"$repo/bridge/strip-debug.sh" "$files" "$W/bridge-debug"

say "the hook in Wine, x86_64 and i386"
t="$W/bridge-test"
BRIDGE_DIR="$t" "$repo/bridge/fetch-valve.sh" --install
mkdir -p "$t/x86_64-windows" "$t/i386-windows" "$t/x86_64-unix"
cp "$files/x86_64-windows-lsteamclient.dll" "$t/x86_64-windows/lsteamclient.dll"
cp "$files/i386-windows-lsteamclient.dll" "$t/i386-windows/lsteamclient.dll"
cp "$files/x86_64-unix-lsteamclient.so" "$t/x86_64-unix/lsteamclient.so"
cp "$files/x86_64-windows-lsteamclient.dll" "$t/lsteamclient.dll"
cp "$files/x86_64-unix-lsteamclient.so" "$t/lsteamclient.so"
ENGINE="$eng" BRIDGE_DIR="$t" WORK="$W/b1-test" "$repo/patches/engine/lby-discord-ntdllhook/test-b1.sh" "$W/ntdll-b1" | tee "$W/b1-test.log"
# The control: the release's own ntdll.dll must not lead to lsteamclient.
if ENGINE="$eng" BRIDGE_DIR="$t" WORK="$W/b1-test" "$repo/patches/engine/lby-discord-ntdllhook/test-b1.sh" --clean > "$W/b1-clean.log" 2>&1; then
	die "the release's ntdll.dll passed the hook test, so the test proves nothing"
fi

feed="$W/feed"
if [ -n "${RELEASE_KEY:-}" ]; then
	say "package, sign with the release key $RELEASE_KEY"
	[ -f "$RELEASE_KEY" ] || die "no key at $RELEASE_KEY"
	keys=$(dirname "$RELEASE_KEY")
	signkey=$RELEASE_KEY
	pub=$(swift "$here/sign.swift" "$RELEASE_KEY" --public | tail -1)
	[ -n "$pub" ] || die "cannot read the public half of $RELEASE_KEY"
else
	say "package, sign with the TEST key"
	keys="$W/keys"
	pub=$("$here/ci-keys.sh" dry-run "$keys" | sed -n 's/^LB_RELEASE_KEY=//p')
	[ -n "$pub" ] || die "no TEST release key"
	signkey="$keys/release.key"
fi
FEED_BASE=${FEED_BASE:-file://$feed/}
id="bridge-$version-$REV"
rm -rf "${feed:?}"
# Where this Dormison comes from (url, sha256, size), from the manifest the engine was fetched by (or the pinned
# one): the app falls back to it when Dormison's newest release has no bridge yet (DECISIONS P8-17). Without it a
# Mac that installs from scratch could not get this engine once Dormison has published a newer one.
engine_json="$WORK/cache/engine.json"
python3 -I -c 'import json,sys; sys.exit(0 if any(c.get("version") == sys.argv[2] for c in json.load(open(sys.argv[1]))["channels"].values()) else 1)' \
	"$engine_json" "$version" || die "$engine_json does not name $version, so the bridge entry could not record where the engine comes from"
python3 -I "$here/feed.py" bridge-artifact --files-dir "$files" --b1-dir "$W/ntdll-b1" --fixes-dir "$W/engine-fixes" \
	--engine "$version" --commit "$commit" --rev "$REV" --feed "$FEED_BASE" --engine-json "$engine_json" --out "$feed"
python3 -I "$here/feed.py" publish-bridges --repo "$repo/bridge/bridge-manifest.json" \
	--out "$feed/manifest/bridge-manifest.json" "$feed/$id.entry.json"
swift "$here/sign.swift" "$signkey" "$feed/$id/$id.tar.xz" "$feed/manifest/bridge-manifest.json"
"$here/gh-publish.sh" verify "$pub" "$feed/$id/$id.tar.xz"
"$here/gh-publish.sh" verify "$pub" "$feed/manifest/bridge-manifest.json"
printf '%s\n' "$pub" > "$W/public-key.txt"
say "done: $feed (key $pub, nothing uploaded)"
