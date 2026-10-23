#!/usr/bin/env python3 -I
"""Draft of Lullaby's game fix catalog from MacGameFix's process-features.json (GPL-3.0).

Only data is taken: per executable the title, the symptom (as the reason), the graphics
backend and the GPTK version the fix stops being needed from. MacGameFix's own fixes (proxy
DLLs) are not imported here; `needs_engine` names a CrossOver module and has no meaning for
Dormison, so it is left out. Executables too generic to match on (`game.exe`) are skipped.
The draft has no `verifiedOn`: nothing in it is applied until a game was checked on an engine.

usage: import-macgamefix.py <MacGameFix checkout> <out.json>
"""
import json, re, subprocess, sys
from pathlib import Path

BACKENDS = {"d3dmetal", "dxmt", "dxvk", "wined3d"}


def main():
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    commit = subprocess.run(["git", "-C", str(src), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    table = json.loads((src / "process-features.json").read_text(encoding="utf-8"))
    generic = {k.lower() for k in table.get("keys_too_generic_to_match_on_alone", [])}
    entries, skipped = [], []
    for exe, row in sorted(table["processes"].items()):
        name = exe.lower()
        if name in generic or not re.fullmatch(r"[a-z0-9_. +'()-]+\.exe", name):
            skipped.append(exe)
            continue
        entry = {"id": "mgf-" + re.sub(r"[^a-z0-9]+", "-", name[:-4]).strip("-"),
                 "name": row["title"][:80], "match": {"exes": [name]}, "verdict": "fits"}
        if row.get("backend") in BACKENDS:
            entry["backend"] = row["backend"]
        if row.get("not_needed_from_gptk"):
            entry["notNeededFromGPTK"] = row["not_needed_from_gptk"]
        entry["source"] = {"kind": "macgamefix", "ref": f"process-features.json:{exe}@{commit[:12]}", "license": "GPL-3.0"}
        entry["reason"] = row.get("symptom", "")[:300]
        entries.append(entry)
    out.write_text(json.dumps({"schema": 1, "serial": 1, "entries": entries}, indent=1, ensure_ascii=False) + "\n")
    print(f"{len(entries)} entries from {commit[:12]}; skipped {len(skipped)}: {skipped}")


main()
