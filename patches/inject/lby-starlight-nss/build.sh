#!/bin/sh
# Builds lullaby-nss.dylib, its kernels and the test tools from a clean MaximKotliar/nss-metal checkout: the checkout is
# copied, Lullaby's patches (nss-metal/*.patch) go onto the copy, never onto the checkout itself.
#   patches/inject/lby-starlight-nss/build.sh <nss-metal checkout> <out dir>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
nm=${1:?nss-metal checkout}; out=${2:?out dir}
want=$(cat "$here/nss-metal/BASE"); have=$(git -C "$nm" rev-parse HEAD)
[ "$want" = "$have" ] || echo "note: nss-metal is at $have, the patches were made on $want"
src=$(mktemp -d); trap 'rm -rf "$src"' EXIT
cp -R "$nm/Sources" "$nm/scripts" "$src/"
for p in "$here"/nss-metal/*.patch; do (cd "$src" && patch -p1 -s < "$p"); done
mkdir -p "$out/res"
for a in arm64 x86_64; do
  clang -arch $a -mmacosx-version-min=26.0 -dynamiclib -O2 -fobjc-arc -Wall -I"$src/Sources/NSSMetal/include" \
    -install_name @rpath/lullaby-nss.dylib -framework Foundation -framework Metal -framework QuartzCore \
    -o "$out/lullaby-nss.$a.dylib" "$here/nss.m" "$src/Sources/NSSMetal/NSSUpscaler.m"
done
lipo -create "$out"/lullaby-nss.arm64.dylib "$out"/lullaby-nss.x86_64.dylib -output "$out/lullaby-nss.dylib"
codesign -fs - "$out/lullaby-nss.dylib" 2>/dev/null
bash "$src/scripts/build-metallib.sh" "$out/res/nss.metallib" 2>/dev/null
cp "$src"/Sources/NSSMetal/Weights/*.bin "$out/res/"
clang -O2 -fobjc-arc -mmacosx-version-min=26.0 -I"$src/Sources/NSSMetal/include" -framework Foundation -framework Metal -framework MetalFX \
  -framework QuartzCore -o "$out/nss_replay" "$here/tests/nss_replay.m" "$src/Sources/NSSMetal/NSSUpscaler.m"
clang -arch x86_64 -O2 -fobjc-arc -mmacosx-version-min=26.0 -framework Foundation -framework Metal -framework MetalFX \
  -framework QuartzCore -framework CoreGraphics -framework ImageIO -framework UniformTypeIdentifiers \
  -o "$out/nss_hook_test" "$here/tests/nss_hook_test.m"   # x86_64 like the Wine loader; run it directly, not through arch
echo "built into $out"
