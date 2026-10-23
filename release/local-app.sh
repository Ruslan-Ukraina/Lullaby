#!/bin/sh
# A release of Lullaby.app from the owner's Mac (docs/RELEASING_LOCAL.md): what .github/workflows/release.yml did,
# without GitHub Actions. Builds, checks, archives, signs and writes the appcast. Publishes only with --yes.
#
#   release/local-app.sh <tag>            the release: kind release, the owner's keys (~/Lullaby-keys), the bridges
#                                         bridge/bridge-manifest.json names, fetched from the published release and
#                                         verified; everything is left in scratch/release/<version>/, nothing uploaded
#   release/local-app.sh <tag> --title "Lullaby r1"   the GitHub release's title (default "Lullaby <version>")
#   release/local-app.sh <tag> --yes      the same, then: the GitHub release <tag> with the zip, then the appcast.
#                                         The tag must already exist and be pushed (nothing here pushes)
#   release/local-app.sh --test [dir]     a rehearsal: kind test, TEST keys (a release build refuses them), the bridge
#                                         of a local feed (default scratch/local-bridge/dormison-r7/feed); nothing is
#                                         published and no key of the owner's is read
#
# Order of publishing is fixed: the zip first, the appcast after, so the app never reads an appcast naming a file
# that is not there. Keys are used from their files and never printed. RELEASE_KEY_FILE / SPARKLE_KEY_FILE override
# the paths. The build number is release/app-build.sh (it must stay above every published one).
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
cd "$root"

die() { echo "==> local-app: $*" >&2; exit 1; }
say() { echo "==> local-app: $*"; }

mode=release
yes=0
tag=
title=
bridge_src=
while [ $# -gt 0 ]; do
	case "$1" in
	--test) mode="test"; shift; case "${1:-}" in ''|--*) ;; *) bridge_src=$1; shift ;; esac ;;
	--yes) yes=1; shift ;;
	--title) title=${2:?--title needs a text}; shift 2 ;;
	-*) die "unknown option $1" ;;
	*) [ -z "$tag" ] || die "one tag only"; tag=$1; shift ;;
	esac
done
[ "$mode" = test ] && [ "$yes" = 1 ] && die "a rehearsal publishes nothing; --yes is for a release"
[ "$mode" = release ] && [ -z "$tag" ] && die "usage: release/local-app.sh <tag> [--yes] | --test [bridge feed dir]"

repo=$(python3 -I "$here/feed.py" config repository)
feed=$(python3 -I "$here/feed.py" config feed)
manifest_tag=$(python3 -I "$here/feed.py" config manifestTag)
appcast_name=$(python3 -I "$here/feed.py" config appcast)
access=$(python3 -I "$here/feed.py" config access)
appcast_url=$(python3 -I "$here/feed.py" config appcastURL)
export GITHUB_REPOSITORY="$repo"

base=$(sed -n 's/^#define LULLABY_VERSION "\(.*\)"/\1/p' steam/hook/version.h)
[ -n "$base" ] || die "no LULLABY_VERSION in steam/hook/version.h"
if [ "$mode" = test ]; then
	version="$base-dryrun.$(date +%Y%m%d%H%M)"
	kind="test"
	pre=true
	tag="dryrun-app-local"
else
	version=${tag#v}
	kind=release
	case "$version" in *-*) pre=true ;; *) pre=false ;; esac
	[ "${version%%-*}" = "$base" ] || die "the tag says $version, but steam/hook/version.h says $base"
fi
[ -n "$title" ] || title="Lullaby $version"
build=$("$here/app-build.sh")
out="$root/scratch/release/$version"
rm -rf "${out:?}"
mkdir -p "$out/keys" "$out/archives"
say "Lullaby $version, build $build, kind $kind$([ "$pre" = true ] && echo ', pre-release'), repository $repo ($access)"

