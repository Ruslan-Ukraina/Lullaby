#!/bin/sh
# Interleaved A/B on PEAK (DXMT): base, variant, base, variant — heat drift hits both sides.
#   perf/peak-ab.sh NAME SETTING JSON
set -u
name=$1; key=$2; val=$3
here=$(cd "$(dirname "$0")" && pwd)
CLI="$HOME/Library/Application Support/lullaby/lullaby-settings"; A=3527290
m() { "$here/peak-matrix.sh" "$1" keep - 45 30 2>&1 | grep '^label' | cut -d' ' -f1,5-8; }
for round in 1 2; do
	"$CLI" set --app $A "$key" null > /dev/null; m "ab-$name-base$round"
	"$CLI" set --app $A "$key" "$val" > /dev/null; m "ab-$name-var$round"
done
"$CLI" set --app $A "$key" null > /dev/null
