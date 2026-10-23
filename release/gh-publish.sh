#!/bin/sh
# GitHub side of the release workflows (Phase 6, docs/RELEASING.md). Needs gh with
# GH_TOKEN and GITHUB_REPOSITORY, as a workflow step has them. Tags come from
# release/feed.json (feed.py config manifestTag / signaturesTag).
#
#   gh-publish.sh fetch <tag> <file> <dir> [--no-sig]
#       download a published file and its .sig into <dir> through the API, so a
#       private repository works the same (ROADMAP §3); exit 1 when not published
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
	tag=$2 file=$3 dir=$4
	mkdir -p "$dir"
	rm -f "${dir:?}/$file" "${dir:?}/$file.sig"
	if ! gh release download "$tag" --repo "$GITHUB_REPOSITORY" --pattern "$file" --dir "$dir" 2>/dev/null \
		|| [ ! -f "$dir/$file" ]; then
		exit 1
	fi
	if [ "${5:-}" != --no-sig ]; then
		if ! gh release download "$tag" --repo "$GITHUB_REPOSITORY" --pattern "$file.sig" --dir "$dir" 2>/dev/null \
			|| [ ! -f "$dir/$file.sig" ]; then
			die "$tag/$file is published without its .sig"
		fi
	fi
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
			--title "$title" --notes "Files Lullaby.app downloads and checks against Lullaby's release key. Published by CI; see docs/RELEASING.md." \
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
check-repo)
	# The app trusts files only under the feed release/feed.json names; publishing
	# anywhere else would give it addresses it refuses.
	want=$(python3 -I "$here/feed.py" config repository)
	[ "$want" = "$GITHUB_REPOSITORY" ] \
		|| die "release/feed.json names $want, but this runs in $GITHUB_REPOSITORY; update the file first"
	;;
*)
	echo "usage: $0 fetch|verify|upload|issue|check-repo ..." >&2
	exit 2
	;;
esac
