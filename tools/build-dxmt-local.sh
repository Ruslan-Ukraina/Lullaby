#!/bin/bash
# Local build of DXMT from a pinned commit, the recipe of .github/workflows/dxmt-build.yml
# (x86_64 and x86, release, D3D12 off). Needs cmake, ninja, meson, mingw-w64 and Rosetta
# (all present on the owner's Mac); installs nothing, everything lands in <work>.
# usage: build-dxmt-local.sh <work dir> [commit]
set -euo pipefail

WORK="${1:?usage: build-dxmt-local.sh <work dir> [commit]}"
COMMIT="${2:-50102f994b406f58f56d5d09f2ad20f9b90390a2}"
LLVM_VERSION=llvmorg-15.0.7
WINE_URL=https://github.com/3Shain/wine/releases/download/v8.16-3shain/wine.tar.gz
WINE_SHA256="${DXMT_WINE_SHA256:-}"
JOBS="$(sysctl -n hw.ncpu)"

mkdir -p "$WORK"
cd "$WORK"
WORK="$PWD"
log() { printf '==> %s\n' "$*"; }

if [ ! -d dxmt/.git ]; then
    git clone https://github.com/3Shain/dxmt.git dxmt
fi
git -C dxmt fetch -q origin
git -C dxmt checkout -q "$COMMIT"
git -C dxmt submodule update --init --recursive -q
test "$(git -C dxmt rev-parse HEAD)" = "$COMMIT"
log "DXMT at $COMMIT"

if [ ! -d toolchains/wine/bin ] && [ ! -d toolchains/wine/lib ]; then
    log "Wine toolchain (3Shain v8.16)"
    mkdir -p toolchains/wine
    curl -fSL "$WINE_URL" -o toolchains/wine.tar.gz
    shasum -a 256 toolchains/wine.tar.gz | tee toolchains/wine.tar.gz.sha256
    if [ -n "$WINE_SHA256" ]; then
        echo "$WINE_SHA256  toolchains/wine.tar.gz" | shasum -a 256 -c -
    fi
    tar -xzf toolchains/wine.tar.gz -C toolchains/wine
fi

if [ ! -x toolchains/llvm-darwin/bin/llvm-config ] && [ ! -d toolchains/llvm-darwin/lib ]; then
    log "LLVM $LLVM_VERSION for Darwin x86_64 (long)"
    [ -d toolchains/llvm-project ] ||
        git clone --depth 1 --branch "$LLVM_VERSION" https://github.com/llvm/llvm-project.git toolchains/llvm-project
    cmake -B toolchains/llvm-darwin-build -S toolchains/llvm-project/llvm \
        -DCMAKE_INSTALL_PREFIX="$WORK/toolchains/llvm-darwin" \
        -DCMAKE_OSX_ARCHITECTURES=x86_64 -DLLVM_HOST_TRIPLE=x86_64-apple-darwin \
        -DLLVM_ENABLE_ASSERTIONS=On -DLLVM_ENABLE_ZSTD=Off -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_FLAGS="-D_LIBCPP_KEEP_TRANSITIVE_INCLUDES_LLVM23" \
        -DLLVM_TARGETS_TO_BUILD="" -DLLVM_BUILD_TOOLS=Off -DLLVM_INCLUDE_BENCHMARKS=Off \
        -DBUG_REPORT_URL="https://github.com/3Shain/dxmt" -DPACKAGE_VENDOR="DXMT" \
        -DLLVM_VERSION_PRINTER_SHOW_HOST_TARGET_INFO=Off -G Ninja
    cmake --build toolchains/llvm-darwin-build -j "$JOBS"
    cmake --install toolchains/llvm-darwin-build
fi

cd dxmt
INSTALL="$WORK/install"
rm -rf "${WORK:?}/install" build64 build32
log "x86_64"
meson setup --cross-file build-win64.txt -Denable_nvapi=true -Denable_nvngx=true \
    -Dnative_llvm_path="$WORK/toolchains/llvm-darwin" -Dwine_install_path="$WORK/toolchains/wine" \
    build64 --buildtype release --prefix "$INSTALL" --strip
meson compile -C build64
meson install -C build64
log "x86"
meson setup --cross-file build-win32.txt -Dwine_install_path="$WORK/toolchains/wine" \
    build32 --buildtype release --prefix "$INSTALL" --strip
meson compile -C build32
meson install -C build32

find "$INSTALL" -name '*.a' -delete
(cd "$INSTALL" && find . -type f ! -name SHA256SUMS ! -name PIN | sort | xargs shasum -a 256) >"$INSTALL/SHA256SUMS"
printf 'commit=%s\n' "$COMMIT" >"$INSTALL/PIN"
log "done: $INSTALL"
