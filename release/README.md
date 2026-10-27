# release
Signing, update feeds, publishing and CI helper scripts. Never keys or tokens.

## components.json and check-components.py
`components.json` lists every external part Lullaby is made of, tries or watches (engine, renderers, drivers, libraries, sources of patches) with the version it is pinned to, its licence and how to look for a newer one. `python3 -I release/check-components.py` asks GitHub, GitLab and LunarG and prints what is newer; it writes nothing and moves no pin. Run it once a month and before a release; `--validate` (`make componentcheck`) is the offline check that the list is well formed and that each pin agrees with the file it comes from.

