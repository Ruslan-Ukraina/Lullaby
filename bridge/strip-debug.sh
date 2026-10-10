#!/bin/sh
# Takes the debug information out of the bridge's PE files (OPTIMIZATION O1): the
# mingw builds of lsteamclient.dll (x86_64, i386) and steam.exe carry DWARF that is
# most of their size (79 MB of bridge -> ~12 MB). The code is not changed, only
# the .debug_* sections go; a crash in Wine still shows addresses.
#
#   bridge/strip-debug.sh <files-dir> <debug-dir>
#
# <files-dir> holds the bridge files under their feed names (steam.exe,
# x86_64-windows-lsteamclient.dll, i386-windows-lsteamclient.dll, ...). Each PE file
# is first copied unchanged into <debug-dir> (kept beside the release, never
# shipped in the app), then stripped in place. Other files are left alone.
set -eu

FILES=${1:?usage: strip-debug.sh <files-dir> <debug-dir>}
DEBUG=${2:?usage: strip-debug.sh <files-dir> <debug-dir>}

strip_one() {
	tool=$1 name=$2
	f=$FILES/$name
	[ -f "$f" ] || { echo "==> strip-debug: $f is missing" >&2; exit 1; }
	command -v "$tool" >/dev/null || { echo "==> strip-debug: $tool is not on PATH (mingw-w64)" >&2; exit 1; }
	cp -p "$f" "$DEBUG/$name"
	"$tool" --strip-debug "$f"
	before=$(wc -c < "$DEBUG/$name" | tr -d ' ')
	after=$(wc -c < "$f" | tr -d ' ')
	[ "$after" -lt "$before" ] || { echo "==> strip-debug: $name did not get smaller ($before bytes)" >&2; exit 1; }
	echo "==> strip-debug: $name $before -> $after bytes"
}

mkdir -p "$DEBUG"
strip_one x86_64-w64-mingw32-strip steam.exe
strip_one x86_64-w64-mingw32-strip x86_64-windows-lsteamclient.dll
strip_one i686-w64-mingw32-strip i386-windows-lsteamclient.dll
