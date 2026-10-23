# Repository map

Rule: a directory or link that is not in this table is not created; a new one is added here first. `tools/check-structure` fails when the tree and this table differ (exceptions: `tools/check-structure.allow`).

| Path | Purpose | Put here | Not here | Stream |
|---|---|---|---|---|
| `app/` | Lullaby.app, `lullaby-settings`, `helpers/` (icon maker, app info) | Swift sources, tests, `Info.plist`, icons | built payload (git-ignored), machine paths | App |
| `bridge/` | Steam bridge: `lsteamclient/` (lby-applejack-steambridge), `steam-shim/` (lby-bigmack-steamexe), build scripts, `bridge-manifest.json` | sources, build/verify scripts | engine patches, VR/Vulkan code without a recorded reason | Bridge |
| `engine/` | fetching and verifying the Dormison release | scripts, signature check | engine files, patches | Engine |
| `patches/` | everything added to other people's code (see PROJECT_RULES) | see below | | Patches |
| `patches/REGISTRY.md` | the single registry: ID, origin, verified releases, switch | | | Patches |
| `patches/engine/` | patches to Dormison modules per module, `lby-discord-ntdllhook`, rebuild/rehearsal tools, probe programs | `.patch` with header, tests | whole foreign sources | Patches |
| `patches/inject/` | components injected without rebuilding the engine (`lby-rainbowdash-reflex`, `lby-pinkiepie-windowstate`) | one directory per component | | Patches |
| `patches/steam/` | links to the components that patch Steam: `lby-luna-steamhook` -> `steam/hook`, `lby-spike-overlay` -> `steam/overlay` | links only | real files | Patches |
| `steam/hook/` | library loaded into Steam: hooks, resolver, Steam Play entry, panel, game launch script | C/ObjC/JS/sh, tests, fixtures | | App |
| `steam/overlay/` | Steam overlay in games | `.m`, tests | | Patches |
| `steam/signatures/` | signature databases per Steam build | JSON, `manifest.json` | hand edits | Release |
| `release/` | signing, feeds, publishing, CI scripts | scripts | keys, tokens | Release |
| `tools/` | developer tools: `perf/` bench stand, importers, `check-structure` | scripts, fixtures | personal or machine-specific scripts | Release |
| `vendor/` | pinned third-party files | cJSON, how to fetch Dobby/Sparkle | fetched trees (ignored) | Release |
| `docs/` | documentation for people | | agent journals, reports | all |
| `.github/` | CI | workflows | | Release |
| `LICENSE*`, `NOTICE`, `README.md`, `Makefile`, `.gitignore` | licences, attribution, entry, build | | | |

Git-ignored work directories used by build scripts: `build/`, `out/`, `scratch/` (disposable, never published).

## Moving files (protocol)
Map first, then `git mv`, one logical move per commit, all references updated in that commit, build and tests of the affected component before and after; if not green after, revert the move. Files the app or engine read at run time (bundle layout, `~/Library/Application Support/lullaby/*`, `.sevo/*.env`, names inside signed releases) are not moved without the owner's approval.
