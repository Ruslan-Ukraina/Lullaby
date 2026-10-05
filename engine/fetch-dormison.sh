#!/bin/sh
# Fetch, verify and unpack a Dormison engine release into the runners directory.
#
#   engine/fetch-dormison.sh              fetch and unpack the channel's release
#   engine/fetch-dormison.sh --activate   also point runners/current at it
#
# Nothing downloaded is trusted until it is checked:
#   1. engine.json against its Ed25519 signature (Dormison's published key);
#   2. the tarball against its own signature, and the sha256 and size the signed
#      manifest gives for it;
#   3. every unpacked file and link against engine-manifest.json from the tarball.
# Unpacking goes to runners/.<version>.partial, which is renamed into place only
# once all of that passed, so a runners/<version> directory is always complete.
# runners/current is switched by an atomic rename and the release it pointed at
# before stays on disk for rollback.
#
# Overridable: CHANNEL, RUNNERS, CACHE, MANIFEST_URL, DORMISON_PUBKEY
set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)

# Pinned in Sevoflurane's Core/Setup/EngineSignature.swift; the private half
# signs every Dormison release (build-macos/publish-engine.sh).
DORMISON_PUBKEY=${DORMISON_PUBKEY:-7uDuIZdCZyobjZcPL12zL+UNOCpHSvLXvVRFHA7bzzA=}
MANIFEST_URL=${MANIFEST_URL:-https://github.com/kageroumado/dormison/releases/download/manifest/engine.json}
# Release assets are accepted only from here, over https.
ASSET_PREFIX=https://github.com/kageroumado/dormison/releases/download/
CHANNEL=${CHANNEL:-beta}
CACHE=${CACHE:-$repo/scratch/engine}
RUNNERS=${RUNNERS:-$HOME/Library/Application Support/notproton/runners}
VERIFY=$repo/scratch/bin/verify-ed25519

activate=0
for arg in "$@"; do
	case "$arg" in
		--activate) activate=1 ;;
		*) echo "==> unknown argument $arg" >&2; exit 1 ;;
	esac
done

die() { echo "==> $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

mkdir -p "$CACHE" "$(dirname "$VERIFY")"
if [ ! -x "$VERIFY" ] || [ "$here/verify-ed25519.swift" -nt "$VERIFY" ]; then
	echo "==> building the signature checker"
	swiftc -O -o "$VERIFY" "$here/verify-ed25519.swift"
fi

# 1. The manifest, always fresh, and its signature.
echo "==> fetching $MANIFEST_URL"
curl -fsSL -o "$CACHE/engine.json.new" "$MANIFEST_URL"
curl -fsSL -o "$CACHE/engine.json.sig.new" "$MANIFEST_URL.sig"
"$VERIFY" "$DORMISON_PUBKEY" "$CACHE/engine.json.new" "$CACHE/engine.json.sig.new" \
	|| die "engine.json does not carry Dormison's signature, refusing it"
mv -f "$CACHE/engine.json.new" "$CACHE/engine.json"
mv -f "$CACHE/engine.json.sig.new" "$CACHE/engine.json.sig"

# shellcheck disable=SC2046 # four whitespace-free fields, split on purpose
set -- $(python3 - "$CACHE/engine.json" "$CHANNEL" <<'PY'
import json, re, sys
m = json.load(open(sys.argv[1]))
if m.get("schema") != 2:
    raise SystemExit(f"manifest schema {m.get('schema')}, expected 2")
c = m.get("channels", {}).get(sys.argv[2])
if not c:
    raise SystemExit(f"channel {sys.argv[2]} is empty")
v, url, sha, size = c["version"], c["url"], c["sha256"], int(c["sizeBytes"])
if not re.fullmatch(r"dormison-[A-Za-z0-9.]+", v):
    raise SystemExit(f"unexpected version name {v!r}")
if not re.fullmatch(r"[0-9a-f]{64}", sha):
    raise SystemExit(f"unexpected sha256 {sha!r}")
print(v, url, sha, size)
PY
)
[ $# -eq 4 ] || die "could not read the $CHANNEL channel from engine.json"
version=$1 url=$2 want_sha=$3 want_size=$4
case "$url" in
	"$ASSET_PREFIX"*) ;;
	*) die "$url is not a Dormison release asset, refusing it" ;;
esac
echo "==> $CHANNEL channel: $version, $want_size bytes, sha256 $want_sha"

