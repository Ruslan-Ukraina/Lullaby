#!/usr/bin/env python3
"""Stage the engine support table and its B1 ntdll.dll files into the app payload.

    stage-support.py <support.json> <b1 build dir> <payload>/engine-support

Every file the table names is copied from the B1 build directory (what
ntdll-patch/b1/build-b1.sh writes, scratch/ntdll-b1/<version>/) and must have
the sha256 the table gives. When the build directory no longer has a file, an
already staged copy with the right digest is kept, as make app-payload does for
the bridge.
"""
import hashlib
import json
import os
import shutil
import sys


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def main():
    table_path, build, dest = sys.argv[1:4]
    table = json.load(open(table_path))
    if table.get("schema") != 1:
        raise SystemExit(f"{table_path}: schema {table.get('schema')}, expected 1")
    os.makedirs(dest, exist_ok=True)
    for engine in table["engines"]:
        if engine["commit"] not in table["bridge"]["engineCommits"]:
            print(f"==> note: {engine['version']} is listed but the bridge is not built for it")
        for item in engine["ntdll"]:
            rel = item["file"]
            if rel.startswith("/") or ".." in rel.split("/"):
                raise SystemExit(f"{rel}: unsafe path")
            src, dst = os.path.join(build, rel), os.path.join(dest, rel)
            if os.path.isfile(src):
                got = sha256(src)
                if got != item["b1"]:
                    raise SystemExit(f"{src}: sha256 {got}, support.json says {item['b1']}")
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                shutil.copyfile(src, dst + ".new")
                os.replace(dst + ".new", dst)
            elif os.path.isfile(dst) and sha256(dst) == item["b1"]:
                print(f"==> keeping staged {rel}")
            else:
                raise SystemExit(f"{src} is missing and nothing is staged, run ntdll-patch/b1/build-b1.sh")
    shutil.copyfile(table_path, os.path.join(dest, "support.json"))
    print(f"==> staged engine support for {', '.join(e['version'] for e in table['engines'])}")


if __name__ == "__main__":
    main()
