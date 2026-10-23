#!/bin/sh
# Builds the stand's native tools into out/: threadcpu (per-thread processor time) and
# frametap.dylib (the frame tap, universal arm64 + x86_64, ad-hoc signed).
#   tools/perf/build.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
mkdir -p "$root/out"
clang -O2 -Wall -Wextra -o "$root/out/threadcpu" "$here/threadcpu.c"
clang -O2 -Wall -Wextra -Wno-unused-parameter -fobjc-arc -dynamiclib -arch arm64 -arch x86_64 \
  -mmacosx-version-min=13.0 -weak_framework Foundation -weak_framework QuartzCore -weak_framework Metal \
  -install_name @rpath/frametap.dylib -o "$root/out/frametap.dylib" "$here/frametap.m"
codesign -f -s - "$root/out/frametap.dylib" > /dev/null 2>&1
echo "==> built out/threadcpu and out/frametap.dylib ($(lipo -archs "$root/out/frametap.dylib"))"