# 2. The tarball, resumed if a previous download was cut short.
tarball=$CACHE/${url##*/}
if [ -f "$tarball" ] && [ "$(stat -f %z "$tarball")" = "$want_size" ] \
	&& [ "$(sha "$tarball")" = "$want_sha" ]; then
	echo "==> $tarball already downloaded"
else
	[ -f "$tarball" ] && mv -f "$tarball" "$tarball.part"
	echo "==> downloading $url"
	curl -fL --retry 5 -C - -o "$tarball.part" "$url"
	mv -f "$tarball.part" "$tarball"
fi
curl -fsSL -o "$tarball.sig" "$url.sig"

got_size=$(stat -f %z "$tarball")
[ "$got_size" = "$want_size" ] || die "$tarball is $got_size bytes, the manifest says $want_size"
got_sha=$(sha "$tarball")
[ "$got_sha" = "$want_sha" ] || die "$tarball sha256 is $got_sha, the manifest says $want_sha"
"$VERIFY" "$DORMISON_PUBKEY" "$tarball" "$tarball.sig" \
	|| die "$tarball does not carry Dormison's signature, refusing it"
echo "==> tarball verified: signature, sha256 and size"

# 3. Unpack beside the destination, check every entry, then rename into place.
mkdir -p "$RUNNERS"
dest=$RUNNERS/$version
if [ -d "$dest" ]; then
	echo "==> $dest already unpacked, leaving it alone"
else
	partial=$RUNNERS/.$version.partial
	rm -rf "$partial"
	mkdir -p "$partial"
	# bsdtar refuses absolute paths and .. components unless told otherwise (-P).
	tar -xJf "$tarball" -C "$partial" --strip-components 1 "$version/"
	echo "==> unpacked into $partial, checking it against engine-manifest.json"
	python3 - "$partial" "$version" <<'PY'
import hashlib, json, os, sys
root, version = sys.argv[1], sys.argv[2]
m = json.load(open(os.path.join(root, "engine-manifest.json")))
if m.get("version") != version:
    raise SystemExit(f"engine-manifest.json is {m.get('version')}, expected {version}")
if m.get("source", {}).get("dirty"):
    raise SystemExit("engine-manifest.json records a dirty source tree")
info = json.load(open(os.path.join(root, "engine-info.json")))
if info.get("version") != version:
    raise SystemExit(f"engine-info.json is {info.get('version')}, expected {version}")
if info.get("commit") != m["source"]["head"]:
    raise SystemExit("engine-info.json and engine-manifest.json name different commits")
listed, bad = set(), []
for c in m["components"]:
    path = os.path.join(root, c["path"])
    listed.add(os.path.normpath(c["path"]))
    if "link" in c:
        if not os.path.islink(path) or os.readlink(path) != c["link"]:
            bad.append(f"{c['path']}: expected a link to {c['link']}")
        continue
    if os.path.islink(path) or not os.path.isfile(path):
        bad.append(f"{c['path']}: missing")
        continue
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    if h.hexdigest() != c["sha256"]:
        bad.append(f"{c['path']}: sha256 {h.hexdigest()}, manifest {c['sha256']}")
extra = []
for d, dirs, files in os.walk(root):
    for name in files + [x for x in dirs if os.path.islink(os.path.join(d, x))]:
        rel = os.path.normpath(os.path.relpath(os.path.join(d, name), root))
        if rel not in listed and rel != "engine-manifest.json":
            extra.append(rel)
if bad:
    print("\n".join(bad[:20]), file=sys.stderr)
    raise SystemExit(f"{len(bad)} entries do not match engine-manifest.json")
if extra:
    print("\n".join(extra[:20]), file=sys.stderr)
    raise SystemExit(f"{len(extra)} files are not in engine-manifest.json")
print(f"==> {len(m['components'])} entries match engine-manifest.json "
      f"({version}, commit {m['source']['head'][:12]})")
PY
	mv "$partial" "$dest"
	echo "==> installed $dest"
fi

[ "$activate" -eq 1 ] || { echo "==> not switching runners/current, pass --activate"; exit 0; }

# 4. Point runners/current at it with a rename, so it is never missing or half
# written. The previous target stays on disk.
previous=$(readlink "$RUNNERS/current" 2>/dev/null || true)
if [ "$previous" = "$version" ]; then
	echo "==> runners/current already points at $version"
	exit 0
fi
python3 - "$RUNNERS" "$version" <<'PY'
import os, sys
runners, version = sys.argv[1], sys.argv[2]
tmp = os.path.join(runners, ".current.new")
if os.path.lexists(tmp):
    os.unlink(tmp)
os.symlink(version, tmp)
os.replace(tmp, os.path.join(runners, "current"))
PY
echo "==> runners/current -> $version${previous:+ (was $previous, kept for rollback)}"
