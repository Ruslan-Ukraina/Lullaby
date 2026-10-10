#!/usr/bin/env python3
"""Lullaby's release feed: what the app carries and what the fork publishes (Phase 5).

Staging into the app payload (make app-payload):

    feed.py stage-bridge <bridge/bridge-manifest.json> <B1 build dir> <payload>
    feed.py stage-signatures <signatures/manifest.json> <signatures/macos.arm64> <payload>

Publishing (CI in Phase 6, or a local test feed; signing is release/sign.swift):

    feed.py bridge-artifact --manifest bridge/bridge-manifest.json --like bridge-dormison-b1-1 \
        --root <payload> --rev 2 --feed <base url> --out <feed dir>
    feed.py bridge-manifest --serial N --out <feed dir>/manifest/bridge-manifest.json <entry.json>...
    feed.py signatures --manifest signatures/manifest.json --dir signatures/macos.arm64 \
        --feed <base url> --serial N --out <feed dir> [--drop-build B]...

Phase 6 CI (.github/workflows, docs/RELEASING.md):

    feed.py valve-manifest <steam_client[_publicbeta]_osx>        version and packages, as JSON
    feed.py engine-versions <engine.json>                          "<channel> <version>" lines
    feed.py config <key>                                           a value of release/feed.json
    feed.py bridge-artifact --files-dir <dir> --b1-dir <dir> --engine E --commit C --rev N \
        --feed <base url> --out <feed dir>                         a bridge built from source
    feed.py publish-bridges --repo bridge/bridge-manifest.json [--current <published>] \
        --out <feed dir>/manifest/bridge-manifest.json <entry.json>...
    feed.py publish-signatures --repo signatures/manifest.json --dir signatures/macos.arm64 \
        [--current <published>] [--add-db <file>] [--add-build B=<db file>:<checked>]... \
        --feed <base url> --out <feed dir>
    feed.py stage-bridge --from-feed <dir with <id>/<id>.tar.xz> ...   bundle a published bridge

The feed directory mirrors GitHub's release downloads: <base>/<tag>/<file>.
Manifests: <tag> = manifest; a bridge build: <tag> = its id; databases: <tag> = signatures.
A published manifest's serial is one more than the larger of the published one and
the repository's, so the app, which refuses a serial lower than one it has seen,
always takes it.
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

BRIDGE_FILES = [
    "steam.exe",
    "x86_64-windows-lsteamclient.dll",
    "x86_64-unix-lsteamclient.so",
    "i386-windows-lsteamclient.dll",
]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def safe(rel):
    if not rel or rel.startswith("/") or ".." in rel.split("/"):
        raise SystemExit(f"{rel}: unsafe path")
    return rel


def load(path, schema=1):
    data = json.load(open(path))
    if data.get("schema") != schema:
        raise SystemExit(f"{path}: schema {data.get('schema')}, expected {schema}")
    return data


def write_json(path, data):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".new"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, path)


def copy_checked(src, dst, want):
    got = sha256(src)
    if got != want:
        raise SystemExit(f"{src}: sha256 {got}, expected {want}")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst + ".new")
    os.replace(dst + ".new", dst)


def unpack_bridge(tarball, entry, into):
    """A published bridge tarball, checked against its manifest entry, unpacked under `into`."""
    got = sha256(tarball)
    if got != entry.get("sha256"):
        raise SystemExit(f"{tarball}: sha256 {got}, the manifest says {entry.get('sha256')}")
    os.makedirs(into, exist_ok=True)
    subprocess.run(["tar", "-xJf", tarball, "-C", into], check=True)
    top = os.path.join(into, entry["id"])
    present = sorted(os.path.relpath(os.path.join(d, n), top)
                     for d, _, names in os.walk(top) for n in names)
    listed = sorted([f["path"] for f in entry["files"]] + [n["file"] for n in entry["ntdll"]]
                    + [e["file"] for e in entry.get("engineFiles", [])])
    if present != listed:
        raise SystemExit(f"{tarball}: holds {present}, the manifest lists {listed}")
    for f in entry["files"]:
        if sha256(os.path.join(top, safe(f["path"]))) != f["sha256"]:
            raise SystemExit(f"{entry['id']}: {f['path']} does not match the manifest")
    for n in entry["ntdll"]:
        if sha256(os.path.join(top, safe(n["file"]))) != n["b1"]:
            raise SystemExit(f"{entry['id']}: {n['file']} does not match the manifest")
    for e in entry.get("engineFiles", []):
        if sha256(os.path.join(top, safe(e["file"]))) != e["patched"]:
            raise SystemExit(f"{entry['id']}: {e['file']} does not match the manifest")
    return top


def stage_bridge(args):
    manifest = load(args.manifest)
    if args.from_feed:
        # A release bundles bridges the bridge workflow published, byte for byte:
        # a PE rebuild differs in its timestamp, so a rebuild is never the same bridge.
        for entry in manifest["bridges"]:
            if not entry.get("url") or not entry.get("sha256"):
                raise SystemExit(f"{entry['id']} is not published (no url/sha256 in {args.manifest}); "
                                 "a release bundles only published bridges")
            tarball = os.path.join(args.from_feed, entry["id"], f"{entry['id']}.tar.xz")
            top = unpack_bridge(tarball, entry, os.path.join(args.from_feed, ".unpacked"))
            for f in entry["files"]:
                copy_checked(os.path.join(top, f["path"]),
                             os.path.join(args.payload, "bridge", f["name"]), f["sha256"])
            if entry.get("engineFiles"):
                # Engine fixes are Mach-O, which SwiftPM strips (RISKS R27): the tarball
                # itself goes in, and the app unpacks and checks it (DECISIONS P8-17).
                copy_checked(tarball, os.path.join(args.payload, "engine-support", f"{entry['id']}.tar.xz"),
                             entry["sha256"])
                continue
            for n in entry["ntdll"]:
                copy_checked(os.path.join(top, n["file"]), os.path.join(
                    args.payload, "engine-support", entry["engine"], f"{n['arch']}-ntdll.dll"), n["b1"])
        # The bundled form (DECISIONS P5-1): no download, and no sha256 per file,
        # since SwiftPM strips Mach-O resources in a release build (RISKS R27). The
        # bytes were checked above; the app's code signature covers them from here.
        # A packed bridge keeps its tarball's layout and digests, checked when unpacked.
        def bundled_entry(e):
            rest = {k: v for k, v in e.items() if k not in ("url", "sha256", "sizeBytes")}
            if e.get("engineFiles"):
                return {**rest, "archive": {"path": f"engine-support/{e['id']}.tar.xz",
                                            "sha256": e["sha256"], "sizeBytes": e["sizeBytes"]}}
            return {**rest,
                    "files": [{"name": f["name"], "path": f"bridge/{f['name']}"} for f in e["files"]],
                    "ntdll": [{**n, "file": f"engine-support/{e['engine']}/{n['arch']}-ntdll.dll"} for n in e["ntdll"]]}
        bundled = {**manifest, "bridges": [bundled_entry(e) for e in manifest["bridges"]]}
        write_json(os.path.join(args.payload, "engine-support", "bridge-manifest.json"), bundled)
        print(f"==> staged published bridge {', '.join(e['id'] for e in manifest['bridges'])}")
        return
    for entry in manifest["bridges"]:
        names = sorted(f["name"] for f in entry["files"])
        if names != sorted(BRIDGE_FILES):
            raise SystemExit(f"{entry['id']}: files {names}, expected {sorted(BRIDGE_FILES)}")
        for f in entry["files"]:
            if not os.path.isfile(os.path.join(args.payload, safe(f["path"]))):
                raise SystemExit(f"{entry['id']}: {f['path']} is not staged, run make bridge")
        for item in entry["ntdll"]:
            rel = safe(item["file"])
            dst = os.path.join(args.payload, rel)
            # engine-support/<engine>/<arch>-ntdll.dll comes from <B1 build dir>/<engine>/<arch>-ntdll.dll
            src = os.path.join(args.b1, rel.split("/", 1)[1] if rel.startswith("engine-support/") else rel)
            if os.path.isfile(src):
                copy_checked(src, dst, item["b1"])
            elif os.path.isfile(dst) and sha256(dst) == item["b1"]:
                print(f"==> keeping staged {rel}")
            else:
                raise SystemExit(f"{src} is missing and nothing is staged, run ntdll-patch/b1/build-b1.sh")
    out = os.path.join(args.payload, "engine-support", "bridge-manifest.json")
    write_json(out, manifest)
    stale = os.path.join(args.payload, "engine-support", "support.json")
    if os.path.exists(stale):
        os.remove(stale)
    print(f"==> staged bundled bridge {', '.join(e['id'] for e in manifest['bridges'])}")


def stage_signatures(args):
    manifest = load(args.manifest)
    listed = {d["file"]: d["sha256"] for d in manifest["databases"]}
    present = sorted(n for n in os.listdir(args.dir) if n.endswith(".json"))
    if sorted(listed) != present:
        raise SystemExit(f"{args.manifest} lists {sorted(listed)}, {args.dir} has {present}")
    for name, want in listed.items():
        got = sha256(os.path.join(args.dir, name))
        if got != want:
            raise SystemExit(f"{name}: sha256 {got}, {args.manifest} says {want} (update the manifest)")
    for build in manifest["builds"]:
        if build["database"] not in listed:
            raise SystemExit(f"build {build['build']} names {build['database']}, which is not listed")
    write_json(os.path.join(args.payload, "signatures", "manifest.json"), manifest)
    print(f"==> staged signatures manifest: {len(listed)} databases, {len(manifest['builds'])} builds")


def bridge_from_build(args):
    """A bridge for engine `args.engine` from a CI build: the four files and build-b1.sh's output."""
    b1 = json.load(open(os.path.join(args.b1_dir, "b1.json")))
    if b1["engine"] != args.engine or b1["commit"] != args.commit:
        raise SystemExit(f"b1.json is for {b1['engine']} {b1['commit']}, not {args.engine} {args.commit}")
    new_id = f"bridge-{args.engine}-{args.rev}"
    feed = args.feed if args.feed.endswith("/") else args.feed + "/"
    with tempfile.TemporaryDirectory() as tmp:
        top = os.path.join(tmp, new_id)
        os.makedirs(os.path.join(top, "ntdll"))
        files, ntdll = [], []
        for name in BRIDGE_FILES:
            dst = os.path.join(top, name)
            shutil.copyfile(os.path.join(args.files_dir, name), dst)
            os.chmod(dst, 0o755)
            files.append({"name": name, "path": name, "sha256": sha256(dst)})
        for arch in ("x86_64", "i386"):
            rel_engine = f"wine/lib/wine/{arch}-windows/ntdll.dll"
            pins = b1["files"][rel_engine]
            rel = f"ntdll/{arch}-ntdll.dll"
            copy_checked(os.path.join(args.b1_dir, f"{arch}-ntdll.dll"), os.path.join(top, rel), pins["b1"])
            ntdll.append({"arch": arch, "path": rel_engine, "file": rel, "clean": pins["clean"], "b1": pins["b1"]})
        engine_files = []
        if args.fixes_dir:
            fixes = json.load(open(os.path.join(args.fixes_dir, "fixes.json")))
            if fixes["engine"] != args.engine or fixes["commit"] != args.commit:
                raise SystemExit(f"fixes.json is for {fixes['engine']} {fixes['commit']}, not {args.engine} {args.commit}")
            for rel_engine, pins in sorted(fixes["files"].items()):
                rel = f"engine/{os.path.basename(rel_engine)}"
                copy_checked(os.path.join(args.fixes_dir, pins["file"]), os.path.join(top, rel), pins["patched"])
                engine_files.append({"path": rel_engine, "file": rel, "clean": pins["clean"],
                                     "patched": pins["patched"], "patches": pins["patches"]})
        out_dir = os.path.join(args.out, new_id)
        os.makedirs(out_dir, exist_ok=True)
        tarball = os.path.join(out_dir, f"{new_id}.tar.xz")
        subprocess.run(["tar", "-cJf", tarball, "-C", tmp, new_id], check=True,
                       env={**os.environ, "COPYFILE_DISABLE": "1"})
    entry = {
        "id": new_id, "engine": args.engine, "engineCommit": args.commit, "rev": args.rev,
        "patch": b1["patch"], "patchSha256": b1["patchSha256"],
        "files": files, "ntdll": ntdll,
        **({"engineFiles": engine_files} if engine_files else {}),
        **({"engineRelease": engine_release(args.engine_json, args.engine)} if args.engine_json else {}),
        "url": f"{feed}{new_id}/{new_id}.tar.xz",
        "sha256": sha256(tarball), "sizeBytes": os.path.getsize(tarball),
    }
    write_json(os.path.join(args.out, f"{new_id}.entry.json"), entry)
    print(f"==> {tarball} ({entry['sizeBytes']} bytes, sha256 {entry['sha256']})")


