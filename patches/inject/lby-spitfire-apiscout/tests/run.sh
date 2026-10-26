#!/bin/sh
# Tests of the scout code (the apiscout block of steam/hook/feats/compat_run.sh) on made-up copies of the files engines write; no game is started
# and nothing outside a temporary directory is touched.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'rm -rf "${t:?}"' EXIT
fail=0; n=0
runscript="$here/../../../../steam/hook/feats/compat_run.sh"
sed -n '/^# --- apiscout begin/,/^# --- apiscout end/p' "$runscript" > "$t/scout.sh"
[ -s "$t/scout.sh" ] || { echo "FAIL: no apiscout block in $runscript"; exit 1; }
# shellcheck source=/dev/null
. "$t/scout.sh"
check() { # name expected actual
  n=$((n+1))
  if [ "$2" = "$3" ]; then :; else echo "FAIL $1: expected [$2] got [$3]"; fail=1; fi
}
api() { sed -n 's/^api=\([^ ]*\).*/\1/p'; }
src() { sed -n 's/.* source=\([^ ]*\).*/\1/p'; }

game="$t/game"; user="$t/user"; mkdir -p "$game" "$user"

# 1. arguments of the chosen Steam option
check "unity d3d11" dx11 "$(apiscout_detect "$game" "$user" -force-d3d11 | api)"
check "unity d3d12" dx12 "$(apiscout_detect "$game" "$user" -force-d3d12 | api)"
check "unity vulkan" vk "$(apiscout_detect "$game" "$user" -force-vulkan | api)"
check "unity glcore" gl "$(apiscout_detect "$game" "$user" -force-glcore | api)"
check "scs rdevice dx11" dx11 "$(apiscout_detect "$game" "$user" -rdevice dx11 | api)"
check "scs rdevice opengl" gl "$(apiscout_detect "$game" "$user" -rdevice opengl | api)"
check "unrelated args" none "$(apiscout_detect "$game" "$user" -windowed -novid | api)"
check "arg source" arg "$(apiscout_detect "$game" "$user" -dx12 | src)"

# 2. Source 2 boot.vcfg
mkdir -p "$game/game/citadel/cfg"
printf '"boot"\n{\n\t"DefaultRenderSystemOption"\t\t"-vulkan"\n}\n' > "$game/game/citadel/cfg/boot.vcfg"
check "source2 vulkan" vk "$(apiscout_detect "$game" "$user" | api)"
check "source2 source" settings "$(apiscout_detect "$game" "$user" | src)"
printf '"boot"\n{\n}\n' > "$game/game/citadel/cfg/boot.vcfg"
check "source2 default" dx11 "$(apiscout_detect "$game" "$user" | api)"
check "arg beats settings" dx12 "$(apiscout_detect "$game" "$user" -force-d3d12 | api)"
rm -rf "${game:?}/game"

# 2b. RE Engine config.ini in the game folder
printf '[GameOption]\nA=1\n[Render]\nCapability=DirectX12\n[Render/Adapter]\n' > "$game/config.ini"
check "re engine dx12" dx12 "$(apiscout_detect "$game" "$user" | api)"
check "re engine source" settings "$(apiscout_detect "$game" "$user" | src)"
printf '[Render]\r\nCapability=DirectX11\r\n' > "$game/config.ini"
check "re engine dx11 with CRLF" dx11 "$(apiscout_detect "$game" "$user" | api)"
printf '[Render]\nCapability=Other\n' > "$game/config.ini"
check "re engine unknown value says nothing" none "$(apiscout_detect "$game" "$user" | api)"
rm -f "$game/config.ini"

# 3. SCS config.cfg
mkdir -p "$user/Documents/Euro Truck Simulator 2"
printf 'uset r_mode_width "3024"\nuset r_device ""\n' > "$user/Documents/Euro Truck Simulator 2/config.cfg"
check "scs automatic says nothing" none "$(apiscout_detect "$game" "$user" | api)"
printf 'uset r_device "dx9"\n' > "$user/Documents/Euro Truck Simulator 2/config.cfg"
check "scs dx9" dx9 "$(apiscout_detect "$game" "$user" | api)"
rm -rf "${user:?}/Documents"

