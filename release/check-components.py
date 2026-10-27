#!/usr/bin/env python3
"""Compares the versions Lullaby is pinned to (release/components.json) with what the sources publish now.

  release/check-components.py                  # asks GitHub, GitLab and LunarG, prints a table; read only
  release/check-components.py --validate       # offline: the list is well formed and every pin is true to the repository
  release/check-components.py --strict         # exit 1 if any component has something newer (for a scheduled run)
  release/check-components.py --only mesa      # parts of the id or the name

Run it now and then (once a month) and before a release. It writes nothing and moves no pin: a newer
version is a reason to read its notes and decide, the way docs/BACKLOG.md says for each part.
GitHub is asked through `gh` when it is installed and logged in (no rate limit), else directly (60 a hour).
"""
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIST = os.path.join(REPO, "release", "components.json")
TYPES = {"github-release", "github-tags", "github-commit", "git-tags", "lunarg-mac", "manual"}
GROUPS = {"ship", "try", "watch"}


def load():
    with open(LIST, encoding="utf-8") as f:
        return json.load(f)["components"]


def version_key(text):
    """Numbers of a version string, a release candidate before the final one: 26.3.0-rc2 < 26.3.0."""
    plain = re.sub(r"-?rc\d+", "", text)
    plain = re.sub(r"\d{8}", "", plain)  # a build date such as -20230507-repack is not a version
    nums = tuple(int(n) for n in re.findall(r"\d+", plain))
    rc = re.search(r"rc(\d+)", text)
    return nums + ((0, int(rc.group(1))) if rc else (1, 0))


def validate(components):
    problems = []
    seen = set()
    for c in components:
        cid = c.get("id", "?")
        for field in ("id", "name", "group", "source", "license", "pinned", "check", "policy"):
            if not c.get(field):
                problems.append(f"{cid}: no {field}")
        if cid in seen:
            problems.append(f"{cid}: id twice")
        seen.add(cid)
        if c.get("group") not in GROUPS:
            problems.append(f"{cid}: group {c.get('group')} is not one of {sorted(GROUPS)}")
        if not str(c.get("source", "")).startswith("https://"):
            problems.append(f"{cid}: source is not an https address")
        chk = c.get("check", {})
        if chk.get("type") not in TYPES:
            problems.append(f"{cid}: check type {chk.get('type')} unknown")
        if chk.get("type") in ("github-release", "github-tags", "github-commit") and not chk.get("repo"):
            problems.append(f"{cid}: check has no repo")
        if chk.get("type") == "git-tags" and not chk.get("url", "").startswith("https://"):
            problems.append(f"{cid}: git-tags has no https url")
        v = c.get("verify")
        if v:
            path = os.path.join(REPO, v["file"])
            if not os.path.isfile(path):
                problems.append(f"{cid}: verify file {v['file']} is missing")
            else:
                with open(path, encoding="utf-8", errors="replace") as f:
                    if v["contains"] not in f.read():
                        problems.append(f"{cid}: pinned {c['pinned']} but {v['file']} does not contain \"{v['contains']}\"")
    return problems


def http_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": "lullaby-check-components", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def github(path):
    if shutil.which("gh"):
        done = subprocess.run(["gh", "api", path], capture_output=True, text=True, timeout=60)
        if done.returncode == 0:
            return json.loads(done.stdout)
        if "404" in done.stdout + done.stderr:
            return None
    try:
        return http_json("https://api.github.com/" + path)
    except Exception:
        return None


def latest(c):
    """(latest version text, note) or (None, why)."""
    chk = c["check"]
    kind = chk["type"]
    if kind == "manual":
        return None, "manual: " + chk["note"]
    if kind == "github-release":
        data = github(f"repos/{chk['repo']}/releases/latest")
        if not data or "tag_name" not in data:
            return None, "no release found"
        return data["tag_name"], (data.get("published_at") or "")[:10]
    if kind == "github-tags":
        data = github(f"repos/{chk['repo']}/tags?per_page=100")
        names = [t["name"] for t in (data or []) if re.search(chk.get("regex", ""), t["name"])]
        if not names:
            return None, "no tag found"
        return max(names, key=version_key), ""
    if kind == "github-commit":
        data = github(f"repos/{chk['repo']}/commits?per_page=1")
        if not data:
            return None, "no commit found"
        return data[0]["sha"][:12], data[0]["commit"]["committer"]["date"][:10]
    if kind == "git-tags":
        done = subprocess.run(["git", "ls-remote", "--tags", chk["url"]], capture_output=True, text=True, timeout=120)
        names = [line.split("refs/tags/")[1] for line in done.stdout.splitlines() if "refs/tags/" in line and not line.endswith("^{}")]
        names = [n for n in names if re.search(chk.get("regex", ""), n)]
        if not names:
            return None, "no tag found"
        stable = [n for n in names if "-rc" not in n]
        best = max(names, key=version_key)
        return best, ("latest stable " + max(stable, key=version_key)) if stable and best != max(stable, key=version_key) else ""
    if kind == "lunarg-mac":
        try:
            return http_json("https://vulkan.lunarg.com/sdk/latest/mac.json")["mac"], ""
        except Exception:
            return None, "LunarG not reachable"
    return None, "unknown check"


def main(argv):
    components = load()
    problems = validate(components)
    if "--validate" in argv:
        for p in problems:
            print("components:", p, file=sys.stderr)
        if problems:
            return 1
        print(f"==> componentcheck: {len(components)} components, every pin true to the repository, no problem")
        return 0
    only = argv[argv.index("--only") + 1].lower() if "--only" in argv else None
    newer = 0
    print(f"{'id':<18} {'group':<6} {'pinned':<22} {'latest':<28} verdict")
    for c in components:
        if only and only not in c["id"].lower() and only not in c["name"].lower():
            continue
        try:
            version, note = latest(c)
        except Exception as error:  # a source that is down must not hide the others
            version, note = None, f"error: {error}"
        if version is None:
            verdict = note
            shown = "-"
        else:
            shown = version
            if c["check"]["type"] == "github-commit":
                verdict = "same" if c["pinned"][:7] in version or version[:7] in c["pinned"] else f"moved on ({note}); " + ("pinned on purpose" if c["id"] == "dobby" else "read it")
            elif version_key(version) > version_key(c["pinned"]):
                verdict = f"NEWER ({note})".replace(" ()", "")
                newer += 1
            elif version_key(version) == version_key(c["pinned"]):
                verdict = "up to date"
            else:
                verdict = "pinned is ahead" + (f" ({note})" if note else "")
        print(f"{c['id']:<18} {c['group']:<6} {c['pinned']:<22} {shown:<28} {verdict}")
    if problems:
        print("\nthe list itself has problems (run with --validate):", file=sys.stderr)
        for p in problems:
            print("  ", p, file=sys.stderr)
    print(f"\n{newer} component(s) with something newer; nothing was changed.")
    return 1 if ("--strict" in argv and newer) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