def engine_release(engine_json, version):
    """Where Dormison's `version` is downloaded from, as its (already verified) engine.json says.
    engine.json names only the newest release, so the bridge keeps this for later (DECISIONS P8-17)."""
    for channel in json.load(open(engine_json))["channels"].values():
        if channel.get("version") == version:
            return {k: channel[k] for k in ("url", "sha256", "sizeBytes")}
    raise SystemExit(f"{engine_json} does not name {version}")


def bridge_artifact(args):
    if args.files_dir:
        return bridge_from_build(args)
    manifest = load(args.manifest)
    like = next((e for e in manifest["bridges"] if e["id"] == args.like), None)
    if like is None:
        raise SystemExit(f"{args.like} is not in {args.manifest}")
    engine = args.engine or like["engine"]
    commit = args.commit or like["engineCommit"]
    new_id = f"bridge-{engine}-{args.rev}"
    feed = args.feed if args.feed.endswith("/") else args.feed + "/"
    with tempfile.TemporaryDirectory() as tmp:
        top = os.path.join(tmp, new_id)
        files, ntdll = [], []
        for f in like["files"]:
            dst = os.path.join(top, f["name"])
            os.makedirs(top, exist_ok=True)
            shutil.copyfile(os.path.join(args.root, safe(f["path"])), dst)
            os.chmod(dst, 0o755)
            files.append({"name": f["name"], "path": f["name"], "sha256": sha256(dst)})
        for item in like["ntdll"]:
            rel = f"ntdll/{item['arch']}-ntdll.dll"
            dst = os.path.join(top, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            copy_checked(os.path.join(args.root, safe(item["file"])), dst, item["b1"])
            ntdll.append({**{k: item[k] for k in ("arch", "path", "clean", "b1")}, "file": rel})
        out_dir = os.path.join(args.out, new_id)
        os.makedirs(out_dir, exist_ok=True)
        tarball = os.path.join(out_dir, f"{new_id}.tar.xz")
        subprocess.run(["tar", "-cJf", tarball, "-C", tmp, new_id], check=True,
                       env={**os.environ, "COPYFILE_DISABLE": "1"})
    entry = {
        "id": new_id, "engine": engine, "engineCommit": commit, "rev": args.rev,
        "files": files, "ntdll": ntdll,
        "url": f"{feed}{new_id}/{new_id}.tar.xz",
        "sha256": sha256(tarball), "sizeBytes": os.path.getsize(tarball),
    }
    for key in ("patch", "patchSha256"):
        if key in like:
            entry[key] = like[key]
    write_json(os.path.join(args.out, f"{new_id}.entry.json"), entry)
    print(f"==> {tarball} ({entry['sizeBytes']} bytes, sha256 {entry['sha256']})")


def bridge_manifest(args):
    entries = [json.load(open(p)) for p in args.entries]
    ids = [e["id"] for e in entries]
    if len(set(ids)) != len(ids):
        raise SystemExit(f"duplicate ids: {ids}")
    write_json(args.out, {"schema": 1, "serial": args.serial, "bridges": entries})
    print(f"==> {args.out}: serial {args.serial}, {', '.join(ids)}")


def signatures_feed(args):
    manifest = load(args.manifest)
    feed = args.feed if args.feed.endswith("/") else args.feed + "/"
    out_dbs = os.path.join(args.out, "signatures")
    os.makedirs(out_dbs, exist_ok=True)
    dropped = {int(b) for b in args.drop_build or []}
    builds = [b for b in manifest["builds"] if int(b["build"]) not in dropped]
    used = {b["database"] for b in builds}
    databases = []
    for d in manifest["databases"]:
        if d["file"] not in used:
            continue
        copy_checked(os.path.join(args.dir, d["file"]), os.path.join(out_dbs, d["file"]), d["sha256"])
        databases.append({**d, "url": f"{feed}signatures/{d['file']}"})
    out = os.path.join(args.out, "manifest", "signatures-manifest.json")
    write_json(out, {"schema": 1, "serial": args.serial, "databases": databases, "builds": builds})
    print(f"==> {out}: serial {args.serial}, {len(databases)} databases, builds "
          + " ".join(str(b["build"]) for b in builds))


def next_serial(*documents):
    return max([d.get("serial", 0) for d in documents if d] + [0]) + 1


def optional(path):
    return load(path) if path and os.path.isfile(path) else None


def publish_bridges(args):
    """The published bridge manifest plus new entries; downloadable bridges only."""
    repo, current = load(args.repo), optional(args.current)
    entries = [e for e in (current or {"bridges": []})["bridges"]]
    for path in args.entries:
        entry = json.load(open(path))
        if not entry.get("url"):
            raise SystemExit(f"{path}: {entry['id']} has no url; only published bridges go in the feed")
        entries = [e for e in entries if e["id"] != entry["id"]] + [entry]
    serial = next_serial(repo, current)
    write_json(args.out, {"schema": 1, "serial": serial, "bridges": entries})
    print(f"==> {args.out}: serial {serial}, {', '.join(e['id'] for e in entries)}")


def publish_signatures(args):
    """The published signatures manifest: what was published, what the repository bundles,
    and new databases and builds. Every database a build names goes in <out>/signatures."""
    repo, current = load(args.repo), optional(args.current)
    feed = args.feed if args.feed.endswith("/") else args.feed + "/"
    sources = {}                                   # file -> local path with the bytes
    databases = {}
    for d in (current or {"databases": []})["databases"]:
        databases[d["file"]] = d
    for d in repo["databases"]:
        databases[d["file"]] = {**d, "url": f"{feed}{args.tag}/{d['file']}"}
        sources[d["file"]] = os.path.join(args.dir, d["file"])
    for path in args.add_db or []:
        name = os.path.basename(path)
        db = json.load(open(path))
        if db.get("schema_version") != 3 or db.get("arch") != "arm64" or f"{db.get('steam_build')}.json" != name:
            raise SystemExit(f"{path}: not a schema 3 arm64 database named after its steam_build")
        databases[name] = {"file": name, "sha256": sha256(path), "url": f"{feed}{args.tag}/{name}"}
        sources[name] = path
    builds = {}
    for b in (current or {"builds": []})["builds"] + repo["builds"]:
        builds[int(b["build"])] = b
    for spec in args.add_build or []:
        build, rest = spec.split("=", 1)
        database, checked = rest.split(":", 1)
        builds[int(build)] = {"build": int(build), "database": database, "checked": checked}
    for b in builds.values():
        if b["database"] not in databases:
            raise SystemExit(f"build {b['build']} names {b['database']}, which is in no manifest")
    out_dbs = os.path.join(args.out, "signatures")
    os.makedirs(out_dbs, exist_ok=True)
    used = sorted({b["database"] for b in builds.values()})
    for name in used:
        if name in sources:
            copy_checked(sources[name], os.path.join(out_dbs, name), databases[name]["sha256"])
    serial = next_serial(repo, current)
    out = os.path.join(args.out, "manifest", "signatures-manifest.json")
    write_json(out, {"schema": 1, "serial": serial,
                     "databases": [databases[n] for n in used],
                     "builds": [builds[k] for k in sorted(builds)]})
    print(f"==> {out}: serial {serial}, {len(used)} databases, builds "
          + " ".join(str(k) for k in sorted(builds)))


def valve_manifest(args):
    """Valve's client manifest (KeyValues text) as JSON: version and packages."""
    import re
    tokens = re.findall(r'"((?:[^"\\]|\\.)*)"|([{}])', open(args.file, encoding="utf-8").read())
    stack, key, root = [{}], None, None
    for text, brace in tokens:
        if brace == "{":
            child = {}
            stack[-1][key] = child
            stack.append(child)
            key = None
        elif brace == "}":
            stack.pop()
        elif key is None:
            key = text
        else:
            stack[-1][key] = text
            key = None
    root = next(iter(stack[0].values()), None)
    if not isinstance(root, dict) or not root.get("version", "").isdigit():
        raise SystemExit(f"{args.file}: not a Steam client manifest")
    packages = {k: v for k, v in root.items() if isinstance(v, dict) and "file" in v and "sha2" in v}
    json.dump({"version": int(root["version"]), "packages": packages}, sys.stdout, indent=2)
    print()


def engine_versions(args):
    """Dormison's engine.json (already verified): one "<channel> <version>" per channel."""
    data = json.load(open(args.file))
    for channel, info in sorted(data.get("channels", {}).items()):
        if isinstance(info, dict) and info.get("version"):
            print(channel, info["version"])


CONFIG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "feed.json")


