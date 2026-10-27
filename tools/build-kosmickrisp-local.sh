#!/bin/sh
# Builds Mesa's KosmicKrisp (Vulkan on Metal 4) for x86_64, the architecture of the Dormison engine's Wine
# (it runs under Rosetta; the LunarG SDK's own build is arm64 only). Nothing outside WORK is written
# and nothing is installed; the result is two files in OUT. Stock Mesa, no patches.
#
#   tools/build-kosmickrisp-local.sh                 # Mesa tag and SDK pinned below
#   MESA_TAG=mesa-26.2.5 tools/build-kosmickrisp-local.sh
#
# Needs, from the owner (Homebrew arm64): meson ninja pkg-config cmake llvm libclc spirv-tools
# spirv-llvm-translator; and a Python environment with mako packaging pyyaml (PYTHON_VENV, default
# ../Workspace/.venv-mesa, made with: python3 -m venv DIR && DIR/bin/pip install mako packaging pyyaml).
# The static SPIRV-Tools libraries for x86_64 come from the LunarG Vulkan SDK zip (SDK_ZIP): its installer
# is NOT run, the packed archive inside installer.dat is read with bsdtar.
#
# How it works: the three tools Mesa needs while building (mesa_clc, vtn_bindgen2, kk_clc) are built for
# this Mac first (arm64), then the driver is cross-built for x86_64 with `-Dmesa-clc=system`.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
MESA_TAG=${MESA_TAG:-mesa-26.2.4}
WORK=${WORK:-$repo/scratch/kk}
OUT=${OUT:-$WORK/out}
PYTHON_VENV=${PYTHON_VENV:-$repo/../Workspace/.venv-mesa}
SDK_VERSION=${SDK_VERSION:-1.4.363.0}
SDK_ZIP=${SDK_ZIP:-$repo/scratch/dl-vulkansdk/vulkansdk-macos-$SDK_VERSION.zip}
SDK_SHA256=${SDK_SHA256:-163431e0203c8215286a17cf393643ce6b951f77d1b4f74ab30821a1f0beb09b}
BREW=${BREW:-/opt/homebrew}

say() { printf '==> %s\n' "$*"; }
need() { [ -e "$1" ] || { echo "kosmickrisp: missing $1 ($2)" >&2; exit 1; }; }
need "$BREW/bin/meson" "brew install meson"
need "$BREW/bin/ninja" "brew install ninja"
need "$BREW/bin/pkg-config" "brew install pkgconf"
need "$BREW/opt/llvm/bin/llvm-config" "brew install llvm"
need "$BREW/opt/libclc" "brew install libclc"
need "$BREW/opt/spirv-tools" "brew install spirv-tools"
need "$BREW/opt/spirv-llvm-translator" "brew install spirv-llvm-translator"
need "$PYTHON_VENV/bin/python3" "python3 -m venv $PYTHON_VENV && $PYTHON_VENV/bin/pip install mako packaging pyyaml"
"$PYTHON_VENV/bin/python3" -c 'import mako, packaging, yaml' 2>/dev/null || { echo "kosmickrisp: the Python environment lacks mako, packaging or pyyaml" >&2; exit 1; }
need "$SDK_ZIP" "download vulkansdk-macos-$SDK_VERSION.zip from https://sdk.lunarg.com/sdk/download/$SDK_VERSION/mac/"
[ "$(shasum -a 256 "$SDK_ZIP" | cut -d' ' -f1)" = "$SDK_SHA256" ] || { echo "kosmickrisp: $SDK_ZIP does not match the pinned sha256" >&2; exit 1; }

mkdir -p "$WORK" "$OUT"
# A clean PATH: our Python first (Mesa runs python3 scripts), then Homebrew, then the system.
PATH="$WORK/tools/bin:$PYTHON_VENV/bin:$BREW/bin:/usr/bin:/bin:/usr/sbin:/sbin"; export PATH

if [ ! -d "$WORK/mesa/.git" ]; then
  say "Mesa $MESA_TAG (shallow clone of the official repository)"
  git clone --quiet --depth 1 --branch "$MESA_TAG" https://gitlab.freedesktop.org/mesa/mesa.git "$WORK/mesa"
fi
[ "$(git -C "$WORK/mesa" describe --tags --exact-match 2>/dev/null || true)" = "$MESA_TAG" ] || { echo "kosmickrisp: $WORK/mesa is not at $MESA_TAG" >&2; exit 1; }

say "static SPIRV-Tools (x86_64 and arm64) out of the SDK's installer archive"
if [ ! -f "$WORK/sysroot/lib/libSPIRV-Tools.a" ]; then
  mkdir -p "$WORK/sdk" "$WORK/sysroot/lib/pkgconfig"
  unzip -q -o "$SDK_ZIP" -d "$WORK/sdk"
  dat=$(find "$WORK/sdk" -name installer.dat | head -n 1)
  "$PYTHON_VENV/bin/python3" - "$dat" "$WORK/sdk/part.7z" <<'PY'
import mmap, sys
src, dst = sys.argv[1:3]
sig = b'7z\xbc\xaf\x27\x1c'
with open(src, 'rb') as f:
    m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
    offsets, i = [], 0
    while True:
        i = m.find(sig, i)
        if i < 0: break
        offsets.append(i); i += 6
    # the SDK itself is the big one, the last archive of the installer
    start = offsets[-1]
    open(dst, 'wb').write(m[start:])
