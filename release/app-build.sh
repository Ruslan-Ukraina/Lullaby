#!/bin/sh
# The build number of a release of Lullaby.app: CFBundleVersion, what Sparkle compares to decide whether a
# release is newer than the one installed. Prints one integer.
#
# It must only grow across every release ever published. The published line before the history of this
# branch started over (1.1.0-pre.25, 2026-10-17) had build 259; the commit count of this branch alone
# (it was 40 when it began) is far below that, so a Mac on pre.25 would never be offered the update.
# The offset puts every build of this branch above it. Never lower it, never change it between releases.
set -eu
OFFSET=300
here=$(cd "$(dirname "$0")" && pwd)
count=$(git -C "$here/.." rev-list --count HEAD)
echo $((count + OFFSET))
