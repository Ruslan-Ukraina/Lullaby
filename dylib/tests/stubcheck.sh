#!/bin/sh
# The View menu's stand-in for `sevo`: "app config <appid> <key> <value>" goes to
# lullaby-settings, which stores it (LullabySettings, SettingsCLITests); every
# other call, and a call while the CLI is missing, changes nothing. The stub is cut
# out of compat_run.sh, so the real text is tested.
set -u
here=$(cd "$(dirname "$0")" && pwd)
src="$here/../feats/compat_run.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/stubcheck.XXXXXX") || exit 1
trap 'rm -rf "${work:?}"' EXIT
HOME="$work/home"; export HOME
support="$HOME/Library/Application Support/lullaby"
mkdir -p "$support"
sed -n "/^sevo_stub=\$(cat <<'STUB'/,/^STUB/p" "$src" | sed '1d;$d' > "$work/sevo"
chmod +x "$work/sevo"

fail=0
calls="$work/calls"
check() { # description, expected calls
  if [ "$(cat "$calls" 2>/dev/null)" != "$2" ]; then
    echo "FAIL: $1"; echo "--- got:"; cat "$calls" 2>/dev/null; fail=1
  fi
}

"$work/sevo" app config 1 upscaler lanczos || { echo "FAIL: exit status without the CLI"; fail=1; }
check "nothing runs without the CLI" ""

cat > "$support/lullaby-settings" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$calls"
exit 3
EOF
chmod +x "$support/lullaby-settings"

"$work/sevo" app config 3527290 upscaler metalfx
"$work/sevo" app config 3527290 fps on
"$work/sevo" other config 1 fps on
"$work/sevo" app list
"$work/sevo" || true
check "app config calls reach the CLI, others do not" "app config 3527290 upscaler metalfx
app config 3527290 fps on"

"$work/sevo" app config 1 'a b;rm' x || { echo "FAIL: the CLI's status leaked out"; fail=1; }
check "arguments arrive as they were given" "app config 3527290 upscaler metalfx
app config 3527290 fps on
app config 1 a b;rm x"

grep -q 'app config 3527290 fps on' "$support/lullaby-sevo.log" \
  || { echo "FAIL: calls are not logged"; fail=1; }

[ "$fail" -eq 0 ] && echo "==> stubcheck: View menu choices reach lullaby-settings"
exit "$fail"
