#!/bin/sh
# Whether a scheduled check runs now: the cheap first job of dormison-bridge.yml and
# steam-signatures.yml, on a Linux runner, so the macOS job starts only when there
# is work (DECISIONS P6-13; macOS minutes cost ten times Linux ones in a private
# repository).
#
#   release/ci-gate.sh <steam|dormison>
#
# Reads GITHUB_EVENT_NAME, HOURS (a repository variable: run every HOURS hours,
# 0 = never by schedule), DEFAULT_HOURS, and CRON_HOURS: how often the workflow's
# cron fires (3 for Steam, 24 for Dormison). HOURS is rounded up to a multiple of
# CRON_HOURS; a cron that fires more often would bill a gate job each time.
# A dispatch or a tag always runs.
# On schedule it then looks for news without building anything:
#   steam     the stable and beta client builds Valve offers, against the builds
#             the published and the repository's signatures manifests list
#   dormison  the versions Dormison's channels name, against the engines the
#             published and the repository's bridge manifests have bridges for
# Prints run=true|false and a reason, for $GITHUB_OUTPUT.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
what=${1:?usage: ci-gate.sh steam|dormison}
hours=${HOURS:-}
[ -n "$hours" ] || hours=${DEFAULT_HOURS:-24}

say() { echo "run=$1"; echo "reason=$2"; exit 0; }

if [ "${GITHUB_EVENT_NAME:-}" != schedule ]; then
	say true "started by hand or by a tag"
fi
case "$hours" in ''|*[!0-9]*) say false "the schedule variable is '$hours', not a number of hours" ;; esac
[ "$hours" -gt 0 ] || say false "the schedule is off (0 hours)"
step=${CRON_HOURS:-1}
every=$(( (hours + step - 1) / step ))
now=$(( $(date -u +%s) / 3600 / step ))
[ $(( now % every )) -eq 0 ] || say false "not this time (every $(( every * step )) h)"
if [ -z "${NP_RELEASE_PRIVATE_KEY:-}" ]; then
	say false "the release keys are not set up yet (docs/RELEASING.md)"
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
manifest_tag=$(python3 -I "$here/feed.py" config manifestTag)

case "$what" in
steam)
	gh release download "$manifest_tag" --repo "$GITHUB_REPOSITORY" --pattern signatures-manifest.json \
		--dir "$tmp" 2>/dev/null || true
	for name in steam_client_osx steam_client_publicbeta_osx; do
		curl -fsSL --retry 3 -o "$tmp/$name" "https://client-update.akamai.steamstatic.com/$name" \
			|| say true "Valve's $name did not answer; the full check decides"
		build=$(python3 -I "$here/feed.py" valve-manifest "$tmp/$name" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["version"])')
		for m in "$repo/signatures/manifest.json" "$tmp/signatures-manifest.json"; do
			[ -f "$m" ] || continue
			if python3 -I -c 'import json,sys; sys.exit(0 if any(int(b["build"]) == int(sys.argv[2]) for b in json.load(open(sys.argv[1]))["builds"]) else 1)' "$m" "$build"; then
				continue 2
			fi
		done
		say true "Steam build $build ($name) has no database yet"
	done
	say false "every Steam build Valve offers has a database"
	;;
dormison)
	gh release download "$manifest_tag" --repo "$GITHUB_REPOSITORY" --pattern bridge-manifest.json \
		--dir "$tmp" 2>/dev/null || true
	engine=$(python3 -I "$here/feed.py" config engineManifest)
	curl -fsSL --retry 3 -o "$tmp/engine.json" "$engine" || say true "Dormison's manifest did not answer; the full check decides"
	for version in $(python3 -I "$here/feed.py" engine-versions "$tmp/engine.json" | cut -d' ' -f2); do
		for m in "$repo/bridge/bridge-manifest.json" "$tmp/bridge-manifest.json"; do
			[ -f "$m" ] || continue
			if python3 -I -c 'import json,sys; sys.exit(0 if any(e["engine"] == sys.argv[2] for e in json.load(open(sys.argv[1]))["bridges"]) else 1)' "$m" "$version"; then
				continue 2
			fi
		done
		say true "$version has no bridge yet"
	done
	say false "every Dormison release on a channel has a bridge"
	;;
*) echo "usage: $0 steam|dormison" >&2; exit 2 ;;
esac
