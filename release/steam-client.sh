#!/bin/sh
# Fetches the macOS Steam client of one channel, the way its updater would, and lays
# it out where anchorcheck and sigslice look for it (Phase 6, docs/BACKLOG.md 22).
#
#   release/steam-client.sh <stable|publicbeta> <work dir>
#
# Writes <work>/build (the client build number) and <work>/home, a HOME whose
# Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS holds the
# client's dylibs. Nothing is trusted on the way:
#   - each package's sha256 must be the one Valve's manifest gives (the manifest
#     comes over https from Valve's CDN, the same source Steam's own updater reads);
#   - steamclient.dylib and steamui.dylib must carry Valve's code signature
#     (team MXGJJ98X76), as the shipped client does;
#   - steamclient.dylib must still have its x86_64 half: lsteamclient.so loads it
#     into the game's x86_64 Wine process (docs/BACKLOG.md 24). Exit 4 says it is gone.
# Exit 0 done, 1 failure, 4 no x86_64 half.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
CHANNEL=${1:?usage: steam-client.sh <stable|publicbeta> <work dir>}
WORK=${2:?usage: steam-client.sh <stable|publicbeta> <work dir>}
VALVE_TEAM=MXGJJ98X76
# What steamclient.dylib and steamui.dylib need to load (otool -L, 2026-10-07).
PACKAGES="bins_osx bins_client_osx bins_misc_osx bins_codecs_osx breakpad_osx"
# Akamai first; the rest serve the same bytes (valve-packages.manifest).
BASES=$(awk '$1 == "base" { printf "%s ", $2 }' "$repo/app/Sources/LullabyApp/Resources/valve-packages.manifest")

die() { echo "==> steam-client: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

case "$CHANNEL" in
	stable) name=steam_client_osx ;;
	publicbeta) name=steam_client_publicbeta_osx ;;
	*) die "channel is '$CHANNEL', expected stable or publicbeta" ;;
esac

fetch() { # file -> $WORK/dl/file, from the first base that has it
	for base in $BASES; do
		if curl -fsSL --retry 3 -o "$WORK/dl/$1.part" "$base/$1"; then
			mv -f "$WORK/dl/$1.part" "$WORK/dl/$1"
			return 0
		fi
	done
	rm -f "$WORK/dl/$1.part"
	return 1
}

mkdir -p "$WORK/dl"
fetch "$name" || die "cannot fetch Valve's $name"
python3 -I "$here/feed.py" valve-manifest "$WORK/dl/$name" > "$WORK/manifest.json" \
	|| die "cannot read Valve's $name"
build=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$WORK/manifest.json")
echo "==> $CHANNEL: Steam client build $build"

macos="$WORK/home/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS"
rm -rf "${WORK:?}/home"
mkdir -p "$macos"
for pkg in $PACKAGES; do
	file=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["packages"][sys.argv[2]]["file"])' \
		"$WORK/manifest.json" "$pkg") || die "$name lists no $pkg"
	want=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["packages"][sys.argv[2]]["sha2"])' \
		"$WORK/manifest.json" "$pkg")
	if [ ! -f "$WORK/dl/$file" ] || [ "$(sha "$WORK/dl/$file")" != "$want" ]; then
		fetch "$file" || die "cannot fetch $file"
	fi
	got=$(sha "$WORK/dl/$file")
	[ "$got" = "$want" ] || die "$file: sha256 $got, Valve's manifest says $want"
	unzip -q -o "$WORK/dl/$file" -d "$macos" || die "$file does not unpack"
	echo "==> $pkg ok ($file)"
done

# Each half on its own: codesign on macOS 27 reports "An internal error has occurred"
# for the universal steamclient.dylib as a whole, while every slice verifies.
for lib in steamclient.dylib steamui.dylib; do
	[ -f "$macos/$lib" ] || die "no $lib in the packages"
	for arch in $(lipo -archs "$macos/$lib"); do
		codesign --verify --strict --arch "$arch" "$macos/$lib" 2>/dev/null \
			|| die "$lib ($arch): Valve's code signature does not verify"
		team=$(codesign -dv --arch "$arch" "$macos/$lib" 2>&1 | sed -n 's/^TeamIdentifier=//p')
		[ "$team" = "$VALVE_TEAM" ] || die "$lib ($arch) is signed by team '$team', not Valve's $VALVE_TEAM"
	done
done
archs=$(lipo -archs "$macos/steamclient.dylib")
echo "==> steamclient.dylib: $archs, signed by Valve ($VALVE_TEAM)"
echo "$build" > "$WORK/build"
case " $archs " in
	*" arm64 "*) ;;
	*) die "steamclient.dylib has no arm64 half ($archs); the Lullaby dylib is arm64 only" ;;
esac
case " $archs " in
	*" x86_64 "*) ;;
	*) echo "==> steamclient.dylib has no x86_64 half: Steamworks in games will break (BACKLOG 24)" >&2; exit 4 ;;
esac
