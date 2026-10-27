#!/bin/sh
# Engine fixes: rebuilds single files of a Dormison release (a unix module such as
# winemac.so) from the commit the release was built from, with Lullaby's patches in
# patches/engine/patches/<file>/*.patch, applied in order. The bridge carries them into the
# engine next to the B1 ntdll.dll pair (BridgeRelease.engineFiles); the release's file
# stays beside each as <file>.lullaby-orig.
#
# Every file is first rebuilt without the patches and its code must match the release's
# instruction for instruction (same compiler, same flags): only then is the patched build
# the release plus the patches and nothing else. Measured for winemac.so of dormison-b2:
# 126067 instructions, no difference.
#
#   build-fixes.sh       build every file that has patches into scratch/patches/engine/<engine>/
#
# Needs the wine tree bridge/setup-wine-tree.sh makes. Overridable: ENGINE, WINE_SRC,
# WINE_BUILD, OUT. Writes fixes.json: per engine path the release's sha256 (clean), the
# patched file's (patched) and the patches.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
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
OUT=${OUT:-$repo/scratch/patches/engine/$version}
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
		win32u.so) echo wine/lib/wine/x86_64-unix/win32u.so ;;
		winecoreaudio.so) echo wine/lib/wine/x86_64-unix/winecoreaudio.so ;;
		*) die "no recipe for $1" ;;
	esac
}
make_target() {
	case "$1" in
		winemac.so) echo dlls/winemac.drv/winemac.so ;;
		ntdll.so) echo dlls/ntdll/ntdll.so ;;
		win32u.so) echo dlls/win32u/win32u.so ;;
		winecoreaudio.so) echo dlls/winecoreaudio.drv/winecoreaudio.so ;;
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

# The release's files carry the search paths its libraries are found by (LC_RPATH: @loader_path/../lib and
# @loader_path/../../ for libfreetype, libvulkan and the rest in wine/lib) and an ad-hoc signature; a plain
# build has only @loader_path/, so a rebuilt win32u.so dlopens nothing from wine/lib (r5-5 to r5-7 before the
# fix: no fonts, no Vulkan). The paths are given to the linker (install_name_tool has no header room for them),
# and the result has to carry exactly the release's, in its order.
rpaths() { otool -l "$1" | awk '/cmd LC_RPATH/ {r=1} r && $1 == "path" {print $2; r=0}'; }
rpath_flags() { # release-file: the paths the plain link does not add itself
	rpaths "$1" | grep -vxF '@loader_path/' | sed 's|^|-Wl,-rpath,|' | tr '\n' ' '
}
finish_like_release() { # file release-file
	rpaths "$1" > "$1.rpaths"
	rpaths "$2" | cmp -s - "$1.rpaths" || die "$1: rpaths differ from the release's file ($(rpaths "$1" | tr '\n' ' '))"
	rm -f "$1.rpaths"
	codesign -f -s - "$1" 2> /dev/null
}

# Whitespace is collapsed: objdump pads its "## symbol" comments to the width of the displacement, which moves
# with the length of the source path (a longer __FILE__ shifts rodata) and says nothing about the code.
# The file names a build dlopens (libfreetype.6.dylib, libvulkan.1.4.357.dylib) are data, not code, so the
# instruction comparison below cannot see a wrong one. A configure that stored a line of otool output
# there (r5-5 and r5-6 shipped that: no fonts, no Vulkan) is caught by comparing these strings.
library_names() { strings -a "$1" | grep -E '^lib[A-Za-z0-9_+.-]+\.(dylib|so)$' | sort -u; }

normalized_code() {
	objdump -d --no-show-raw-insn "$1" | sed -n '3,$p' \
		| sed -E 's/^ *[0-9a-f]+://; s/0x[0-9a-f]+/X/g; s/[0-9a-f]{6,}/X/g; s/<[^>]*>//g; s/[[:space:]]+/ /g'
}

# make 3.81 compares whole seconds: the objects of the patched sources go before each build.
build() {
	for p in "$2"/*.patch; do
		sed -n 's|^+++ b/\(.*\)\.[cm]\([[:space:]].*\)*$|\1.o|p' "$p" | while read -r obj; do
			rm -f "${WINE_BUILD:?}/$obj"
		done
	done
	rm -f "${WINE_BUILD:?}/$(make_target "$1")" # relinked every time, with the release's rpaths
	make -C "$WINE_BUILD" -j"$(sysctl -n hw.ncpu)" LDFLAGS="$(sed -n 's/^LDFLAGS = //p' "$WINE_BUILD/Makefile") $(rpath_flags "$(clean_of "$1")")" \
		"$(make_target "$1")" > "$OUT/$1-build.log" 2>&1 \
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
	if ! cmp -s "$OUT/$name-base.dis" "$OUT/$name-release.dis"; then
		# The first differences, so that a CI log says what drifted.
		diff "$OUT/$name-base.dis" "$OUT/$name-release.dis" | head -40 >&2 || true
		nm "$built" | awk '{print $NF}' | sort -u > "$OUT/$name-base.syms"
		nm "$clean" | awk '{print $NF}' | sort -u > "$OUT/$name-release.syms"
		echo "==> symbols only in the release:" >&2
		comm -13 "$OUT/$name-base.syms" "$OUT/$name-release.syms" | head -20 >&2 || true
		echo "==> symbols only in the rebuild:" >&2
		comm -23 "$OUT/$name-base.syms" "$OUT/$name-release.syms" | head -20 >&2 || true
		die "$name: the rebuilt unpatched code differs from the release's; compiler or flags drifted (diff $OUT/$name-base.dis $OUT/$name-release.dis)"
	fi
	echo "==> $name: the rebuilt unpatched code is the release's, instruction for instruction"
	library_names "$built" > "$OUT/$name-base.libs"
	library_names "$clean" > "$OUT/$name-release.libs"
	if ! cmp -s "$OUT/$name-base.libs" "$OUT/$name-release.libs" || strings -a "$built" | grep -q 'compatibility version'; then
		diff "$OUT/$name-base.libs" "$OUT/$name-release.libs" >&2 || true
		die "$name: the rebuilt unpatched file names other libraries than the release's (configure SONAME probe, see bridge/setup-wine-tree.sh)"
	fi
	echo "==> $name: the library names it loads are the release's"

	patches=""
	for p in "$dir"/*.patch; do
		git -C "$WINE_SRC" apply --check "$p" || die "$(basename "$p") does not apply to $commit"
		git -C "$WINE_SRC" apply "$p"
		patches="$patches${patches:+, }{ \"name\": \"$(basename "$p")\", \"sha256\": \"$(sha "$p")\" }"
	done
	echo "==> $name: building with $(find "$dir" -name '*.patch' | wc -l | tr -d ' ') patch(es)"
	build "$name" "$dir"
	cp -f "$built" "$OUT/$name"
	finish_like_release "$OUT/$name" "$clean"
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
