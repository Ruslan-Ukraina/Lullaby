# NotProton for Dormison

Play Windows games from your Steam library on a Mac, inside the normal macOS Steam app,
the way Steam Play (Proton) works on Linux.

This is a fork of [NotProton](https://github.com/NotProtonNot/NotProton). The original runs
games on CrossOver. This fork runs them on [Dormison](https://github.com/kageroumado/dormison),
a free Wine engine for macOS, and keeps itself up to date.

## What you get

- **Steam Play in macOS Steam.** A Windows game gets a Play button. Steam's overlay,
  achievements, friends and cloud saves work through a Mac port of Valve's `lsteamclient`.
- **Game settings inside Steam.** Properties → Compatibility shows the renderer, Retina,
  upscaler and FPS counter, with more under "Advanced settings…". Steam Settings →
  Compatibility holds the defaults for all games. English, Ukrainian and Russian.
- **Renderers.** D3DMetal, DXMT (Direct3D 10/11 on Metal, the default), DXVK, WineD3D.
  D3DMetal (needed for Direct3D 12) comes from Apple's Game Porting Toolkit, which you
  download from Apple yourself and add in NotProton. NotProton never ships it.
- **Game windows from Dormison.** Native macOS windows that resize, native full screen,
  upscaling (Lanczos, MetalFX), an FPS counter, raw mouse input and a held cursor; msync
  is always on.
- **Recipes.** Games NotProton knows get the setup that worked best (marked "NotProton
  recipe"); your own choice always wins, and "Restore recipe" goes back.
- **Updates.** The engine (signed by Dormison), the Steam bridge, the Steam signatures and
  the app itself update from signed releases. Steam is held back from a build NotProton
  does not support yet.

## Install

1. You need a Mac with Apple silicon, macOS 27, Rosetta, and Steam in `/Applications`.
2. Open NotProton and press **Install**. It closes Steam gently, patches it, and downloads
   the engine.
3. Start Steam from `/Applications/Steam.app`. In a Windows game's Properties →
   Compatibility, turn on the compatibility tool, then press Play.

The app is not notarized yet: the first time, open it from System Settings → Privacy &
Security → "Open Anyway".

## What is not there

- **Online games with anti-cheat** (VAC, EasyAntiCheat, BattlEye): not tested, do not play
  them online.
- **32-bit games** are not checked on a live game yet.
- **Direct3D 12** needs D3DMetal (your own copy from Apple).
- **Native full screen** (the green button) scales a fixed-size game window; use the game's
  borderless mode for full resolution. A rework is planned.
- Some Steam client builds are not supported until their signatures are published; Steam
  waits for them instead of updating.

## Where things come from

| Part | From | License |
|---|---|---|
| NotProton (this repository) | [NotProton](https://github.com/NotProtonNot/NotProton) by NotProtonNot and contributors, and this fork | GPL-3.0 |
| Engine | [Dormison](https://github.com/kageroumado/dormison) (Wine + wine-staging + its own work) by kageroumado | LGPL-2.1-or-later |
| Settings catalog, texts, graphics card identity | [Sevoflurane](https://github.com/kageroumado/sevoflurane) by kageroumado | MIT |
| Two engine fixes (memory accounting, Retina screen size) | [Highball](https://github.com/gauthierpiarrette/highball-engine) by gauthierpiarrette | LGPL-2.1-or-later |
| `lsteamclient` | Valve's [Proton](https://github.com/ValveSoftware/Proton) | Steamworks SDK License |
| `steam-shim` | Valve's Proton `steam_helper` | BSD-3-Clause |
| DXMT, DXVK, MoltenVK | inside Dormison's release, unchanged | LGPL-2.1-or-later, zlib, Apache-2.0 |
| Function hooks inside Steam | [Dobby](https://github.com/jmpews/Dobby) by Jmpews | Apache-2.0 |
| App updates | [Sparkle](https://sparkle-project.org) | MIT |
| D3DMetal (yours) | Apple Game Porting Toolkit | Apple's license, not distributed |

The details, and which files each part covers, are in [NOTICE](NOTICE).

## For developers

- `app/` — the macOS app and the settings CLI (Swift); `dylib/` — the library loaded into
  Steam; `lsteamclient/`, `steam-shim/` — the Steam bridge; `ntdll-patch/b1/` — the loader
  hook built from Dormison's source; `engine-fixes/` — single engine files rebuilt with
  fixes, each first proven equal to the release.
- `make app` builds the app, `make app-tests` runs the Swift tests; the C and script
  checks are the other targets in the `Makefile`.
- Plans, decisions and progress: `docs/` (in Russian).

Issues and pull requests are welcome.