# --- the tree must be what is released
if [ "$mode" = release ]; then
	[ -z "$(git status --porcelain)" ] || die "the working tree is not clean"
	if [ "$yes" = 1 ]; then
		git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "the tag $tag does not exist; create it (an annotated tag: its text is the release notes) and push it"
		[ "$(git rev-parse "$tag^{commit}")" = "$(git rev-parse HEAD)" ] || die "the tag $tag is not at HEAD"
		git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1 || die "the tag $tag is not on origin; push it first"
	fi
fi

# --- keys: public halves into the build, private ones stay in their files
if [ "$mode" = test ]; then
	eval "$("$here/ci-keys.sh" dry-run "$out/keys" | sed -nE 's/^(LB_RELEASE_KEY|SPARKLE_KEY)=(.*)$/export \1="\2"/p')"
	sparkle_key_file=$out/keys/sparkle.key
	release_key_file=$out/keys/release.key
else
	release_key_file=${RELEASE_KEY_FILE:-$HOME/Lullaby-keys/lullaby-release.key}
	sparkle_key_file=${SPARKLE_KEY_FILE:-$HOME/Lullaby-keys/lullaby-sparkle.key}
	[ -f "$release_key_file" ] || die "no release key at $release_key_file"
	[ -f "$sparkle_key_file" ] || die "no Sparkle key at $sparkle_key_file"
	LB_RELEASE_KEY=$(swift "$here/sign.swift" "$release_key_file" --public 2>/dev/null) || die "the release key file is not a base64 Ed25519 private key"
	SPARKLE_KEY=$(swift "$here/sign.swift" "$sparkle_key_file" --public 2>/dev/null) || die "the Sparkle key file is not a base64 Ed25519 private key"
	export LB_RELEASE_KEY SPARKLE_KEY
	[ "$LB_RELEASE_KEY" != "$SPARKLE_KEY" ] || die "the release key and the Sparkle key are one key"
	say "the owner's keys: release $LB_RELEASE_KEY, Sparkle $SPARKLE_KEY"
fi

# --- the bridges to bundle
bridge_dir="$out/bridge-feed"
mkdir -p "$bridge_dir"
restore_manifest=0
trap '[ "$restore_manifest" = 1 ] && git -C "$root" checkout -q -- bridge/bridge-manifest.json || true' EXIT
if [ "$mode" = test ]; then
	src=${bridge_src:-$root/scratch/local-bridge/dormison-r7/feed}
	[ -d "$src/manifest" ] || die "no local bridge feed at $src (release/local-bridge.sh builds one)"
	restore_manifest=1
	python3 -I - "$src/manifest/bridge-manifest.json" bridge/bridge-manifest.json <<'PY'
import json, sys
feed, repo = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
repo["bridges"] = feed["bridges"]
json.dump(repo, open(sys.argv[2], "w"), indent=2)
PY
	for id in $(python3 -I -c 'import json; [print(e["id"]) for e in json.load(open("bridge/bridge-manifest.json"))["bridges"]]'); do
		mkdir -p "$bridge_dir/$id"
		cp "$src/$id/$id.tar.xz" "$src/$id/$id.tar.xz.sig" "$bridge_dir/$id/"
		say "bridge $id from the local feed (TEST key)"
	done
else
	for id in $(python3 -I -c 'import json; [print(e["id"]) for e in json.load(open("bridge/bridge-manifest.json"))["bridges"]]'); do
		"$here/gh-publish.sh" fetch "$id" "$id.tar.xz" "$bridge_dir/$id" \
			|| die "the bridge $id is not published; build it (release/local-bridge.sh), publish it (release/local-publish.sh) and commit its entry into bridge/bridge-manifest.json"
		say "bridge $id (published)"
	done
fi
if [ "$mode" = test ]; then
	[ -f "$(dirname "$src")/public-key.txt" ] || die "no public-key.txt beside the local bridge feed"
	bridge_key=$(tr -d '\n' <"$(dirname "$src")/public-key.txt")
