#!/bin/sh
# The View menu's stand-in for `sevo`: "app config <appid> <key> <value>" lands
# in .sevo/apps/<program>.env, other keys and bad values change nothing. The
# stub is cut out of compat_run.sh, so the real text is tested.
set -u
here=$(cd "$(dirname "$0")" && pwd)
src="$here/../feats/compat_run.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/stubcheck.XXXXXX") || exit 1
trap 'rm -rf "${work:?}"' EXIT
HOME="$work/home"; export HOME
mkdir -p "$HOME/Library/Application Support/notproton" "$work/pfx/.sevo/apps"
WINEPREFIX="$work/pfx"; export WINEPREFIX
sed -n "/^sevo_stub=\$(cat <<'STUB'/,/^STUB/p" "$src" | sed '1d;$d' > "$work/sevo"
chmod +x "$work/sevo"

fail=0
env_file="$WINEPREFIX/.sevo/apps/game.exe.env"
check() { # description, expected content
  if [ "$(cat "$env_file" 2>/dev/null)" != "$2" ]; then
    echo "FAIL: $1"; echo "--- got:"; cat "$env_file" 2>/dev/null; fail=1
  fi
}

"$work/sevo" app config 1 upscaler lanczos
[ ! -f "$env_file" ] || { echo "FAIL: wrote without game-exe"; fail=1; }

echo game.exe > "$WINEPREFIX/.sevo/game-exe"
printf 'SEVO_LOADER=/x/wine\n' > "$env_file"
"$work/sevo" app config 1 upscaler metalfx
"$work/sevo" app config 1 fps on
"$work/sevo" app config 1 fps-graph off
"$work/sevo" app config 1 windows all
"$work/sevo" app config 1 filter bilinear
"$work/sevo" app config 1 upscaler anime4k
check "settings are written, repeats replace" "SEVO_LOADER=/x/wine
SEVO_UPSCALER=anime4k
SEVO_FPS=1
SEVO_FPS_GRAPH=0
SEVO_RESIZABLE_WINDOWS=all
SEVO_FINAL_FILTER=bilinear"
"$work/sevo" app config 1 bogus x
"$work/sevo" app config 1 upscaler 'a b;rm'
"$work/sevo" app config 1 fps maybe
"$work/sevo" other config 1 fps on
check "unknown keys and bad values change nothing" "SEVO_LOADER=/x/wine
SEVO_UPSCALER=anime4k
SEVO_FPS=1
SEVO_FPS_GRAPH=0
SEVO_RESIZABLE_WINDOWS=all
SEVO_FINAL_FILTER=bilinear"

[ "$fail" -eq 0 ] && echo "==> stubcheck: View menu choices reach .sevo/apps/<program>.env"
exit "$fail"
