#!/bin/sh
# Runs tests/trampcheck.c for x86_64 and i386 against a clone of the engine with
# the given ntdll.dll pair, in a throwaway prefix. Nothing of the live engine,
# the user's prefixes or Steam is touched; the clone is an APFS copy-on-write
# copy, so it costs next to no disk.
#
#   test-b1.sh <dir with x86_64-ntdll.dll and i386-ntdll.dll>    expect OK
#   test-b1.sh --clean                                            the release ntdll: expect FAIL
#
# Overridable: ENGINE (default runners/current), BRIDGE_DIR, WORK.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../.." && pwd)
support="$HOME/Library/Application Support/lullaby"
ENGINE=$(cd -P "${ENGINE:-$support/runners/current}" && pwd)
BRIDGE_DIR=${BRIDGE_DIR:-$support/bridge}
WORK=${WORK:-$repo/scratch/b1-test}

die() { echo "==> $*" >&2; exit 1; }
[ $# -eq 1 ] || die "usage: $0 <dir with x86_64-ntdll.dll and i386-ntdll.dll> | --clean"
for t in x86_64-w64-mingw32-gcc i686-w64-mingw32-gcc; do
	command -v "$t" >/dev/null 2>&1 || die "$t not found (brew install mingw-w64)"
done

clone="$WORK/engine"
if [ ! -x "$clone/wine/bin/wine" ]; then
	mkdir -p "$WORK"
	rm -rf "${clone:?}"
	cp -cR "$ENGINE" "$clone"
fi
for a in x86_64 i386; do
	live="$clone/wine/lib/wine/$a-windows/ntdll.dll"
	clean="$ENGINE/wine/lib/wine/$a-windows/ntdll.dll"
	[ -f "$clean.lullaby-orig" ] && clean="$clean.lullaby-orig"
	if [ "$1" = --clean ]; then
		cp -f "$clean" "$live"
	else
		[ -f "$1/$a-ntdll.dll" ] || die "no $1/$a-ntdll.dll"
		cp -f "$1/$a-ntdll.dll" "$live"
	fi
done

bin="$WORK/bin"
mkdir -p "$bin/x86_64" "$bin/i386"
x86_64-w64-mingw32-gcc -O1 -o "$bin/x86_64/trampcheck.exe" "$here/tests/trampcheck.c"
i686-w64-mingw32-gcc -O1 -o "$bin/i386/trampcheck.exe" "$here/tests/trampcheck.c"
# A game finds steamclient next to itself or in the Steam folder; tier0 and vstdlib
# are steamclient64's own imports.
for f in steamclient64.dll tier0_s64.dll vstdlib_s64.dll; do cp -f "$BRIDGE_DIR/$f" "$bin/x86_64/"; done
cp -f "$BRIDGE_DIR/steamclient.dll" "$bin/i386/"

prefix="$WORK/pfx"
rm -rf "${prefix:?}"
mkdir -p "$prefix"
export WINEPREFIX="$prefix" WINEMSYNC=1 WINEDEBUG="err+all,fixme-all,+loaddll"
export WINEDLLPATH="$BRIDGE_DIR"
export WINEDLLOVERRIDES="steamclient=n;steamclient64=n;lsteamclient=b;mscoree,mshtml="
wine="$clone/wine/bin/wine"
server="$clone/wine/bin/wineserver"
"$wine" wineboot --init > "$WORK/wineboot.log" 2>&1 || true

fails=0
for a in x86_64 i386; do
	echo "== $a"
	(cd "$bin/$a" && "$wine" trampcheck.exe) > "$WORK/$a.log" 2>&1 || fails=$((fails + 1))
	grep -a -E "^(OK|FAIL) " "$WORK/$a.log" || { echo "FAIL no output, see $WORK/$a.log"; fails=$((fails + 1)); }
	grep -a "lead to lsteamclient" "$WORK/$a.log" | sed 's/^/   /' || true
done
"$server" -k 2>/dev/null || true
"$server" -w 2>/dev/null || true
echo "==> $fails arch(es) failed"
exit "$fails"
