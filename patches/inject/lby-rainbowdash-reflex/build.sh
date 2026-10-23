#!/bin/sh
# Builds Lullaby's nvapi64.dll (x86_64 PE) with mingw-w64: patches/inject/lby-rainbowdash-reflex/build.sh OUT.dll
#
# The DLL is stamped as one of Wine's own ("Wine builtin DLL" right after the DOS header,
# where dlls/ntdll/loader.c looks): with nvapi64=b the game then takes it from the D3DMetal
# renderer directory like Apple's DLLs, and never an nvapi64.dll lying in its own folder.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=${1:?output dll}
x86_64-w64-mingw32-gcc -shared -O2 -Wall -Wextra -Wno-unused-parameter -Wno-cast-function-type \
  -o "$out" "$here/lullaby_nvapi.c" "$here/nvapi64.def" \
  -static-libgcc -Wl,--no-insert-timestamp -lntdll -luser32
x86_64-w64-mingw32-strip "$out"
python3 -I - "$out" <<'PY'
import struct, sys
path = sys.argv[1]
data = bytearray(open(path, "rb").read())
signature = b"Wine builtin DLL\0"
if struct.unpack_from("<I", data, 0x3C)[0] < 0x40 + len(signature):
    sys.exit("no room for the builtin signature before the PE header")
data[0x40:0x40 + len(signature)] = signature
open(path, "wb").write(data)
PY
