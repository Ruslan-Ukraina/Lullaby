#!/usr/bin/env python3
"""NotProton's release feed: what the app carries and what the fork publishes (Phase 5).

Staging into the app payload (make app-payload):

    feed.py stage-bridge <bridge/bridge-manifest.json> <B1 build dir> <payload>
    feed.py stage-signatures <signatures/manifest.json> <signatures/macos.arm64> <payload>

Publishing (CI in Phase 6, or a local test feed; signing is release/sign.swift):

    feed.py bridge-artifact --manifest bridge/bridge-manifest.json --like bridge-dormison-b1-1 \
        --root <payload> --rev 2 --feed <base url> --out <feed dir>
    feed.py bridge-manifest --serial N --out <feed dir>/manifest/bridge-manifest.json <entry.json>...
    feed.py signatures --manifest signatures/manifest.json --dir signatures/macos.arm64 \
        --feed <base url> --serial N --out <feed dir> [--drop-build B]...

The feed directory mirrors GitHub's release downloads: <base>/<tag>/<file>.
Manifests: <tag> = manifest; a bridge build: <tag> = its id; databases: <tag> = signatures.
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


def stage_bridge(args):
    manifest = load(args.manifest)
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


def bridge_artifact(args):
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


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("stage-bridge")
    s.add_argument("manifest"); s.add_argument("b1"); s.add_argument("payload")
    s.set_defaults(run=stage_bridge)
    s = sub.add_parser("stage-signatures")
    s.add_argument("manifest"); s.add_argument("dir"); s.add_argument("payload")
    s.set_defaults(run=stage_signatures)
    s = sub.add_parser("bridge-artifact")
    for name in ("--manifest", "--like", "--root", "--feed", "--out"):
        s.add_argument(name, required=True)
    s.add_argument("--rev", type=int, required=True)
    s.add_argument("--engine"); s.add_argument("--commit")
    s.set_defaults(run=bridge_artifact)
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
