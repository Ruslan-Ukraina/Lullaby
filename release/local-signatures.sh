#!/bin/sh
# The signature databases of steam/signatures, published from the owner's Mac (docs/RELEASING_LOCAL.md): the
# databases in the repository and its manifest become the signed signatures-manifest.json the app reads. The same
# publishing steps as .github/workflows/steam-signatures.yml, for databases that are already cut and accepted
# (out/sigslice and out/anchorcheck did that: docs/DECISIONS.md, the build's row). Nothing is sent without --yes.
#
#   release/local-signatures.sh            the owner's release key (~/Lullaby-keys), builds the signed feed, sends nothing
#   release/local-signatures.sh --yes      then uploads the databases (release "signatures"), then the manifest
#   release/local-signatures.sh --test     a rehearsal with a TEST key; nothing is read from the owner's keys or sent
#
# The order is the app's safety: databases first, the manifest last. The key is used from its file and never printed
# (RELEASE_KEY_FILE overrides the path). The serial is one more than the published one, so the app takes it.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
cd "$root"
die() { echo "==> local-signatures: $*" >&2; exit 1; }
say() { echo "==> local-signatures: $*"; }

mode=release
yes=0
for a in "$@"; do
	case "$a" in
	--test) mode="test" ;;
	--yes) yes=1 ;;
	*) die "usage: release/local-signatures.sh [--yes | --test]" ;;
	esac
done
[ "$mode" = test ] && [ "$yes" = 1 ] && die "a rehearsal sends nothing; --yes is for the release"

repo=$(python3 -I "$here/feed.py" config repository)
feed=$(python3 -I "$here/feed.py" config feed)
manifest_tag=$(python3 -I "$here/feed.py" config manifestTag)
signatures_tag=$(python3 -I "$here/feed.py" config signaturesTag)
export GITHUB_REPOSITORY="$repo"

out="$root/scratch/release/signatures"
rm -rf "${out:?}"
mkdir -p "$out/keys"
if [ "$mode" = test ]; then
	eval "$("$here/ci-keys.sh" dry-run "$out/keys" | sed -nE 's/^(LB_RELEASE_KEY|SPARKLE_KEY)=(.*)$/export \1="\2"/p')"
	key_file=$out/keys/release.key
else
	key_file=${RELEASE_KEY_FILE:-$HOME/Lullaby-keys/lullaby-release.key}
	[ -f "$key_file" ] || die "no release key at $key_file"
	LB_RELEASE_KEY=$(swift "$here/sign.swift" "$key_file" --public 2>/dev/null) || die "the release key file is not a base64 Ed25519 private key"
	grep -v '^#' "$here/test-public-keys.txt" | grep -qxF "$LB_RELEASE_KEY" && die "that is a TEST key"
	say "the owner's release key: $LB_RELEASE_KEY"
fi
export LB_RELEASE_KEY
verify() { VERIFY=${VERIFY:-$out/verify-ed25519} "$here/gh-publish.sh" verify "$LB_RELEASE_KEY" "$1"; }

current=
if [ "$mode" = release ] && "$here/gh-publish.sh" fetch "$manifest_tag" signatures-manifest.json "$out/current"; then
	verify "$out/current/signatures-manifest.json"
	current=$out/current/signatures-manifest.json
	say "published manifest: serial $(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["serial"])' "$current")"
else
	say "no published signatures manifest is read; this one starts from the repository's"
fi

# shellcheck disable=SC2086
python3 -I "$here/feed.py" publish-signatures --repo steam/signatures/manifest.json --dir steam/signatures/macos.arm64 \
	${current:+--current "$current"} --feed "$feed" --out "$out/feed"
swift "$here/sign.swift" "$key_file" "$out/feed/manifest/signatures-manifest.json"
verify "$out/feed/manifest/signatures-manifest.json"
n=$(find "$out/feed/signatures" -name "*.json" | wc -l | tr -d ' ')
say "signed: serial $(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["serial"])' "$out/feed/manifest/signatures-manifest.json"), $n database(s) in $out/feed"
if [ "$yes" != 1 ]; then
	say "nothing was sent ($([ "$mode" = test ] && echo 'a rehearsal' || echo 'no --yes')); it would send $n database(s) to the release '$signatures_tag', then the manifest to '$manifest_tag'"
	exit 0
fi

"$here/gh-publish.sh" upload "$signatures_tag" "Steam signature databases" "$out"/feed/signatures/*.json
"$here/gh-publish.sh" upload "$manifest_tag" "Signed manifests" "$out/feed/manifest/signatures-manifest.json" "$out/feed/manifest/signatures-manifest.json.sig"
"$here/gh-publish.sh" fetch "$manifest_tag" signatures-manifest.json "$out/back"
cmp "$out/back/signatures-manifest.json" "$out/feed/manifest/signatures-manifest.json" || die "the published manifest differs from the one signed"
verify "$out/back/signatures-manifest.json"
say "published; the manifest reads back and verifies"
