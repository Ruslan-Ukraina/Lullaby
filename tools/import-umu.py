#!/usr/bin/env python3 -I
"""Draft of Lullaby's game fix catalog from umu-protonfixes (docs/GAME_FIXES.md §4).

Reads gamefixes-steam/<appid>.py as TEXT with ast.parse and never imports or runs it.
Takes only literal calls at the top level of main():
  util.set_environment(KEY, VALUE), util.winedll_override(DLL, util.OverrideOrder.X),
  util.regedit_add(HKCU\\Software\\Wine\\..., NAME, TYPE, VALUE).
Everything else (protontricks, copies, ini edits, conditions) is counted and skipped.
The same rules as GameFixCatalog.swift apply, so the draft always decodes there.

usage: import-umu.py <umu-protonfixes checkout> <out.json> [report.txt]
"""
import ast, json, re, subprocess, sys
from collections import Counter
from pathlib import Path

FORBIDDEN = {"WINELOADER", "WINESERVER", "WINEPREFIX", "WINEDLLOVERRIDES", "PATH", "HOME", "MTL_HUD_ENABLED"}
FORBIDDEN_PREFIX = ("DYLD_", "LD_", "LULLABY_", "SEVO_", "WINEDLLPATH")
# Proton-only switches mean nothing to Dormison.
PROTON_ONLY = ("PROTON_", "STEAM_COMPAT", "STEAM_RUNTIME", "SteamGame", "UMU_", "PROTONFIXES")
ORDER = {"NATIVE": "n", "BUILTIN": "b", "NATIVE_BUILTIN": "n,b", "BUILTIN_NATIVE": "b,n", "DISABLED": "d"}
WINE_KEY = "HKCU\\Software\\Wine\\"


def literal(node):
    try:
        return ast.literal_eval(node)
    except Exception:
        return None


def order_of(node):
    if isinstance(node, ast.Attribute) and node.attr in ORDER:
        return ORDER[node.attr]
    return None


def convert(path, skipped):
    tree = ast.parse(path.read_text(encoding="utf-8"))
    name = ast.get_docstring(tree) or path.stem
    main = next((n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "main"), None)
    env, dlls, reg = {}, {}, []
    for stmt in main.body if main else []:
        call = stmt.value if isinstance(stmt, ast.Expr) and isinstance(stmt.value, ast.Call) else None
        fn = None
        if call is not None and isinstance(call.func, ast.Attribute) and isinstance(call.func.value, ast.Name) \
                and call.func.value.id == "util":
            fn = call.func.attr
        else:
            skipped["not a plain util call"] += 1
            continue
        args = [literal(a) for a in call.args]
        if call.keywords:
            skipped[f"{fn} with keywords"] += 1
        elif fn == "set_environment" and len(args) == 2 and all(isinstance(a, str) for a in args):
            k, v = args
            if not re.fullmatch(r"[A-Z][A-Z0-9_]*", k) or k in FORBIDDEN or k.startswith(FORBIDDEN_PREFIX):
                skipped["env key not allowed"] += 1
            elif k.startswith(PROTON_ONLY):
                skipped["proton-only env"] += 1
            elif len(v.encode()) > 256 or "\n" in v or "\0" in v:
                skipped["env value not allowed"] += 1
            else:
                env[k] = v
        elif fn == "winedll_override" and len(args) == 2 and isinstance(args[0], str) and order_of(call.args[1]):
            if re.fullmatch(r"[A-Za-z0-9_.-]+", args[0]) and ".." not in args[0]:
                dlls[args[0]] = order_of(call.args[1])
            else:
                skipped["dll name not allowed"] += 1
        elif fn == "regedit_add" and len(args) == 4 and all(isinstance(a, str) for a in args):
            key, n, t, v = args
            ok = key.startswith(WINE_KEY) and ".." not in key and n and "\0" not in n + v \
                and (t == "REG_SZ" or (t == "REG_DWORD" and v.isdigit() and int(v) < 2**32))
            if ok:
                reg.append({"key": key, "name": n, "type": t, "value": v})
            else:
                skipped["registry outside Software\\Wine"] += 1
        else:
            skipped[fn] += 1
    if not (env or dlls or reg):
        return None
    entry = {"id": f"umu-{path.stem}", "name": name.strip().splitlines()[0][:80],
             "match": {"appIDs": [int(path.stem)]}, "verdict": "fits"}
    if env: entry["env"] = dict(sorted(env.items()))
    if dlls: entry["dllOverrides"] = dict(sorted(dlls.items()))
    if reg: entry["registry"] = reg
    return entry


def main():
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    commit = subprocess.run(["git", "-C", str(src), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    skipped, entries = Counter(), []
    for f in sorted((src / "gamefixes-steam").glob("[0-9]*.py"), key=lambda p: int(p.stem)):
        try:
            entry = convert(f, skipped)
        except SyntaxError:
            skipped["unparsable file"] += 1
            continue
        if entry:
            entry["source"] = {"kind": "umu-protonfixes", "ref": f"gamefixes-steam/{f.name}@{commit[:12]}",
                               "license": "BSD-2-Clause"}
            entry["reason"] = "umu-protonfixes, declarative part only; not yet checked on Dormison"
            entries.append(entry)
    out.write_text(json.dumps({"schema": 1, "serial": 1, "entries": entries}, indent=1, ensure_ascii=False) + "\n")
    report = f"{len(entries)} entries from {commit}\nskipped calls:\n" + "".join(
        f"  {n:5d}  {why}\n" for why, n in skipped.most_common())
    if len(sys.argv) > 3:
        Path(sys.argv[3]).write_text(report)
    print(report, end="")


main()
