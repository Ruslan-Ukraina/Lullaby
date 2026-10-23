#!/usr/bin/env python3 -I
"""Installs, by hand and without Lullaby's installer, a bridge that release/local-bridge.sh built (and signed) into
this Mac's Lullaby: the verified engine, the bridge's engine files and ntdll pair (originals kept as .lullaby-orig),
the bridge store entry, the live bridge files, lullaby-engine.env, and last the `current`/`previous` links. Everything
it replaces is first copied into lullaby/backups/engine-switch-<time>/ with a rollback.sh. Dry run unless --yes.

  release/local-install.py <engine, e.g. dormison-r7> <rev> [--yes]

Refuses while a Wine server runs (a game or a session). Steam may stay open: the next launch reads `current`.
"""
import hashlib, json, os, shutil, subprocess, sys, time

repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SUP = os.path.expanduser("~/Library/Application Support/lullaby")
WORK = os.environ.get("WORK", os.path.join(repo, "scratch/local-bridge"))
engine, rev = sys.argv[1], sys.argv[2]
yes = "--yes" in sys.argv
bid = f"bridge-{engine}-{rev}"
W = os.path.join(WORK, engine)
feed = os.path.join(W, "feed")


def die(msg):
    sys.exit(f"==> local-install: {msg}")


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def say(msg):
    print(f"==> {msg}")


def run(*cmd):
    subprocess.run(cmd, check=True)


def atomic_copy(src, dst):
    tmp = dst + ".lb-new"
    shutil.copy2(src, tmp)
    os.replace(tmp, dst)


if subprocess.run(["pgrep", "-x", "wineserver"], capture_output=True).stdout.strip():
    die("a Wine server is running: close the game or session first")

manifest = json.load(open(os.path.join(feed, "manifest/bridge-manifest.json")))
entry = next((b for b in manifest["bridges"] if b["id"] == bid), None) or die(f"{bid} is not in the local feed")
tar = os.path.join(feed, bid, f"{bid}.tar.xz")
if sha(tar) != entry["sha256"]:
    die("the bridge package does not match its manifest entry")
pub = open(os.path.join(W, "public-key.txt")).read().strip()
verify = os.path.join(repo, "scratch/bin/verify-ed25519")
for f in (tar, os.path.join(feed, "manifest/bridge-manifest.json")):
    if subprocess.run([verify, pub, f, f + ".sig"], capture_output=True).returncode != 0:
        die(f"{f} does not carry the release key's signature")
say(f"{bid}: package and manifest verified against {pub}")

src_engine = os.path.join(WORK, "runners", engine)
if not os.path.isfile(os.path.join(src_engine, "engine-info.json")):
    die(f"no verified engine at {src_engine}")
info = json.load(open(os.path.join(src_engine, "engine-info.json")))
if info["version"] != engine or info["commit"] != entry["engineCommit"]:
    die("the engine and the bridge are not for each other")

unpacked = os.path.join(W, "installed-unpacked")
shutil.rmtree(unpacked, ignore_errors=True)
os.makedirs(unpacked)
run("tar", "-xJf", tar, "-C", unpacked)
pkg = os.path.join(unpacked, bid)

dest_engine = os.path.join(SUP, "runners", engine)
cur_link = os.path.join(SUP, "runners", "current")
cur_target = os.path.basename(os.path.realpath(cur_link))
live = os.path.join(SUP, "bridge")
live_map = {  # package file -> live bridge file
    "x86_64-windows-lsteamclient.dll": "lsteamclient.dll",
    "x86_64-unix-lsteamclient.so": "lsteamclient.so",
    "i386-windows-lsteamclient.dll": "i386-windows/lsteamclient.dll",
    "steam.exe": "steam.exe",
}
say(f"plan: engine {engine} -> {dest_engine} (a clone of the verified one), the bridge's "
    f"{len(entry['engineFiles'])} engine files and {len(entry['ntdll'])} ntdll files into it, "
    f"{len(live_map)} live bridge files, store {bid}, then current: {cur_target} -> {engine}")
if not yes:
    say("dry run: nothing changed; add --yes")
    sys.exit(0)

reuse = sys.argv[sys.argv.index("--backup") + 1] if "--backup" in sys.argv else None
stamp = time.strftime("%Y%m%d-%H%M%S")
bk = reuse or os.path.join(SUP, "backups", f"engine-switch-{stamp}")
if not reuse:
    os.makedirs(os.path.join(bk, "bridge-live/i386-windows"))
    for _, rel in live_map.items():
        shutil.copy2(os.path.join(live, rel), os.path.join(bk, "bridge-live", rel))
    shutil.copy2(os.path.join(SUP, "bridges/state.json"), os.path.join(bk, "state.json"))
prev_target = os.path.basename(os.path.realpath(os.path.join(SUP, "runners", "previous"))) \
    if os.path.islink(os.path.join(SUP, "runners", "previous")) else ""
