#!/usr/bin/env python3
# Turns a JavaScript file into a C string macro, so a webpatch gate can splice it into
# its replacement text at compile time.
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 4:
        sys.stderr.write("usage: embed_js.py <input.js> <output.h> <MACRO>\n")
        return 2
    src, dst, macro = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
    text = src.read_text(encoding="ascii")
    pieces = []
    for line in text.rstrip("\n").split("\n"):
        stripped = line.strip()
        if stripped.startswith("//"):
            continue  # comments stay in the source, not in Steam's page
        body = line.replace("\\", "\\\\").replace('"', '\\"')
        pieces.append(f'    "{body}\\n"')
    guard = f"NOTPROTON_GENERATED_{macro.upper()}_H"
    header = (
        f"// Generated from {src.as_posix()} by dylib/embed_js.py. Edit that file.\n"
        f"#ifndef {guard}\n"
        f"#define {guard}\n"
        f"\n"
        f"#define {macro} \\\n" + " \\\n".join(pieces) + "\n"
        f"\n"
        f"#endif // {guard}\n"
    )
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(header, encoding="ascii")
    return 0


if __name__ == "__main__":
    sys.exit(main())
