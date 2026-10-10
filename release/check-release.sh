#!/bin/sh
# Guards for a release build of Lullaby.app (Phase 6, docs/RELEASING.md).
#
#   check-release.sh config        before the build: the make variables a build of
#                                  kind LB_BUILD_KIND is about to bake in
#   check-release.sh bundle <app>  after the build: what the bundle actually carries
#
# A release build (LB_BUILD_KIND=release) needs the owner's keys, never a TEST key
# (release/test-public-keys.txt), https feeds, and no development switches: the
# Steam Helper debug channel (BACKLOG 20) is compiled in only with LB_DEV=1, and
# its file name must not appear in the shipped dylib. A test build (dry run) must
# carry TEST keys only, so it can never pass for a release. A dev build is checked
# for nothing but the debug channel, and only when LB_DEV is not set.
#
# Reads LB_BUILD_KIND, LB_DEV, LB_RELEASE_KEY, LB_RELEASE_FEED, SPARKLE_KEY and
# SPARKLE_FEED from the environment (make exports them for this script).
set -eu

here=$(cd "$(dirname "$0")" && pwd)
TEST_KEYS="$here/test-public-keys.txt"
KIND=${LB_BUILD_KIND:-dev}

die() { echo "==> release check: $*" >&2; exit 1; }
is_test_key() { [ -n "$1" ] && grep -v '^#' "$TEST_KEYS" | grep -qxF "$1"; }
is_key() { [ "$(printf '%s' "$1" | base64 -d 2>/dev/null | wc -c | tr -d ' ')" = 32 ]; }

check_keys() { # kind release-key sparkle-key release-feed sparkle-feed
	case "$1" in
	release)
		[ -n "$2" ] || die "a release build needs LB_RELEASE_KEY (the owner's public release key)"
		[ -n "$3" ] || die "a release build needs SPARKLE_KEY (the owner's public Sparkle key)"
		is_key "$2" || die "LB_RELEASE_KEY is not a base64 Ed25519 public key"
		is_key "$3" || die "SPARKLE_KEY is not a base64 Ed25519 public key"
		is_test_key "$2" && die "LB_RELEASE_KEY is a TEST key; a release build refuses it"
		is_test_key "$3" && die "SPARKLE_KEY is a TEST key; a release build refuses it"
		[ "$2" != "$3" ] || die "the release key and the Sparkle key are the same key; use two"
		case "$4" in https://*) ;; *) die "LB_RELEASE_FEED must be https, not '$4'" ;; esac
		case "$5" in https://*) ;; *) die "SPARKLE_FEED must be https, not '$5'" ;; esac
		;;
	test)
		for k in "$2" "$3"; do
			[ -z "$k" ] || is_test_key "$k" || die "a test build takes TEST keys only, not $k"
		done
		;;
	dev) ;;
	*) die "LB_BUILD_KIND is '$1', expected release, test or dev" ;;
	esac
}

plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null || true; }

case "${1:-}" in
config)
	if [ "$KIND" = release ] && [ "${LB_DEV:-}" = 1 ]; then
		die "LB_DEV=1 builds the Steam Helper debug channel in; never in a release"
	fi
	check_keys "$KIND" "${LB_RELEASE_KEY:-}" "${SPARKLE_KEY:-}" "${LB_RELEASE_FEED:-}" "${SPARKLE_FEED:-}"
	echo "==> release check: $KIND build configuration ok"
	;;
bundle)
	app=${2:?usage: check-release.sh bundle <Lullaby.app>}
	kind=$(plist "$app" LBBuildKind)
	[ "$kind" = "$KIND" ] || die "$app says LBBuildKind '$kind', expected '$KIND'"
	check_keys "$kind" "$(plist "$app" LBReleasePublicKey)" "$(plist "$app" SUPublicEDKey)" \
		"$(plist "$app" LBReleaseFeedURL)" "$(plist "$app" SUFeedURL)"
	if [ "$KIND" != dev ] || [ "${LB_DEV:-}" != 1 ]; then
		found=$(find "$app" -name lullaby.dylib -type f)
		[ -n "$found" ] || die "no lullaby.dylib in $app"
		for dylib in $found; do
			if strings -a "$dylib" | grep -q steam-windows-debug; then
				die "$dylib carries the Steam Helper debug channel (BACKLOG 20)"
			fi
		done
	fi
	if [ "$KIND" = release ]; then
		# ROADMAP §9.5: no background checks; the window looks when it opens.
		[ "$(plist "$app" SUEnableAutomaticChecks)" = false ] || die "a release build must not check for updates in the background"
		[ "$(plist "$app" SURequireSignedFeed)" = true ] || die "a release build requires a signed appcast"
	fi
	codesign --verify --strict "$app" || die "$app: the code signature does not verify"
	echo "==> release check: $app is a sound $KIND build ($(plist "$app" CFBundleShortVersionString), build $(plist "$app" CFBundleVersion))"
	;;
*)
	echo "usage: $0 config | bundle <Lullaby.app>" >&2
	exit 2
	;;
esac
