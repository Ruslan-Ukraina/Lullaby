#!/bin/sh
# New macOS Steam builds -> signature databases (Phase 6, docs/BACKLOG.md 22).
#
#   release/steam-signatures.sh <work dir> <feed dir> <feed base url> [<published manifest> [<published dbs dir>]]
#
# For the stable and the publicbeta client: fetch it (release/steam-client.sh),
# skip it when a manifest already lists its build, otherwise cut a database for it
# with out/sigslice from the newest database that slices cleanly, and accept the
# result only if out/anchorcheck, given that database alone, exits 0 (every anchor
# resolved, every recorded address and pattern on it). The accepted ones go into a
# new signatures manifest in <feed dir> (release/feed.py publish-signatures); the
# caller signs and uploads it.
#
# Writes <work>/summary.md, and <work>/result with lines
#   new <build> <channel>          a database was cut and checked
#   failed <build> <channel>       a build needs a person (its logs are in <work>)
#   nox86 <build> <channel>        steamclient.dylib lost its x86_64 half (BACKLOG 24)
# Exit 0 when nothing failed, 1 when a build needs a person (the others are still
# published), 2 when the run itself broke.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
WORK=${1:?usage}; FEED_DIR=${2:?usage}; FEED=${3:?usage}
CURRENT=${4:-}; PUBLISHED_DBS=${5:-}
SIGSLICE=$repo/out/sigslice
ANCHORCHECK=$repo/out/anchorcheck

mkdir -p "$WORK"
rm -f "$WORK"/[0-9]*.json      # a database from an earlier run is not this run's
: > "$WORK/result"
: > "$WORK/summary.md"
[ -x "$SIGSLICE" ] && [ -x "$ANCHORCHECK" ] || { echo "==> run: make out/sigslice out/anchorcheck" >&2; exit 2; }

listed() { # build -> 0 when a manifest already names it
	for m in "$repo/signatures/manifest.json" $CURRENT; do
		[ -f "$m" ] || continue
		python3 -I -c 'import json,sys; sys.exit(0 if any(int(b["build"]) == int(sys.argv[2]) for b in json.load(open(sys.argv[1]))["builds"]) else 1)' \
			"$m" "$1" && return 0
	done
	return 1
}

# Newest database first, by the build in its name; published ones count too.
bases() {
	find "$repo/signatures/macos.arm64" ${PUBLISHED_DBS:+"$PUBLISHED_DBS"} -maxdepth 1 -name '[0-9]*.json' 2>/dev/null \
		| awk -F/ '{ n = $NF; sub(/\.json$/, "", n); print n "\t" $0 }' | sort -rn | cut -f2 | awk '!seen[$0]++'
}

today=$(date -u +%Y-%m-%d)
set --                      # collects publish-signatures arguments from here on
failed=0
for channel in stable publicbeta; do
	cw="$WORK/$channel"
	rc=0
	"$here/steam-client.sh" "$channel" "$cw" > "$cw.client.log" 2>&1 || rc=$?
	if [ "$rc" -ne 0 ] && [ "$rc" -ne 4 ]; then
		echo "==> $channel: cannot fetch the client, see $cw.client.log" >&2
		tail -5 "$cw.client.log" >&2
		echo "- $channel: the client could not be fetched or verified (\`$(tail -1 "$cw.client.log")\`)" >> "$WORK/summary.md"
		echo "failed unknown $channel" >> "$WORK/result"
		failed=1
		continue
	fi
	build=$(cat "$cw/build")
	if [ "$rc" -eq 4 ]; then
		echo "nox86 $build $channel" >> "$WORK/result"
		echo "- $channel $build: **steamclient.dylib has no x86_64 half**; Steamworks in games will break (BACKLOG 24)" >> "$WORK/summary.md"
	fi
	if listed "$build"; then
		echo "==> $channel: build $build is already supported"
		echo "- $channel $build: already supported" >> "$WORK/summary.md"
		continue
	fi
	if [ -f "$WORK/$build.json" ]; then
		echo "==> $channel: build $build was cut above (same build as the other channel)"
		continue
	fi
	cut=""
	for base in $(bases); do
		if HOME="$cw/home" "$SIGSLICE" "$base" "$build" "$WORK/$build.raw.json" > "$cw.slice.log" 2>&1; then
			cut=$base
			break
		fi
		echo "==> $channel $build: ${base##*/} does not slice cleanly ($(tail -2 "$cw.slice.log" | head -1))"
	done
	if [ -z "$cut" ]; then
		echo "failed $build $channel" >> "$WORK/result"
		{
			echo "- $channel $build: **no database slices cleanly**; a person has to cut one (BACKLOG 22). Last attempt:"
			echo '```'
			grep -E "NEEDS A PERSON|signatures," "$cw.slice.log" | head -20
			echo '```'
		} >> "$WORK/summary.md"
		failed=1
		continue
	fi
	python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); f=open(sys.argv[2],"w"); json.dump(d,f,indent=2); f.write("\n")' \
		"$WORK/$build.raw.json" "$WORK/$build.json"
	rm -f "$WORK/$build.raw.json"
	if ! HOME="$cw/home" "$ANCHORCHECK" "$WORK/$build.json" > "$cw.anchorcheck.log" 2>&1; then
		echo "failed $build $channel" >> "$WORK/result"
		{
			echo "- $channel $build: cut from ${cut##*/}, but **anchorcheck rejects it**:"
			echo '```'
			grep -E "WRONG|FAILED|DISAGREES|PATTERN|wrong|unresolved" "$cw.anchorcheck.log" | head -20
			echo '```'
		} >> "$WORK/summary.md"
		rm -f "$WORK/$build.json"
		failed=1
		continue
	fi
	resolved=$(sed -n 's/^ *\([0-9]*\) anchors resolved, \([0-9]*\) unresolved.*/\1\/\1/p' "$cw.anchorcheck.log" | head -1)
	patterns=$(sed -n 's/^\([0-9]*\) signatures, \([0-9]*\) new patterns.*/\2/p' "$cw.slice.log")
	checked="$today CI anchorcheck: $resolved anchors and recorded addresses, cut from ${cut##*/} ($patterns new patterns)"
	echo "new $build $channel" >> "$WORK/result"
	echo "- $channel $build: database cut from ${cut##*/}, $patterns new patterns; anchorcheck: all anchors, addresses and patterns agree" >> "$WORK/summary.md"
	set -- "$@" --add-db "$WORK/$build.json" --add-build "$build=$build.json:$checked"
	echo "==> $channel: build $build cut from ${cut##*/} and checked"
done

if [ $# -gt 0 ]; then
	python3 -I "$here/feed.py" publish-signatures --repo "$repo/signatures/manifest.json" \
		--dir "$repo/signatures/macos.arm64" --feed "$FEED" --out "$FEED_DIR" \
		--tag "$(python3 -I "$here/feed.py" config signaturesTag)" \
		${CURRENT:+--current "$CURRENT"} "$@"
fi
exit "$failed"
