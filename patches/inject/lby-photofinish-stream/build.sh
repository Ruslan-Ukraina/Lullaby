#!/bin/sh
# Builds lullaby-stream.dylib (arm64 + x86_64) and its test:
#   patches/inject/lby-photofinish-stream/build.sh <out dir>
# Syphon.framework is not linked: the library opens it at run time (components/stream/ or OBS's own copy).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=${1:?out dir}
mkdir -p "$out"
for a in arm64 x86_64; do
  clang -arch $a -mmacosx-version-min=26.0 -dynamiclib -O2 -fobjc-arc -Wall -Wextra -Wno-unused-parameter \
    -install_name @rpath/lullaby-stream.dylib -framework Foundation -framework Metal -framework QuartzCore \
    -o "$out/lullaby-stream.$a.dylib" "$here/stream.m"
done
lipo -create "$out/lullaby-stream.arm64.dylib" "$out/lullaby-stream.x86_64.dylib" -output "$out/lullaby-stream.dylib"
rm -f "$out/lullaby-stream.arm64.dylib" "$out/lullaby-stream.x86_64.dylib"
codesign -fs - "$out/lullaby-stream.dylib" 2>/dev/null
clang -O2 -fobjc-arc -Wall -mmacosx-version-min=26.0 -framework Foundation -framework Metal -framework QuartzCore \
  -o "$out/stream_test" "$here/tests/stream_test.m"
echo "built into $out"
