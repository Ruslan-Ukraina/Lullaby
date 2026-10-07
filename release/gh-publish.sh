#!/bin/sh
# GitHub side of the release workflows (Phase 6, docs/RELEASING.md). Needs gh with
# GH_TOKEN and GITHUB_REPOSITORY, as a workflow step has them.
#
#   gh-publish.sh fetch <feed base> <tag> <file> <dir>
#       download a published file and its .sig into <dir>; exit 1 when not published
#   gh-publish.sh verify <public key> <file>
#       <file>.sig must be the release key's signature over <file>
#   gh-publish.sh upload <tag> <title> <file>...
#       into the release <tag>, made first if missing (a pre-release, never "latest")
#   gh-publish.sh issue <title> <body file>
#       open an issue, or comment on the open one with the same title
#
# Upload order matters and is the caller's: artifacts first, manifests last, so the
# app never reads a manifest naming a file that is not there yet.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
VERIFY=${VERIFY:-${RUNNER_TEMP:-/tmp}/verify-ed25519}

die() { echo "==> gh-publish: $*" >&2; exit 1; }

case "${1:-}" in
fetch)
	base=$2 tag=$3 file=$4 dir=$5
	mkdir -p "$dir"
	curl -fsSL --retry 3 -o "$dir/$file" "$base$tag/$file" 2>/dev/null || { rm -f "$dir/$file"; exit 1; }
	curl -fsSL --retry 3 -o "$dir/$file.sig" "$base$tag/$file.sig" || die "$tag/$file is published without its .sig"
	;;
verify)
	[ -x "$VERIFY" ] || swiftc -O -o "$VERIFY" "$here/../engine/verify-ed25519.swift"
	"$VERIFY" "$2" "$3" "$3.sig" || die "$3 does not carry the release key's signature"
	;;
upload)
	tag=$2 title=$3
	shift 3
	if ! gh release view "$tag" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
		gh release create "$tag" --repo "$GITHUB_REPOSITORY" --prerelease --latest=false \
			--title "$title" --notes "Files NotProton.app downloads and checks against NotProton's release key. Published by CI; see docs/RELEASING.md." \
			|| die "cannot create the release $tag"
	fi
	gh release upload "$tag" --repo "$GITHUB_REPOSITORY" --clobber "$@" || die "cannot upload to $tag"
	echo "==> gh-publish: $tag <- $*"
	;;
issue)
	title=$2 body=$3
	number=$(gh issue list --repo "$GITHUB_REPOSITORY" --state open --search "\"$title\" in:title" \
		--json number,title --jq ".[] | select(.title == \"$title\") | .number" | head -1)
	if [ -n "$number" ]; then
		gh issue comment "$number" --repo "$GITHUB_REPOSITORY" --body-file "$body"
		echo "==> gh-publish: commented on issue #$number"
	else
		gh issue create --repo "$GITHUB_REPOSITORY" --title "$title" --body-file "$body"
	fi
	;;
*)
	echo "usage: $0 fetch|verify|upload|issue ..." >&2
	exit 2
	;;
esac
