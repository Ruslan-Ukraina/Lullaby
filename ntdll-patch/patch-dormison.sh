#!/bin/sh
# Patch the x86_64 ntdll.dll of an unpacked Dormison engine so that loading
# steamclient64.dll routes its exports to lsteamclient.dll (route B2 in
# docs/DECISIONS.md, the same detour the CrossOver build used).
#
#   ntdll-patch/patch-dormison.sh [engine dir]    default: runners/current
#
# The clean ntdll.dll is recognised by the sha256 engine-manifest.json gives
# for it, not by a hash pinned here, so the script serves the next release as
# long as resolve.py still finds the hook. Steps:
#   1. resolve.py and build.sh make the payload for this exact binary;
#   2. apply.py writes a patched copy and verify.py checks it statically;
#   3. the copy goes in place with the clean file kept beside it as
#      ntdll.dll.notproton-orig, and a copy goes to the bridge, which the run
#      script compares the engine against.
# Dormison loads the 64 bit ntdll.dll from its own tree only (load_ntdll in
# dlls/ntdll/unix/loader.c), so WINEDLLPATH_PREPEND cannot carry it and the
# file in the tree is what has to change.
# i386 is not patched: its code cave is 368 bytes for a 1376 byte payload
# (docs/RISKS.md R1, Phase 3).
#
# Overridable: RUNNERS, BRIDGE_DIR, OUT
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
RUNNERS=${RUNNERS:-$HOME/Library/Application Support/notproton/runners}
BRIDGE_DIR=${BRIDGE_DIR:-$HOME/Library/Application Support/notproton/bridge}

die() { echo "==> $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

engine=$(cd -P "${1:-$RUNNERS/current}" && pwd) || die "no engine at ${1:-$RUNNERS/current}"
rel=wine/lib/wine/x86_64-windows/ntdll.dll
live=$engine/$rel
orig=$live.notproton-orig
[ -f "$engine/engine-manifest.json" ] || die "$engine has no engine-manifest.json"

version=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' \
	"$engine/engine-manifest.json")
want_clean=$(python3 - "$engine/engine-manifest.json" "$rel" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
print(next(c["sha256"] for c in m["components"] if c["path"] == sys.argv[2]))
PY
)

if [ -f "$orig" ] && [ "$(sha "$orig")" = "$want_clean" ]; then
	clean=$orig
elif [ "$(sha "$live")" = "$want_clean" ]; then
	clean=$live
else
	die "neither $rel nor its .notproton-orig is the clean $version file ($want_clean)"
fi
echo "==> $version: clean x86_64 ntdll.dll $want_clean"

OUT=${OUT:-$repo/scratch/ntdll/$version}
mkdir -p "$OUT"
cp -p "$clean" "$OUT/ntdll.dll.clean"

# The subshell keeps build.sh's cd and its outputs to ntdll-patch.
(cd "$here" && ./build.sh "$OUT/ntdll.dll.clean" dormison) || die "building the payload failed"
cp -f "$here/detour2-dormison.bin" "$OUT/detour2-dormison.bin"
python3 "$here/apply.py" "$OUT/ntdll.dll.clean" "$OUT/ntdll.dll" "$OUT/detour2-dormison.bin"
python3 "$here/verify.py" "$OUT/ntdll.dll.clean" "$OUT/ntdll.dll" "$OUT/detour2-dormison.bin" \
	|| die "the patched copy failed verification, nothing installed"
patched_sha=$(sha "$OUT/ntdll.dll")

install_atomically() {
	from=$1 to=$2
	mkdir -p "$(dirname "$to")"
	cp -f "$from" "$to.new"
	mv -f "$to.new" "$to"
	[ "$(sha "$to")" = "$(sha "$from")" ] || die "install verify failed: $to"
}

if [ "$(sha "$live")" = "$patched_sha" ]; then
	echo "==> $live is already the patched copy"
else
	[ -f "$orig" ] || cp -p "$live" "$orig"
	install_atomically "$OUT/ntdll.dll" "$live"
	echo "==> installed $live (clean copy kept as ${orig##*/})"
fi
install_atomically "$OUT/ntdll.dll" "$BRIDGE_DIR/wine/x86_64-windows/ntdll.dll"
echo "==> bridge copy $BRIDGE_DIR/wine/x86_64-windows/ntdll.dll"
echo "==> done: x86_64 ntdll.dll $want_clean -> $patched_sha"
