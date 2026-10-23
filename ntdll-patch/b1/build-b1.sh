#!/bin/sh
# B1: builds Dormison's PE ntdll.dll, x86_64 and i386, from the commit the engine
# release was built from, with the steamclient -> lsteamclient hook in loader.c
# (0001-ntdll-redirect-steamclient-to-lsteamclient.patch). Only the PE half is
# rebuilt; ntdll.so, the unix interface and the server protocol stay the release's.
#
#   build-b1.sh                 build into scratch/ntdll-b1/<engine version>/
#   build-b1.sh --check-base    first rebuild the unpatched source and require its code to
#                               match the release's ntdll.dll (same compiler, same flags)
#
# Needs the wine tree bridge/setup-wine-tree.sh makes (scratch/dormison-src and
# scratch/dormison-build). Overridable: ENGINE, WINE_SRC, WINE_BUILD, OUT.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
support="$HOME/Library/Application Support/lullaby"
ENGINE=$(cd -P "${ENGINE:-$support/runners/current}" && pwd)
WINE_SRC=${WINE_SRC:-$repo/scratch/dormison-src}
WINE_BUILD=${WINE_BUILD:-$repo/scratch/dormison-build}
PATCH="$here/0001-ntdll-redirect-steamclient-to-lsteamclient.patch"
PATH="/opt/homebrew/bin:/opt/homebrew/opt/bison/bin:$PATH"
export PATH

die() { echo "==> $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
strip_for() { case "$1" in x86_64) echo x86_64-w64-mingw32-strip ;; i386) echo i686-w64-mingw32-strip ;; esac; }
objdump_for() { case "$1" in x86_64) echo x86_64-w64-mingw32-objdump ;; i386) echo i686-w64-mingw32-objdump ;; esac; }

check_base=0
[ "${1:-}" = --check-base ] && check_base=1

[ -f "$ENGINE/engine-info.json" ] || die "no engine-info.json in $ENGINE"
version=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$ENGINE/engine-info.json")
commit=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["commit"])' "$ENGINE/engine-info.json")
OUT=${OUT:-$repo/scratch/ntdll-b1/$version}
mkdir -p "$OUT"

[ -d "$WINE_BUILD/dlls/ntdll" ] || die "no wine build tree at $WINE_BUILD, run bridge/setup-wine-tree.sh"
# The release's commit itself, or the fork's lullaby/b1-steamclient branch on top of
# it, whose only change is dlls/ntdll/loader.c.
head=$(git -C "$WINE_SRC" rev-parse HEAD)
if [ "$head" != "$commit" ]; then
	git -C "$WINE_SRC" merge-base --is-ancestor "$commit" "$head" \
		|| die "$WINE_SRC is at $head, which is not built on the engine's $commit"
	changed=$(git -C "$WINE_SRC" diff --name-only "$commit" "$head")
	[ "$changed" = dlls/ntdll/loader.c ] \
		|| die "$WINE_SRC at $head changes more than dlls/ntdll/loader.c over $commit: $changed"
fi

# The clean ntdll.dll of the release, from the engine's own manifest.
clean_of() {
	rel="wine/lib/wine/$1-windows/ntdll.dll"
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

normalized_code() { # arch file -> disassembly without addresses
	"$(objdump_for "$1")" -d --no-show-raw-insn "$2" | sed -n '3,$p' \
		| sed -E 's/^ *[0-9a-f]+://; s/0x[0-9a-f]+/X/g; s/[0-9a-f]{6,}/X/g; s/<[^>]*>//g'
}

build() {
	# The patch touches loader.c alone. make 3.81 compares whole seconds, so a patch applied
	# in the second the previous build finished looks older than its object, and the build
	# would keep the other variant (found 09.10 on a rebuild of a tree that was already built).
	rm -f "$WINE_BUILD/dlls/ntdll/x86_64-windows/loader.o" "$WINE_BUILD/dlls/ntdll/i386-windows/loader.o"
	make -C "$WINE_BUILD" -j"$(sysctl -n hw.ncpu)" \
		dlls/ntdll/x86_64-windows/ntdll.dll dlls/ntdll/i386-windows/ntdll.dll > "$OUT/build.log" 2>&1 \
		|| { tail -20 "$OUT/build.log" >&2; die "ntdll build failed, see $OUT/build.log"; }
}

applied() { git -C "$WINE_SRC" apply --reverse --check "$PATCH" 2>/dev/null; }

if [ "$check_base" = 1 ]; then
	if applied; then git -C "$WINE_SRC" apply --reverse "$PATCH"; fi
	echo "==> building the unpatched ntdll.dll to compare with $version"
	build
	for a in x86_64 i386; do
		"$(strip_for $a)" -o "$OUT/$a-base.dll" "$WINE_BUILD/dlls/ntdll/$a-windows/ntdll.dll"
		if normalized_code $a "$OUT/$a-base.dll" | cmp -s - "$OUT/$a-release.dis" 2>/dev/null \
			|| { normalized_code $a "$(clean_of $a)" > "$OUT/$a-release.dis"
			     normalized_code $a "$OUT/$a-base.dll" | cmp -s - "$OUT/$a-release.dis"; }; then
			echo "==> $a: the rebuilt unpatched code is the release's, instruction for instruction"
		else
			die "$a: the rebuilt unpatched ntdll.dll differs from the release in code; compiler or flags drifted"
		fi
	done
fi

if ! applied; then
	git -C "$WINE_SRC" apply --check "$PATCH" || die "the patch does not apply to $commit"
	git -C "$WINE_SRC" apply "$PATCH"
fi
echo "==> building the B1 ntdll.dll for $version ($commit)"
build
for a in x86_64 i386; do
	"$(strip_for $a)" -o "$OUT/$a-ntdll.dll" "$WINE_BUILD/dlls/ntdll/$a-windows/ntdll.dll"
	strings -a "$OUT/$a-ntdll.dll" | grep -q "lead to lsteamclient" || die "$a: the hook is not in the build"
done

cat > "$OUT/b1.json" <<JSON
{
  "engine": "$version",
  "commit": "$commit",
  "patch": "$(basename "$PATCH")",
  "patchSha256": "$(sha "$PATCH")",
  "files": {
    "wine/lib/wine/x86_64-windows/ntdll.dll": { "clean": "$(sha "$(clean_of x86_64)")", "b1": "$(sha "$OUT/x86_64-ntdll.dll")" },
    "wine/lib/wine/i386-windows/ntdll.dll": { "clean": "$(sha "$(clean_of i386)")", "b1": "$(sha "$OUT/i386-ntdll.dll")" }
  }
}
JSON
echo "==> $OUT/x86_64-ntdll.dll $(sha "$OUT/x86_64-ntdll.dll")"
echo "==> $OUT/i386-ntdll.dll $(sha "$OUT/i386-ntdll.dll")"
