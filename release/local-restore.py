#!/usr/bin/env python3 -I
"""Puts this Mac's Lullaby back to a published bridge on a verified engine, by hand, when the release feed no
longer lists that bridge (its manifest entry is gone, so the app cannot install it). Used for the roll back to the
pre.25 state: engine dormison-r6, bridge-dormison-r6-5, GPTK 4.0 beta 3.

  release/local-restore.py <engine> <bridge tarball> <verified engine dir> [--pin <pin json>] [--gptk <the toolkit folder, e.g. ".../4.0 beta 3">] [--yes]

What it trusts: the bridge tarball must carry the owner's release signature (the .sig beside it), the engine must be
a directory release/engine/fetch-dormison.sh unpacked and checked, and every engine file the bridge replaces must be
the release's own (engine-manifest.json). Dry run unless --yes. Everything it replaces is copied into
lullaby/backups/restore-<time>/ first, with a rollback.sh. Refuses while a Wine server runs.
"""
import hashlib, json, os, shutil, subprocess, sys, tarfile, time

repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUP = os.path.expanduser("~/Library/Application Support/lullaby")
PUB = "NMdeqw9gY3V97eTrGe1HN+V/nzGTsg/8fstoMfOR4MA="
args = [a for a in sys.argv[1:] if not a.startswith("--")]
yes = "--yes" in sys.argv
gptk_src = sys.argv[sys.argv.index("--gptk") + 1] if "--gptk" in sys.argv else None
pin = sys.argv[sys.argv.index("--pin") + 1] if "--pin" in sys.argv else None
for opt in (gptk_src, pin):
    if opt in args:
        args.remove(opt)
engine, tar_path, src_engine = args[0], os.path.abspath(args[1]), os.path.abspath(args[2])
bid = os.path.basename(tar_path).removesuffix(".tar.xz")


def die(msg):
    sys.exit(f"==> local-restore: {msg}")


def say(msg):
    print(f"==> {msg}")


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


if subprocess.run(["pgrep", "-x", "wineserver"], capture_output=True).returncode == 0:
    die("a Wine server runs; close the game first")
verify = os.path.join(repo, "scratch/bin/verify-ed25519")
if subprocess.run([verify, PUB, tar_path, tar_path + ".sig"], capture_output=True).returncode != 0:
    die(f"{tar_path} does not carry the release key's signature")
info = json.load(open(os.path.join(src_engine, "engine-info.json")))
if info["version"] != engine:
    die(f"{src_engine} is {info['version']}, not {engine}")
manifest = {c["path"]: c["sha256"] for c in json.load(open(os.path.join(src_engine, "engine-manifest.json")))["components"] if "sha256" in c}

unpacked = os.path.join(SUP, ".restore-unpacked")
shutil.rmtree(unpacked, ignore_errors=True)
os.makedirs(unpacked)
with tarfile.open(tar_path) as t:
    t.extractall(unpacked, filter="data")
pkg = os.path.join(unpacked, bid)

ENGINE_FILES = {"engine/ntdll.so": "wine/lib/wine/x86_64-unix/ntdll.so",
                "engine/win32u.so": "wine/lib/wine/x86_64-unix/win32u.so",
                "engine/winemac.so": "wine/lib/wine/x86_64-unix/winemac.so"}
NTDLL = {"ntdll/x86_64-ntdll.dll": ("x86_64", "wine/lib/wine/x86_64-windows/ntdll.dll"),
         "ntdll/i386-ntdll.dll": ("i386", "wine/lib/wine/i386-windows/ntdll.dll")}
LIVE = {"x86_64-windows-lsteamclient.dll": "lsteamclient.dll", "x86_64-unix-lsteamclient.so": "lsteamclient.so",
        "i386-windows-lsteamclient.dll": "i386-windows/lsteamclient.dll", "steam.exe": "steam.exe"}

dest = os.path.join(SUP, "runners", engine)
cur = os.path.basename(os.path.realpath(os.path.join(SUP, "runners", "current")))
state_path = os.path.join(SUP, "bridges/state.json")
old_state = json.load(open(state_path))
say(f"plan: {engine} cloned from {src_engine} into {dest} (if missing), {len(ENGINE_FILES)} engine files and "
    f"{len(NTDLL)} ntdll files from {bid}, {len(LIVE)} live bridge files, store {bid}, current: {cur} -> {engine}"
    + (f", GPTK from {gptk_src}" if gptk_src else ""))
if not yes:
    say("dry run: nothing changed; add --yes")
    sys.exit(0)

bk = os.path.join(SUP, "backups", f"restore-{time.strftime('%Y%m%d-%H%M%S')}")
os.makedirs(os.path.join(bk, "bridge-live/i386-windows"))
for rel in LIVE.values():
    shutil.copy2(os.path.join(SUP, "bridge", rel), os.path.join(bk, "bridge-live", rel))
shutil.copy2(state_path, os.path.join(bk, "state.json"))
gptk_now = os.path.join(SUP, "d3dmetal")
gptk_status = os.path.join(gptk_now, ".install-status.json")
if gptk_src:
    shutil.copy2(gptk_status, os.path.join(bk, "install-status.json"))