else
	bridge_key=$LB_RELEASE_KEY
fi
for sig in "$bridge_dir"/*/*.tar.xz.sig; do
	VERIFY=${VERIFY:-$out/verify-ed25519} "$here/gh-publish.sh" verify "$bridge_key" "${sig%.sig}" || die "a bridge's signature does not verify"
done

# --- build
say "building the dylib, the shim, the helpers"
make all overlay-shim iconmaker appinfo nvapi-shim >"$out/build-parts.log" 2>&1 || { tail -n 20 "$out/build-parts.log"; die "the parts did not build (log: $out/build-parts.log)"; }
say "building Lullaby.app"
rm -rf "$root/out/Lullaby.app"
make app LB_BUILD_KIND="$kind" LB_RELEASE_KEY="$LB_RELEASE_KEY" SPARKLE_KEY="$SPARKLE_KEY" APP_VERSION="$version" APP_BUILD="$build" \
	BRIDGE_FEED_DIR="$bridge_dir" >"$out/build-app.log" 2>&1 || { tail -n 20 "$out/build-app.log"; die "the app did not build (log: $out/build-app.log)"; }
app="$root/out/Lullaby.app"

# --- checks
LB_BUILD_KIND=$kind "$here/check-release.sh" bundle "$app"
if [ "$kind" = release ]; then
	# The same configuration with a TEST key must be refused.
	if LB_BUILD_KIND=release LB_RELEASE_KEY="$(swift "$here/testkeys.swift" release)" SPARKLE_KEY="$SPARKLE_KEY" APP_BUILD="$build" \
		LB_RELEASE_FEED="$feed" SPARKLE_FEED="$appcast_url" "$here/check-release.sh" config >/dev/null 2>&1; then
		die "a release configuration with the TEST key passed the check"
	fi
fi
say "the hermetic suites and the Swift tests"
make -s sigcheck callscheck webpatch-fixtures peicon-fixtures panel-behavior compatcheck compatsvc-check updategate-check \
	settingsbridge-check steamwin-check releasecheck >"$out/tests.log" 2>&1 || { tail -n 20 "$out/tests.log"; die "a suite failed (log: $out/tests.log)"; }
LB_REQUIRE_PAYLOAD=1 make -s app-tests >>"$out/tests.log" 2>&1 || { tail -n 20 "$out/tests.log"; die "the Swift tests failed (log: $out/tests.log)"; }

# --- archive, sign, appcast
sparkle_bin="$root/app/.build/artifacts/sparkle/Sparkle/bin"
[ -x "$sparkle_bin/generate_appcast" ] || swift package resolve --package-path app >/dev/null 2>&1
[ -x "$sparkle_bin/generate_appcast" ] || die "no Sparkle tools at $sparkle_bin"
arch="$out/archives"
zip="Lullaby-$version.zip"
ditto -c -k --keepParent "$app" "$arch/$zip"
notes=
if [ "$mode" = release ] && git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
	notes=$(git tag -l --format='%(contents)' "$tag" | sed '/^-----BEGIN PGP/,$d')
fi
[ -n "$notes" ] || notes="Lullaby $version."
printf '%s\n' "$notes" >"$arch/Lullaby-$version.md"
published="$out/published-appcast"
have_published=0
if [ "$mode" = release ] && "$here/gh-publish.sh" fetch "$manifest_tag" "$appcast_name" "$published" --no-sig; then
	cp "$published/$appcast_name" "$arch/appcast.xml"
	have_published=1
	say "adding to the published appcast"
elif [ "$mode" = release ]; then
	say "WARNING: no published appcast was read; this one starts with only $version"
fi
channel=
[ "$pre" = true ] && channel="--channel beta"
# shellcheck disable=SC2086
"$sparkle_bin/generate_appcast" --ed-key-file "$sparkle_key_file" --download-url-prefix "${feed}$tag/" \
	--embed-release-notes --maximum-versions 1000 $channel "$arch" >"$out/appcast.log" 2>&1 || { tail -n 20 "$out/appcast.log"; die "generate_appcast failed"; }
if [ "$have_published" = 1 ]; then
	# generate_appcast drops the items whose archives are not in the folder (every earlier release): put them
	# back, so a Mac that skipped a version still finds its way, then sign the edited appcast again.
	python3 -I - "$published/$appcast_name" "$arch/appcast.xml" <<'PY'
import re, sys
old, new = open(sys.argv[1]).read(), open(sys.argv[2]).read()
item = re.compile(r"<item>.*?</item>", re.S)
version = re.compile(r"<sparkle:version>([^<]+)</sparkle:version>")
have = {m.group(1) for m in version.finditer(new)}
kept = [i for i in item.findall(old) if (v := version.search(i)) and v.group(1) not in have]
if kept:
    new = new.replace("</channel>", "\n".join(kept) + "\n</channel>", 1)
    open(sys.argv[2], "w").write(new)
print(f"kept {len(kept)} earlier item(s)")
PY
	"$sparkle_bin/sign_update" --ed-key-file "$sparkle_key_file" "$arch/appcast.xml" >/dev/null
fi
grep -Eq "sparkle:version>$build<|sparkle:version=\"$build\"" "$arch/appcast.xml" || die "the appcast does not carry build $build"
grep -q "sparkle:edSignature" "$arch/appcast.xml" || die "the appcast is not signed"
"$sparkle_bin/sign_update" --verify --ed-key-file "$sparkle_key_file" "$arch/appcast.xml" >/dev/null || die "the appcast's signature does not verify"
say "archive and appcast are ready in $arch"

if [ "$yes" != 1 ]; then
	say "nothing was published ($([ "$mode" = test ] && echo 'a rehearsal' || echo 'no --yes'))"
	exit 0
fi

# --- publish: the release with the zip, then the appcast
pre_flag=
[ "$pre" = true ] && pre_flag=--prerelease
gh release create "$tag" --repo "$repo" --verify-tag $pre_flag --title "$title" \
	--notes-file "$arch/Lullaby-$version.md" "$arch/$zip" || die "cannot create the release $tag"
if [ "$access" = private ]; then
	# A private repository's download links need a browser session, so the enclosure points at the asset's
	# API address, which Sparkle reads with the user's token. The edit changes the appcast: sign it again.
	api=$(gh api "repos/$repo/releases/tags/$tag" --jq ".assets[] | select(.name == \"$zip\") | .url")
	[ -n "$api" ] || die "the uploaded $zip has no API address"
	python3 -I - "$arch/appcast.xml" "${feed}$tag/$zip" "$api" <<'PY'
import sys
path, public, api = sys.argv[1:4]
text = open(path).read()
if f'url="{public}"' not in text:
    sys.exit(f"{public} is not an enclosure of the appcast")
open(path, "w").write(text.replace(f'url="{public}"', f'url="{api}"'))
PY
	"$sparkle_bin/sign_update" --ed-key-file "$sparkle_key_file" "$arch/appcast.xml" >/dev/null
	"$sparkle_bin/sign_update" --verify --ed-key-file "$sparkle_key_file" "$arch/appcast.xml" >/dev/null || die "the edited appcast does not verify"
fi
cp "$arch/appcast.xml" "$out/$appcast_name"
"$here/gh-publish.sh" upload "$manifest_tag" "Signed manifests" "$out/$appcast_name"
"$here/gh-publish.sh" fetch "$manifest_tag" "$appcast_name" "$out/back" --no-sig
cmp "$out/back/$appcast_name" "$arch/appcast.xml" || die "the published appcast differs from the one signed"
"$here/gh-publish.sh" fetch "$tag" "$zip" "$out/back" --no-sig
cmp "$out/back/$zip" "$arch/$zip" || die "the published zip differs from the one built"
say "published $tag and the appcast ($access); both read back and match"
