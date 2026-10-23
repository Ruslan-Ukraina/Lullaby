#!/bin/sh
# Uploads a bridge that release/local-bridge.sh built and signed with the owner's release key
# (RELEASE_KEY=~/Lullaby-keys/lullaby-release.key). The same two steps as the workflow's Publish:
# the bridge first, the manifest last, so the app never reads a manifest naming a missing file.
# Nothing is sent unless --yes is given: without it the script only says what it would do.
#
#   release/local-publish.sh <engine, e.g. dormison-r7> <rev> [--yes]
#
# Overridable: WORK (default scratch/local-bridge), GITHUB_REPOSITORY (default feed.json's).
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
WORK=${WORK:-$repo/scratch/local-bridge}
engine=${1:?usage: local-publish.sh <engine> <rev> [--yes]}
rev=${2:?usage: local-publish.sh <engine> <rev> [--yes]}
yes=${3:-}
die() { echo "==> local-publish: $*" >&2; exit 1; }

W=$WORK/$engine
id=bridge-$engine-$rev
feed=$W/feed
[ -f "$feed/$id/$id.tar.xz" ] && [ -f "$feed/manifest/bridge-manifest.json" ] || die "no signed feed for $id in $feed (run release/local-bridge.sh with RELEASE_KEY first)"
[ -f "$W/public-key.txt" ] || die "no $W/public-key.txt: the bridge was not built by local-bridge.sh"
pub=$(cat "$W/public-key.txt")
if grep -qxF "$pub" "$here/test-public-keys.txt"; then die "$pub is a TEST key, not the release key"; fi
GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["repository"])' "$here/feed.json")}
manifest_tag=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["manifestTag"])' "$here/feed.json")
export GITHUB_REPOSITORY

"$here/gh-publish.sh" verify "$pub" "$feed/$id/$id.tar.xz"
"$here/gh-publish.sh" verify "$pub" "$feed/manifest/bridge-manifest.json"
echo "==> signed with $pub, repository $GITHUB_REPOSITORY"
echo "    release $id:        $id.tar.xz, $id.tar.xz.sig, $id-debug.tar.xz (if present)"
echo "    release $manifest_tag: bridge-manifest.json, bridge-manifest.json.sig"
[ "$yes" = --yes ] || { echo "==> dry run: nothing uploaded; add --yes to upload"; exit 0; }

set -- "$feed/$id/$id.tar.xz" "$feed/$id/$id.tar.xz.sig"
[ ! -f "$feed/$id/$id-debug.tar.xz" ] || set -- "$@" "$feed/$id/$id-debug.tar.xz"
"$here/gh-publish.sh" upload "$id" "Steam bridge $id" "$@"
"$here/gh-publish.sh" upload "$manifest_tag" "Signed manifests" \
	"$feed/manifest/bridge-manifest.json" "$feed/manifest/bridge-manifest.json.sig"
echo "==> uploaded $id and the manifest to $GITHUB_REPOSITORY"