def feed_config(path=CONFIG):
    """release/feed.json: where Lullaby publishes and how the app downloads (DECISIONS P6-11).
    Everything else (the feed base, the appcast URL) is derived from it."""
    c = json.load(open(path))
    if c.get("schema") != 1:
        raise SystemExit(f"{path}: schema {c.get('schema')}, expected 1")
    repo = c.get("repository", "")
    if repo.count("/") != 1 or not all(repo.split("/")):
        raise SystemExit(f"{path}: repository must be owner/name, not {repo!r}")
    if c.get("access") not in ("public", "private"):
        raise SystemExit(f"{path}: access must be public or private")
    for key in ("manifestTag", "signaturesTag", "appcast"):
        if not c.get(key) or "/" in c[key]:
            raise SystemExit(f"{path}: {key} must be a plain name")
    engine = c.get("engineManifest", "")
    if not engine.startswith("https://github.com/") or "/releases/download/" not in engine:
        raise SystemExit(f"{path}: engineManifest must be a GitHub release download over https")
    c["feed"] = f"https://github.com/{repo}/releases/download/"
    c["appcastURL"] = f"{c['feed']}{c['manifestTag']}/{c['appcast']}"
    return c


def config(args):
    value = feed_config(args.file or CONFIG)[args.key]
    print(value)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("stage-bridge")
    s.add_argument("manifest"); s.add_argument("b1"); s.add_argument("payload")
    s.add_argument("--from-feed")
    s.set_defaults(run=stage_bridge)
    s = sub.add_parser("stage-signatures")
    s.add_argument("manifest"); s.add_argument("dir"); s.add_argument("payload")
    s.set_defaults(run=stage_signatures)
    s = sub.add_parser("bridge-artifact")
    for name in ("--feed", "--out"):
        s.add_argument(name, required=True)
    for name in ("--manifest", "--like", "--root", "--files-dir", "--b1-dir", "--fixes-dir", "--engine-json"):
        s.add_argument(name)
    s.add_argument("--rev", type=int, required=True)
    s.add_argument("--engine"); s.add_argument("--commit")
    s.set_defaults(run=bridge_artifact)
    s = sub.add_parser("publish-bridges")
    s.add_argument("--repo", required=True); s.add_argument("--current"); s.add_argument("--out", required=True)
    s.add_argument("entries", nargs="+")
    s.set_defaults(run=publish_bridges)
    s = sub.add_parser("publish-signatures")
    for name in ("--repo", "--dir", "--feed", "--out"):
        s.add_argument(name, required=True)
    s.add_argument("--tag", default="signatures")
    s.add_argument("--current"); s.add_argument("--add-db", action="append")
    s.add_argument("--add-build", action="append")
    s.set_defaults(run=publish_signatures)
    s = sub.add_parser("config")
    s.add_argument("key"); s.add_argument("--file")
    s.set_defaults(run=config)
    s = sub.add_parser("valve-manifest")
    s.add_argument("file")
    s.set_defaults(run=valve_manifest)
    s = sub.add_parser("engine-versions")
    s.add_argument("file")
    s.set_defaults(run=engine_versions)
    s = sub.add_parser("bridge-manifest")
    s.add_argument("--serial", type=int, required=True); s.add_argument("--out", required=True)
    s.add_argument("entries", nargs="+")
    s.set_defaults(run=bridge_manifest)
    s = sub.add_parser("signatures")
    for name in ("--manifest", "--dir", "--feed", "--out"):
        s.add_argument(name, required=True)
    s.add_argument("--serial", type=int, required=True)
    s.add_argument("--drop-build", action="append")
    s.set_defaults(run=signatures_feed)
    args = p.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
