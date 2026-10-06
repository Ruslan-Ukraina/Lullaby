#!/bin/sh
# Puts the B1 ntdll.dll pair build-b1.sh made into the engine and the bridge.
#
#   install-b1.sh              runners/current
#   install-b1.sh --restore    put the release's clean files back (B1 off, B2 off)
#
# Next to each engine file stay the release's clean copy (.notproton-orig) and,
# for x86_64, the spike's B2 binary patch (.notproton-b2) if it was there. Files
# are switched by rename, and not while a game of ours runs.
# Overridable: ENGINE, BRIDGE_DIR, B1_DIR.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
support="$HOME/Library/Application Support/notproton"
ENGINE=$(cd -P "${ENGINE:-$support/runners/current}" && pwd)
BRIDGE_DIR=${BRIDGE_DIR:-$support/bridge}

die() { echo "==> $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

restore=0
[ "${1:-}" = --restore ] && restore=1

version=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$ENGINE/engine-info.json")
B1_DIR=${B1_DIR:-$repo/scratch/ntdll-b1/$version}

if pgrep -f "notproton/(runners|launchers)/" >/dev/null 2>&1; then
	die "a game of ours is running (pgrep -f 'notproton/(runners|launchers)/'), quit it first"
fi

clean_sha() {
	python3 -I - "$ENGINE/engine-manifest.json" "$1" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
print(next(c["sha256"] for c in m["components"] if c["path"] == sys.argv[2]))
PY
}

install_atomically() {
	cp -f "$1" "$2.new"
	mv -f "$2.new" "$2"
	[ "$(sha "$2")" = "$(sha "$1")" ] || die "install verify failed: $2"
}

for a in x86_64 i386; do
	rel="wine/lib/wine/$a-windows/ntdll.dll"
	live="$ENGINE/$rel"
	orig="$live.notproton-orig"
	want=$(clean_sha "$rel")

	# The release's file, kept once and never overwritten.
	if [ ! -f "$orig" ]; then
		[ "$(sha "$live")" = "$want" ] || die "$rel is not the release's file and there is no .notproton-orig"
		cp -p "$live" "$orig"
	fi
	[ "$(sha "$orig")" = "$want" ] || die "$orig is not the release's $rel ($want)"

	if [ "$restore" = 1 ]; then
		install_atomically "$orig" "$live"
		rm -f "${BRIDGE_DIR:?}/wine/$a-windows/ntdll.dll"
		echo "==> $a: the release's ntdll.dll is back"
		continue
	fi

	new="$B1_DIR/$a-ntdll.dll"
	[ -f "$new" ] || die "no $new, run build-b1.sh"
	strings -a "$new" | grep -q "lead to lsteamclient" || die "$new has no B1 hook"
	cur=$(sha "$live")
	if [ "$cur" = "$(sha "$new")" ]; then
		echo "==> $a: already B1"
	else
		if [ "$cur" != "$want" ] && [ ! -f "$live.notproton-b2" ]; then
			cp -p "$live" "$live.notproton-b2"
			echo "==> $a: the previous patched file is kept as ntdll.dll.notproton-b2"
		fi
		install_atomically "$new" "$live"
		echo "==> $a: installed B1 $(sha "$new")"
	fi
	mkdir -p "$BRIDGE_DIR/wine/$a-windows"
	install_atomically "$new" "$BRIDGE_DIR/wine/$a-windows/ntdll.dll"
done
[ "$restore" = 1 ] || cp -f "$B1_DIR/b1.json" "$BRIDGE_DIR/wine/b1.json"
echo "==> done"