with open(os.path.join(bk, "rollback.sh") if not reuse else os.devnull, "w") as f:
    f.write(f"""#!/bin/sh
# Puts Lullaby back as it was before {engine} was switched in ({stamp}). Close games first.
set -eu
SUP="$HOME/Library/Application Support/lullaby"
B="$(cd "$(dirname "$0")" && pwd)"
cp -f "$B/state.json" "$SUP/bridges/state.json"
for f in lsteamclient.dll lsteamclient.so steam.exe i386-windows/lsteamclient.dll; do cp -f "$B/bridge-live/$f" "$SUP/bridge/$f"; done
ln -sfn {cur_target} "$SUP/runners/current.new" && mv -fh "$SUP/runners/current.new" "$SUP/runners/current"
{f'ln -sfn {prev_target} "$SUP/runners/previous.new" && mv -fh "$SUP/runners/previous.new" "$SUP/runners/previous"' if prev_target else 'true'}
echo "rolled back: current -> {cur_target}"
""")
os.chmod(os.path.join(bk, "rollback.sh"), 0o755)  # (a reused backup keeps its own script)
say(f"backup and rollback script: {bk}")

# 1. the engine, cloned (APFS copy-on-write) from the verified one
if not os.path.isdir(dest_engine):
    part = dest_engine + ".partial"
    shutil.rmtree(part, ignore_errors=True)
    run("cp", "-cR", src_engine, part)
    os.rename(part, dest_engine)
say("engine in place")

# 2. the bridge's files into the engine, the release's own kept as .lullaby-orig
def put(rel_pkg, rel_engine, clean, patched):
    target = os.path.join(dest_engine, rel_engine)
    orig = target + ".lullaby-orig"
    have = sha(target)
    if have == patched:
        return
    if have != clean:
        die(f"{rel_engine} is neither the release's nor the bridge's file")
    if not os.path.exists(orig):
        shutil.copy2(target, orig)
    atomic_copy(os.path.join(pkg, rel_pkg), target)
    if sha(target) != patched:
        die(f"{rel_engine} does not match after copying")

for f in entry["engineFiles"]:
    put(f["file"], f["path"], f["clean"], f["patched"])
for f in entry["ntdll"]:
    put(f["file"], f["path"], f["clean"], f["b1"])
say("engine files and the ntdll pair applied")

# 3. the bridge store
store = os.path.join(SUP, "bridges", bid)
if not os.path.isdir(store):
    shutil.copytree(pkg, store)
tarball = next((os.path.join(dp, n) for dp, _, ns in os.walk(os.path.join(WORK, "cache")) for n in ns if n == f"{engine}.tar.xz"), None)
record = dict(entry)
record.pop("patch", None)
record.pop("patchSha256", None)
if tarball:
    record["engineRelease"] = {"sha256": sha(tarball), "sizeBytes": os.path.getsize(tarball),
        "url": f"https://github.com/kageroumado/dormison/releases/download/{engine.split('-', 1)[1]}/{engine}.tar.xz"}
json.dump(record, open(os.path.join(store, "bridge.json"), "w"), indent=2, sort_keys=True)

# 4. the live bridge files
for name, rel in live_map.items():
    atomic_copy(os.path.join(pkg, name), os.path.join(live, rel))
say("live bridge files replaced")

# 5. the engine's description for the run script
env_path = os.path.join(SUP, "runners", cur_target, "lullaby-engine.env")
if os.path.exists(env_path):
    old_env = open(env_path).read()
    env = old_env.replace(cur_target, engine).replace(
        next((l.split("'")[1] for l in old_env.splitlines() if l.startswith("LB_ENGINE_COMMIT=")), ""), info["commit"])
else:
    # The engine being replaced is the one just cloned (r5 over r5): the file's layout is written out.
    unix = os.path.join(dest_engine, "wine/lib/wine")
    env = f"""# Written by Lullaby for compat_run.sh. Do not edit.
LB_ENGINE_VERSION='{engine}'
LB_ENGINE_COMMIT='{info["commit"]}'
LB_ENGINE_WINELOADER='{dest_engine}/wine/bin/wine'
LB_ENGINE_WINESERVER='{dest_engine}/wine/bin/wineserver'
LB_ENGINE_UNIX_DIR='{unix}/x86_64-unix'
LB_ENGINE_DLLPATH_X86_64='{unix}/x86_64-windows'
LB_ENGINE_DLLPATH_I386='{unix}/i386-windows'
"""
open(os.path.join(dest_engine, "lullaby-engine.env"), "w").write(env)

# 6. a smoke test before anything is switched
wine = os.path.join(dest_engine, "wine/bin/wine")
out = subprocess.run([wine, "--version"], capture_output=True, text=True, timeout=60)
if out.returncode != 0 or not out.stdout.strip():
    die(f"the new engine does not run: {out.stdout} {out.stderr}")
say(f"smoke test: {out.stdout.strip()}")

# 7. the switch, last: links by rename, then the bridge state
for name, target in (("previous", cur_target), ("current", engine)):
    link = os.path.join(SUP, "runners", name)
    tmp = link + ".new"
    if os.path.lexists(tmp):
        os.remove(tmp)
    os.symlink(target, tmp)
    os.replace(tmp, link)
state_path = os.path.join(SUP, "bridges/state.json")
state = json.load(open(state_path))
state["previous"], state["current"] = state.get("current"), bid
json.dump(state, open(state_path, "w"), indent=2)
say(f"switched: current -> {engine}, bridge {bid}. Roll back with: {bk}/rollback.sh")
