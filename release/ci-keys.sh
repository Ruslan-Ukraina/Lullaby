#!/bin/sh
# Puts the signing keys of a CI run in files and their public halves in the
# environment (Phase 6, docs/RELEASING.md).
#
#   release/ci-keys.sh dry-run <dir>   the TEST keys (release/testkeys.swift)
#   release/ci-keys.sh release <dir>   the owner's keys, from GitHub secrets and variables
#
# Writes <dir>/release.key and <dir>/sparkle.key (mode 0600) and appends
# NP_RELEASE_KEY=… and SPARKLE_KEY=… (the public keys) to $GITHUB_ENV, or prints
# them without it. In release mode it reads
#   NP_RELEASE_PRIVATE_KEY, SPARKLE_PRIVATE_KEY   secrets: base64 private keys
#   NP_RELEASE_PUBLIC_KEY,  SPARKLE_PUBLIC_KEY    variables: the public keys
# and refuses a private key that does not belong to its public key, and any TEST key.
# Exit 3 in release mode when the secrets are not set up yet, so a scheduled run
# can skip instead of failing until the owner has added them.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
MODE=${1:?usage: ci-keys.sh dry-run|release <dir>}
DIR=${2:?usage: ci-keys.sh dry-run|release <dir>}

die() { echo "==> ci-keys: $*" >&2; exit 1; }
emit() { if [ -n "${GITHUB_ENV:-}" ]; then echo "$1=$2" >> "$GITHUB_ENV"; else echo "$1=$2"; fi; }
is_test_key() { grep -v '^#' "$here/test-public-keys.txt" | grep -qxF "$1"; }

umask 077
mkdir -p "$DIR"
rm -f "$DIR/release.key" "$DIR/sparkle.key"

case "$MODE" in
dry-run)
	release=$(swift "$here/testkeys.swift" release "$DIR/release.key")
	sparkle=$(swift "$here/testkeys.swift" sparkle "$DIR/sparkle.key")
	echo "==> ci-keys: TEST keys (release $release, Sparkle $sparkle); a release build refuses both"
	;;
release)
	if [ -z "${NP_RELEASE_PRIVATE_KEY:-}" ] || [ -z "${SPARKLE_PRIVATE_KEY:-}" ] \
		|| [ -z "${NP_RELEASE_PUBLIC_KEY:-}" ] || [ -z "${SPARKLE_PUBLIC_KEY:-}" ]; then
		echo "==> ci-keys: the release keys are not set up yet (docs/RELEASING.md, section 1)" >&2
		exit 3
	fi
	printf '%s\n' "$NP_RELEASE_PRIVATE_KEY" > "$DIR/release.key"
	printf '%s\n' "$SPARKLE_PRIVATE_KEY" > "$DIR/sparkle.key"
	release=$(swift "$here/sign.swift" "$DIR/release.key" --public 2>/dev/null) \
		|| die "NP_RELEASE_PRIVATE_KEY is not a base64 Ed25519 private key"
	sparkle=$(swift "$here/sign.swift" "$DIR/sparkle.key" --public 2>/dev/null) \
		|| die "SPARKLE_PRIVATE_KEY is not a base64 Ed25519 private key"
	[ "$release" = "$NP_RELEASE_PUBLIC_KEY" ] \
		|| die "NP_RELEASE_PRIVATE_KEY does not belong to NP_RELEASE_PUBLIC_KEY ($release)"
	[ "$sparkle" = "$SPARKLE_PUBLIC_KEY" ] \
		|| die "SPARKLE_PRIVATE_KEY does not belong to SPARKLE_PUBLIC_KEY ($sparkle)"
	[ "$release" != "$sparkle" ] || die "the release key and the Sparkle key are one key; make two"
	is_test_key "$release" && die "NP_RELEASE_PUBLIC_KEY is a TEST key"
	is_test_key "$sparkle" && die "SPARKLE_PUBLIC_KEY is a TEST key"
	echo "==> ci-keys: the owner's keys (release $release, Sparkle $sparkle)"
	;;
*) die "mode is '$MODE', expected dry-run or release" ;;
esac
emit NP_RELEASE_KEY "$release"
emit SPARKLE_KEY "$sparkle"
