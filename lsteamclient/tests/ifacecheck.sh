#!/bin/sh
# Runs tests/ifacecheck.c, x86_64 and i386, against the running Steam client in the
# throwaway prefix ntdll-patch/b1/test-b1.sh made (run that first). Needs Steam open
# and logged in; no game is started and no app id is set.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
support="$HOME/Library/Application Support/lullaby"
BRIDGE_DIR=${BRIDGE_DIR:-$support/bridge}
WORK=${WORK:-$repo/scratch/b1-test}
die() { echo "==> $*" >&2; exit 1; }
[ -x "$WORK/engine/wine/bin/wine" ] && [ -d "$WORK/pfx" ] || die "run ntdll-patch/b1/test-b1.sh first"
pgrep -x steam_osx >/dev/null || die "Steam is not running"
bin="$WORK/iface"
mkdir -p "$bin/x86_64" "$bin/i386"
x86_64-w64-mingw32-gcc -O1 -o "$bin/x86_64/ifacecheck.exe" "$here/ifacecheck.c"
i686-w64-mingw32-gcc -O1 -o "$bin/i386/ifacecheck.exe" "$here/ifacecheck.c"
for f in steamclient64.dll tier0_s64.dll vstdlib_s64.dll; do cp -f "$BRIDGE_DIR/$f" "$bin/x86_64/"; done
cp -f "$BRIDGE_DIR/steamclient.dll" "$bin/i386/"
export WINEPREFIX="$WORK/pfx" WINEMSYNC=1 WINEDEBUG="err+all,fixme-all"
export WINEDLLPATH="$BRIDGE_DIR"
export WINEDLLOVERRIDES="steamclient=n;steamclient64=n;lsteamclient=b;mscoree,mshtml="
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS"
unset SteamAppId SteamGameId
fails=0
for a in x86_64 i386; do
	echo "== $a"
	(cd "$bin/$a" && "$WORK/engine/wine/bin/wine" ifacecheck.exe) > "$WORK/iface-$a.log" 2>&1 || fails=$((fails + 1))
	grep -a -E "^(OK|FAIL) " "$WORK/iface-$a.log" || { echo "FAIL no output, see $WORK/iface-$a.log"; fails=$((fails + 1)); }
	grep -a "Don't recognize interface" "$WORK/iface-$a.log" || true
done
"$WORK/engine/wine/bin/wineserver" -k 2>/dev/null || true
echo "==> $fails arch(es) failed"
exit "$fails"