# 4. Unity Player.log of the last run
mkdir -p "$user/AppData/LocalLow/Studio/Game"
printf 'Initialize engine version\nForcing GfxDevice: Direct3D 11\nDirect3D:\n    Version:  Direct3D 11.0 [level 11.1]\n' > "$user/AppData/LocalLow/Studio/Game/Player.log"
check "unity log dx11" dx11 "$(apiscout_detect "$game" "$user" | api)"
check "unity log source" lastrun "$(apiscout_detect "$game" "$user" | src)"
printf 'Direct3D:\n    Version:  Direct3D 12.0 [level 12.1]\n' > "$user/AppData/LocalLow/Studio/Game/Player.log"
check "unity log dx12" dx12 "$(apiscout_detect "$game" "$user" | api)"
rm -rf "${user:?}/AppData"

# 5. files beside the exe only suggest, and come last
mkdir -p "$game/D3D12"
check "files dx12" dx12 "$(apiscout_detect "$game" "$user" | api)"
check "files source" files "$(apiscout_detect "$game" "$user" | src)"
check "args beat files" dx11 "$(apiscout_detect "$game" "$user" -dx11 | api)"
rmdir "$game/D3D12"

# 5b. MonoGame builds, each in a folder of its own (the temporary directory goes away at the end)
mkdir -p "$t/mg1" "$t/mg2" "$t/mg3"
printf 'xx DesktopGL OpenGL yy' > "$t/mg1/MonoGame.Framework.dll"
check "monogame desktopgl" gl "$(apiscout_detect "$t/mg1" "$user" | api)"
printf 'xx SharpDX Direct3D11 yy' > "$t/mg2/MonoGame.Framework.dll"
check "monogame windowsdx" dx11 "$(apiscout_detect "$t/mg2" "$user" | api)"
printf 'xx nothing yy' > "$t/mg3/MonoGame.Framework.dll"
check "monogame unknown build" none "$(apiscout_detect "$t/mg3" "$user" | api)"

# 6. backends
check "backend dx12" d3dmetal "$(apiscout_backend dx12)"
check "backend dx11" dxmt "$(apiscout_backend dx11)"
check "backend dx9" mtld3d "$(apiscout_backend dx9)"
check "backend vk" kosmickrisp "$(apiscout_backend vk)"
check "backend gl" winemetalgl "$(apiscout_backend gl)"
check "backend none" dxmt "$(apiscout_backend none)"

# 7. the remembered places: only a changed one is reported
printf 'a\n' > "$t/a.cfg"; printf 'b\n' > "$t/b.cfg"
apiscout_remember "$t/state" "$t/a.cfg" "$t/b.cfg"
out=$(apiscout_changed "$t/state" || true)
check "unchanged is silent" "" "$out"
if apiscout_changed "$t/state" >/dev/null; then check "unchanged status" 1 0; else check "unchanged status" 1 1; fi
printf 'bbbb\n' > "$t/b.cfg"
out=$(apiscout_changed "$t/state" || true)
check "changed place named" "$t/b.cfg" "$out"
rm -f "$t/a.cfg"; out=$(apiscout_changed "$t/state" || true)
check "removed place counts as changed" "$t/a.cfg
$t/b.cfg" "$out"

# 8. read only: detecting creates nothing in the game or the prefix user
before=$(find "$t" | sort | tr '\n' ' ')
apiscout_detect "$game" "$user" -dx11 >/dev/null
after=$(find "$t" | sort | tr '\n' ' ')
check "writes nothing" "$before" "$after"

[ "$fail" -eq 0 ] && echo "==> apiscout tests: $n checks pass"
exit "$fail"