with open(os.path.join(bk, "rollback.sh"), "w") as f:
    f.write(f"""#!/bin/sh
# Puts Lullaby back as it was before {bid} was restored. Close games first.
set -eu
SUP="$HOME/Library/Application Support/lullaby"
B="$(cd "$(dirname "$0")" && pwd)"
cp -f "$B/state.json" "$SUP/bridges/state.json"
for f in lsteamclient.dll lsteamclient.so steam.exe i386-windows/lsteamclient.dll; do cp -f "$B/bridge-live/$f" "$SUP/bridge/$f"; done
ln -sfn {cur} "$SUP/runners/current.new" && mv -fh "$SUP/runners/current.new" "$SUP/runners/current"
if [ -d "$B/gptk" ]; then
  for d in "$SUP"/d3dmetal/*/; do rm -rf "${{d%/}}"; done
  mv "$B"/gptk/* "$SUP/d3dmetal/" && cp -f "$B/install-status.json" "$SUP/d3dmetal/.install-status.json"
fi
echo "rolled back: current -> {cur}"
""")
os.chmod(os.path.join(bk, "rollback.sh"), 0o755)
say(f"backup and rollback script: {bk}")

if not os.path.isdir(dest):
    part = dest + ".partial"
    shutil.rmtree(part, ignore_errors=True)
    subprocess.run(["cp", "-cR", src_engine, part], check=True)
    os.rename(part, dest)


def replace(path, new_file):
    tmp = path + ".lullaby-new"
    shutil.copy2(new_file, tmp)
    os.replace(tmp, path)


engine_files, ntdll = [], []
for rel_pkg, rel in ENGINE_FILES.items():
    target = os.path.join(dest, rel)
    patched = sha(os.path.join(pkg, rel_pkg))
    if sha(target) not in (manifest[rel], patched):
        die(f"{rel} is neither the release's nor the bridge's file")
    if sha(target) != patched:
        if not os.path.exists(target + ".lullaby-orig"):
            shutil.copy2(target, target + ".lullaby-orig")
        replace(target, os.path.join(pkg, rel_pkg))
    engine_files.append({"clean": manifest[rel], "file": rel_pkg, "patched": patched, "path": rel})
for rel_pkg, (arch, rel) in NTDLL.items():
    target = os.path.join(dest, rel)
    b1 = sha(os.path.join(pkg, rel_pkg))
    if sha(target) not in (manifest[rel], b1):
        die(f"{rel} is neither the release's nor the bridge's file")
    if sha(target) != b1:
        if not os.path.exists(target + ".lullaby-orig"):
            shutil.copy2(target, target + ".lullaby-orig")
        replace(target, os.path.join(pkg, rel_pkg))
    ntdll.append({"arch": arch, "b1": b1, "clean": manifest[rel], "file": rel_pkg, "path": rel})
say("engine files and the ntdll pair applied")

store = os.path.join(SUP, "bridges", bid)
if not os.path.isdir(store):
    shutil.copytree(pkg, store)
rev = int(bid.rsplit("-", 1)[1])
record = {"id": bid, "engine": engine, "engineCommit": info["commit"], "rev": rev, "engineFiles": engine_files, "ntdll": ntdll,
          "files": [{"name": n, "path": n, "sha256": sha(os.path.join(pkg, n))} for n in LIVE],
          "sha256": sha(tar_path), "sizeBytes": os.path.getsize(tar_path),
          "url": f"https://github.com/Ruslan-Ukraina/Lullaby/releases/download/{bid}/{bid}.tar.xz"}
if pin:  # the pin file fetch-dormison.sh was given: where the engine comes from, for a reinstall by the app
    release = json.load(open(pin))["channels"]["pin"]
    record["engineRelease"] = {"sha256": release["sha256"], "sizeBytes": release["sizeBytes"], "url": release["url"]}
json.dump(record, open(os.path.join(store, "bridge.json"), "w"), indent=2, sort_keys=True)

for name, rel in LIVE.items():
    replace(os.path.join(SUP, "bridge", rel), os.path.join(pkg, name))
say("live bridge files replaced")

unix = os.path.join(dest, "wine/lib/wine")
open(os.path.join(dest, "lullaby-engine.env"), "w").write(f"""# Written by Lullaby for compat_run.sh. Do not edit.
LB_ENGINE_VERSION='{engine}'
LB_ENGINE_COMMIT='{info["commit"]}'
LB_ENGINE_WINELOADER='{dest}/wine/bin/wine'
LB_ENGINE_WINESERVER='{dest}/wine/bin/wineserver'
LB_ENGINE_UNIX_DIR='{unix}/x86_64-unix'
LB_ENGINE_DLLPATH_X86_64='{unix}/x86_64-windows'
LB_ENGINE_DLLPATH_I386='{unix}/i386-windows'
""")
out = subprocess.run([os.path.join(dest, "wine/bin/wine"), "--version"], capture_output=True, text=True, timeout=60)
if out.returncode != 0 or not out.stdout.strip():
    die(f"the engine does not run: {out.stdout} {out.stderr}")
say(f"smoke test: {out.stdout.strip()}")

if gptk_src:
    os.makedirs(os.path.join(bk, "gptk"))
    for d in os.listdir(gptk_now):
        if os.path.isdir(os.path.join(gptk_now, d)):
            os.rename(os.path.join(gptk_now, d), os.path.join(bk, "gptk", d))
    version = os.path.basename(os.path.abspath(gptk_src))
    subprocess.run(["cp", "-cR", gptk_src, os.path.join(gptk_now, version)], check=True)
    json.dump({"state": "installed", "version": version}, open(gptk_status, "w"), separators=(",", ":"))
    say(f"GPTK: {version} in place")

link = os.path.join(SUP, "runners", "current")
os.symlink(engine, link + ".new")
os.replace(link + ".new", link)
json.dump({"current": bid, "previous": old_state.get("current")}, open(state_path, "w"), indent=2)
shutil.rmtree(unpacked, ignore_errors=True)
say(f"done: current -> {engine}, bridge {bid}. Roll back with: {bk}/rollback.sh")
