# Lullaby

[Українська](README.md) · **English**

Play the Windows games of your Steam library right on a Mac, in the ordinary Steam for macOS, the way Steam Play (Proton) works on Linux. You get the full Steam gaming experience with a bias towards being native on the Mac. All of it thanks to the [Dormison](https://github.com/kageroumado/dormison) engine (Wine for macOS).

[![Lullaby: відео](https://img.youtube.com/vi/i7PQ9IO-7fU/maxresdefault.jpg)](https://youtu.be/i7PQ9IO-7fU)

## Installation

1. You need an Apple silicon Mac, macOS 26 or newer, Rosetta and Steam in `/Applications`.
2. Open Lullaby and press **Install**. It closes Steam carefully, patches it and downloads the engine.
3. Start Steam from `/Applications/Steam.app`. On a Windows game open "Properties → Compatibility", turn the compatibility tool on, and press Play.


The app is not notarized by Apple, so the first time open it through "System Settings → Privacy & Security → Open Anyway".

## Lullaby patches and components

| Component | What it does |
|---|---|
| `lby-pinkiepie-windowstate` | Remembers the size and full-screen state of a game's window; a borderless full-screen game goes to macOS native full screen by itself. |
| `lby-ponthree-pacer` | Direct: the picture goes straight to the display (no window compositor) with V-Sync, so a ProMotion screen (VRR) follows the game. |
| `lby-rainbowdash-reflex` | NVIDIA Reflex for D3DMetal games; DLSS goes through MetalFX. |
| `lby-spitfire-apiscout` | Automatic renderer choice: finds out in a few seconds which graphics API a game uses. |
| `lby-octavia-gcmouse` | Raw mouse through GameController: no pointer curve, the trackpad stays the system's. |
| `lby-derpy-fixes` | Small fixes of Wine and WineMetalGL: memory, Retina, sound that follows the output device and the microphone. |
| `lby-rarity-icons` | Game icons and names in the Dock in the macOS shape. |
| `ENG-12, ENG-15 (winemac)` | Native full screen: a picture smaller than the screen (say 1920×1200) is stretched to the whole screen without distortion. |

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
