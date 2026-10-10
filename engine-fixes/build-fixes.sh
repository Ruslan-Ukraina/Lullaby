#!/bin/sh
# Engine fixes: rebuilds single files of a Dormison release (a unix module such as
# winemac.so) from the commit the release was built from, with NotProton's patches in
# engine-fixes/patches/<file>/*.patch, applied in order. The bridge carries them into the
# engine next to the B1 ntdll.dll pair (BridgeRelease.engineFiles); the release's file
# stays beside each as <file>.lullaby-orig.
#
# Every file is first rebuilt without the patches and its code must match the release's
# instruction for instruction (same compiler, same flags): only then is the patched build
# the release plus the patches and nothing else. Measured for winemac.so of dormison-b2:
# 126067 instructions, no difference.
#
#   build-fixes.sh       build every file that has patches into scratch/engine-fixes/<engine>/
#
# Needs the wine tree bridge/setup-wine-tree.sh makes. Overridable: ENGINE, WINE_SRC,
# WINE_BUILD, OUT. Writes fixes.json: per engine path the release's sha256 (clean), the
# patched file's (patched) and the patches.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
support="$HOME/Library/Application Support/lullaby"
ENGINE=$(cd -P "${ENGINE:-$support/runners/current}" && pwd)
WINE_SRC=${WINE_SRC:-$repo/scratch/dormison-src}
WINE_BUILD=${WINE_BUILD:-$repo/scratch/dormison-build}
PATH="/opt/homebrew/bin:/opt/homebrew/opt/bison/bin:$PATH"
export PATH

die() { echo "==> $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
json() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$ENGINE/engine-info.json" "$1"; }

[ -f "$ENGINE/engine-info.json" ] || die "no engine-info.json in $ENGINE"
version=$(json version)
commit=$(json commit)
OUT=${OUT:-$repo/scratch/engine-fixes/$version}
mkdir -p "$OUT"
[ -d "$WINE_BUILD/dlls" ] || die "no wine build tree at $WINE_BUILD, run bridge/setup-wine-tree.sh"
head=$(git -C "$WINE_SRC" rev-parse HEAD)
[ "$head" = "$commit" ] || git -C "$WINE_SRC" merge-base --is-ancestor "$commit" "$head" \
	|| die "$WINE_SRC is at $head, which is not built on the engine's $commit"

# What each file is: its place in the engine, its make target, and what must be built first.
engine_path() {
	case "$1" in
		winemac.so) echo wine/lib/wine/x86_64-unix/winemac.so ;;
		ntdll.so) echo wine/lib/wine/x86_64-unix/ntdll.so ;;
		*) die "no recipe for $1" ;;
	esac
}
make_target() {
	case "$1" in
		winemac.so) echo dlls/winemac.drv/winemac.so ;;
		ntdll.so) echo dlls/ntdll/ntdll.so ;;
	esac
}
prepare() {
	case "$1" in
		# The driver's Swift half is a static archive wine's makefiles do not build.
		winemac.so) make -C "$WINE_SRC/dlls/winemac.drv/swift" > "$OUT/$1-swift.log" 2>&1 \
			|| die "$1: the Swift archive did not build, see $OUT/$1-swift.log" ;;
	esac
}

# The release's file, from the engine's own manifest: in place, or kept aside by a fix.
clean_of() {
	rel=$(engine_path "$1")
	want=$(python3 -I - "$ENGINE/engine-manifest.json" "$rel" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
print(next(c["sha256"] for c in m["components"] if c["path"] == sys.argv[2]))
PY
)
	for f in "$ENGINE/$rel.lullaby-orig" "$ENGINE/$rel"; do
		[ -f "$f" ] && [ "$(sha "$f")" = "$want" ] && { echo "$f"; return 0; }
	done
	die "no clean $rel in $ENGINE (want $want)"
}

normalized_code() {
	objdump -d --no-show-raw-insn "$1" | sed -n '3,$p' \
		| sed -E 's/^ *[0-9a-f]+://; s/0x[0-9a-f]+/X/g; s/[0-9a-f]{6,}/X/g; s/<[^>]*>//g'
}

# make 3.81 compares whole seconds: the objects of the patched sources go before each build.
build() {
	for p in "$2"/*.patch; do
		sed -n 's|^+++ b/\(.*\)\.[cm]\([[:space:]].*\)*$|\1.o|p' "$p" | while read -r obj; do
			rm -f "${WINE_BUILD:?}/$obj"
		done
	done
	make -C "$WINE_BUILD" -j"$(sysctl -n hw.ncpu)" "$(make_target "$1")" > "$OUT/$1-build.log" 2>&1 \
		|| { tail -20 "$OUT/$1-build.log" >&2; die "$1 build failed, see $OUT/$1-build.log"; }
}

applied() { git -C "$WINE_SRC" apply --reverse --check "$1" 2>/dev/null; }

entries=""
for dir in "$here"/patches/*/; do
	name=$(basename "$dir")
	dir=${dir%/}
	ls "$dir"/*.patch > /dev/null 2>&1 || continue
	rel=$(engine_path "$name")
	built="$WINE_BUILD/$(make_target "$name")"
	clean=$(clean_of "$name")
	prepare "$name"

	# Unpatched first: newest patch off first.
	# shellcheck disable=SC2045 # our own patch names, without spaces
	for p in $(ls -r "$dir"/*.patch); do
		if applied "$p"; then git -C "$WINE_SRC" apply --reverse "$p"; fi
	done
	echo "==> $name: building the release's source to compare with $version"
	build "$name" "$dir"
	normalized_code "$built" > "$OUT/$name-base.dis"
	normalized_code "$clean" > "$OUT/$name-release.dis"
	cmp -s "$OUT/$name-base.dis" "$OUT/$name-release.dis" \
		|| die "$name: the rebuilt unpatched code differs from the release's; compiler or flags drifted (diff $OUT/$name-base.dis $OUT/$name-release.dis)"
	echo "==> $name: the rebuilt unpatched code is the release's, instruction for instruction"

	patches=""
	for p in "$dir"/*.patch; do
		git -C "$WINE_SRC" apply --check "$p" || die "$(basename "$p") does not apply to $commit"
		git -C "$WINE_SRC" apply "$p"
		patches="$patches${patches:+, }{ \"name\": \"$(basename "$p")\", \"sha256\": \"$(sha "$p")\" }"
	done
	echo "==> $name: building with $(find "$dir" -name '*.patch' | wc -l | tr -d ' ') patch(es)"
	build "$name" "$dir"
	cp -f "$built" "$OUT/$name"
	normalized_code "$OUT/$name" | cmp -s - "$OUT/$name-release.dis" 2>/dev/null \
		&& die "$name: the patched build has the release's code, the patches changed nothing"
	# Back to the release's source, so the tree builds the B1 ntdll.dll and the bridge as before.
	# shellcheck disable=SC2045 # as above
	for p in $(ls -r "$dir"/*.patch); do git -C "$WINE_SRC" apply --reverse "$p"; done

	entries="$entries${entries:+,
}    \"$rel\": { \"clean\": \"$(sha "$clean")\", \"patched\": \"$(sha "$OUT/$name")\", \"file\": \"$name\", \"patches\": [ $patches ] }"
	echo "==> $OUT/$name $(sha "$OUT/$name")"
done

cat > "$OUT/fixes.json" <<JSON
{
  "engine": "$version",
  "commit": "$commit",
  "files": {
$entries
  }
}
JSON
echo "==> $OUT/fixes.json"