PY
  bsdtar -xf "$WORK/sdk/part.7z" -C "$WORK/sysroot" --strip-components=1 \
    macOS/include/spirv-tools macOS/lib/libSPIRV-Tools.a macOS/lib/libSPIRV-Tools-opt.a macOS/lib/libSPIRV-Tools-link.a
  for a in libSPIRV-Tools libSPIRV-Tools-opt libSPIRV-Tools-link; do
    lipo -info "$WORK/sysroot/lib/$a.a" | grep -q x86_64 || { echo "kosmickrisp: $a.a has no x86_64 part" >&2; exit 1; }
  done
fi
cat > "$WORK/sysroot/lib/pkgconfig/SPIRV-Tools.pc" <<EOF
prefix=$WORK/sysroot
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: SPIRV-Tools
Description: SPIR-V Tools (static, universal, from the LunarG Vulkan SDK $SDK_VERSION)
Version: 2026.3
Libs: -L\${libdir} -lSPIRV-Tools-opt -lSPIRV-Tools-link -lSPIRV-Tools -lc++
Cflags: -I\${includedir}
EOF

say "host tools (mesa_clc, vtn_bindgen2, kk_clc) for this Mac"
cat > "$WORK/native.ini" <<EOF
[binaries]
llvm-config = '$BREW/opt/llvm/bin/llvm-config'
EOF
if [ ! -x "$WORK/tools/bin/kk_clc" ]; then
  PKG_CONFIG_PATH="$BREW/opt/libclc/share/pkgconfig:$BREW/opt/spirv-tools/lib/pkgconfig:$BREW/opt/spirv-llvm-translator/lib/pkgconfig:$BREW/opt/z3/lib/pkgconfig" \
    meson setup "$WORK/native-build" "$WORK/mesa" --native-file "$WORK/native.ini" --buildtype=release \
      -Dplatforms=macos -Dvulkan-drivers=kosmickrisp -Dgallium-drivers= -Dopengl=false -Dzstd=disabled \
      -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dllvm=enabled > "$WORK/native-setup.log" 2>&1
  ninja -C "$WORK/native-build" src/compiler/clc/mesa_clc src/compiler/spirv/vtn_bindgen2 src/kosmickrisp/clc/kk_clc > "$WORK/native-build.log" 2>&1
  mkdir -p "$WORK/tools/bin"
  cp "$WORK/native-build/src/compiler/clc/mesa_clc" "$WORK/native-build/src/compiler/spirv/vtn_bindgen2" \
     "$WORK/native-build/src/kosmickrisp/clc/kk_clc" "$WORK/tools/bin/"
fi

say "the driver for x86_64"
cat > "$WORK/cross-x86_64.ini" <<EOF
[binaries]
c = ['/usr/bin/clang', '-arch', 'x86_64']
cpp = ['/usr/bin/clang++', '-arch', 'x86_64']
objc = ['/usr/bin/clang', '-arch', 'x86_64']
objcpp = ['/usr/bin/clang++', '-arch', 'x86_64']
ar = '/usr/bin/ar'
strip = '/usr/bin/strip'
pkg-config = '$BREW/bin/pkg-config'
python = '$PYTHON_VENV/bin/python3'
llvm-config = '$BREW/opt/llvm/bin/llvm-config'

[host_machine]
system = 'darwin'
subsystem = 'macos'
kernel = 'xnu'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'

[properties]
needs_exe_wrapper = true
pkg_config_libdir = '$WORK/sysroot/lib/pkgconfig'
EOF
if [ ! -d "$WORK/x86-build" ]; then
  meson setup "$WORK/x86-build" "$WORK/mesa" --cross-file "$WORK/cross-x86_64.ini" --buildtype=release \
    -Dplatforms=macos -Dvulkan-drivers=kosmickrisp -Dgallium-drivers= -Dopengl=false -Dzstd=disabled \
    -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dllvm=disabled -Dmesa-clc=system -Dprecomp-compiler=system \
    > "$WORK/x86-setup.log" 2>&1
fi
ninja -C "$WORK/x86-build" > "$WORK/x86-build.log" 2>&1

lib="$WORK/x86-build/src/kosmickrisp/vulkan/libvulkan_kosmickrisp.dylib"
[ -f "$lib" ] || { echo "kosmickrisp: the build gave no library, see $WORK/x86-build.log" >&2; exit 1; }
lipo -info "$lib" | grep -q 'architecture: x86_64' || { echo "kosmickrisp: the library is not x86_64" >&2; exit 1; }
cp "$lib" "$OUT/libvulkan_kosmickrisp.dylib"
codesign -s - --force "$OUT/libvulkan_kosmickrisp.dylib" >/dev/null 2>&1
# A path with a slash is read relative to this file; a bare name would go to the system's dlopen search.
cat > "$OUT/kosmickrisp_icd.json" <<'EOF'
{
  "file_format_version": "1.0.1",
  "ICD": {
    "api_version": "1.4.0",
    "library_path": "./libvulkan_kosmickrisp.dylib"
  }
}
EOF
say "built: $OUT/libvulkan_kosmickrisp.dylib ($(lipo -info "$OUT/libvulkan_kosmickrisp.dylib" | sed 's/.*are: //;s/.*architecture: //'), $MESA_TAG, sha256 $(shasum -a 256 "$OUT/libvulkan_kosmickrisp.dylib" | cut -c1-16)...)"
