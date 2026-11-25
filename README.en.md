<h1 align="center"><img src="docs/banner.en.jpg" alt="Lullaby: Windows games in the ordinary Steam for macOS" width="100%"></h1>

<p align="center"><a href="README.md">Українська</a> · <b>English</b></p>

Play the Windows games of your Steam library right on a Mac, in the ordinary Steam for macOS, the way Steam Play (Proton) works on Linux. You get the full Steam gaming experience with a bias towards being native on the Mac. All of it thanks to the [Dormison](https://github.com/kageroumado/dormison) engine (Wine for macOS).

[![Lullaby: відео](https://img.youtube.com/vi/i7PQ9IO-7fU/maxresdefault.jpg)](https://youtu.be/i7PQ9IO-7fU)

## Installation

1. You need an Apple silicon Mac, macOS 26 or newer, Rosetta and Steam in `/Applications`.
   Download `Lullaby-….zip` from the [latest release](https://github.com/Ruslan-Ukraina/Lullaby/releases/latest), unzip it and move Lullaby to `/Applications`.
2. Open Lullaby and press **Install**. It closes Steam carefully, patches it and downloads the engine.
3. Start Steam from `/Applications/Steam.app`. On a Windows game open "Properties → Compatibility", turn the compatibility tool on, and press Play.


The app is not notarized by Apple, so the first time open it through "System Settings → Privacy & Security → Open Anyway".

## Lullaby patches

| Patch | What it does |
|---|---|
| `lby-trixie-fullscreen` | Native full screen: a borderless full-screen game goes to macOS native full screen by itself, and a picture smaller than the screen (say 1920×1200) is stretched to the whole screen without distortion; the size and state of the game's window are remembered (engine patches ENG-12, ENG-15 and `lby-pinkiepie-windowstate`). |
| `lby-ponthree-pacer` | Direct and Reflex: the picture goes straight to the display (no window compositor) with V-Sync, so a ProMotion screen (VRR) follows the game; NVIDIA Reflex for D3DMetal games, DLSS goes through MetalFX (`lby-rainbowdash-reflex`). |
| `lby-octavia-gcmouse` | Input and sound: raw mouse through GameController (no pointer curve, the trackpad stays the system's); sound follows the output device and the microphone. |
| `lby-derpy-fixes` | Small fixes of Wine: memory, Retina, hardware GPU scheduling, the window view for WineMetalGL; adaptation to D3DMetal 4.0 beta 3. |

Besides the patches, Lullaby includes the app with game settings, automatic renderer choice, the Steam overlay and game icons.

## Credits and licences

| Частина | Звідки | Ліцензія |
|---|---|---|
| Lullaby (цей репозиторій) | на основі [NotProton](https://github.com/NotProtonNot/NotProton) від NotProtonNot і співавторів | GPL-3.0 |
| Рушій | [Dormison](https://github.com/kageroumado/dormison) (Wine + wine-staging + власні напрацювання) від kageroumado | LGPL-2.1-or-later |
| Каталог налаштувань, тексти, ідентифікація відеокарти | [Sevoflurane](https://github.com/kageroumado/sevoflurane) від kageroumado | MIT |
| Два виправлення рушія (облік пам'яті, розмір екрана Retina) | [Highball](https://github.com/gauthierpiarrette/highball-engine) від gauthierpiarrette | LGPL-2.1-or-later |
| Сира миша через GameController | [WineForge](https://github.com/Alien4042x/WineForge), у ньому Wine MR !11799 від Elvin Hayatov | LGPL-2.1-or-later |
| `lsteamclient` | [Proton](https://github.com/ValveSoftware/Proton) від Valve | Steamworks SDK License |
| `steam-shim` | `steam_helper` з Proton від Valve | BSD-3-Clause |
| DXMT, DXVK, MoltenVK | усередині релізу Dormison, без змін | LGPL-2.1-or-later, zlib, Apache-2.0 |
| Назви й структури для відповіді NVIDIA Reflex | [nvapi](https://github.com/NVIDIA/nvapi) від NVIDIA | MIT |
| Перехоплення функцій усередині Steam | [Dobby](https://github.com/jmpews/Dobby) від Jmpews | Apache-2.0 |
| Оновлення застосунку | [Sparkle](https://sparkle-project.org) | MIT |
| Direct3D 9 через Metal (завантажується в автора, коли знадобиться) | [mtld3d](https://github.com/athei/mtld3d) від athei | zlib |
| OpenGL через Metal (завантажується в автора, коли знадобиться) | [WineMetalGL](https://github.com/metalsharp/WineMetalGL) від MetalSharp | LGPL-3.0-or-later |
| D3DMetal (ваш) | Apple Game Porting Toolkit | ліцензія Apple, не поширюється |

Details, and which files belong to which part, are in [NOTICE](NOTICE).

## For developers

The map of the repository is `docs/STRUCTURE.md`, component names `docs/NAMING.md`, project rules `docs/PROJECT_RULES.md`. `make app` builds the app, `make app-tests` runs the Swift tests, `make patchcheck` checks the patches against the registry `patches/REGISTRY.md`.
