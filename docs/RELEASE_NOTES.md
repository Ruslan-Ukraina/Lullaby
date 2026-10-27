Lullaby r4 (1.1.0)

Changes since r3
- A game now picks its own renderer. Auto (the default) reads which graphics API the game uses and chooses: DX12 on D3DMetal, DX11 on DXMT, DX9 on mtld3d, OpenGL on WineMetalGL, Vulkan on MoltenVK. Your own choice in the game's properties still wins. mtld3d and WineMetalGL are downloaded the first time a game needs them (pinned and checked).
- A game that covers the screen goes to macOS's own full screen by itself: its own desktop, the picture under the notch at the screen's full resolution (3024x1898 on a 14" MacBook Pro), and the game is told that size. A new row "Native full screen" in the game's properties (and in Steam's Compatibility settings for all games) is on for every game; LULLABY_NATIVE_FULLSCREEN=0 turns it off for one run, LULLABY_FULLSCREEN_SIZE=0 keeps the old scaled picture.
- Sound follows the output device: connect headphones and the game's sound moves to them, disconnect and it comes back, with no restart (LULLABY_AUDIO_FOLLOW=0 turns it off for one run). The microphone does not follow yet.
- 32-bit games (for example The Binding of Isaac: Rebirth) run: the bridge carries the 32-bit Steam files.
- OpenGL games: Euro Truck Simulator 2 no longer says "no devices found" on OpenGL, and a window that grows no longer flashes magenta; the picture of an OpenGL game follows its window.
- Every external part Lullaby is made of is listed with its pinned version in release/components.json; a script checks what is newer (nothing changes by itself).

Known limits
- Dormison r8 is not supported yet (its archive carries Apple's files).
- On OpenGL (WineMetalGL) the picture can stay at the old size after a window changes size; the Metal HUD frame counter does not show there.
- Resident Evil Requiem with HDR on shows a pale picture; not rechecked in native full screen yet.
- Native Vulkan games run on MoltenVK; KosmicKrisp is opt-in only (LULLABY_VULKAN=kosmickrisp) and not recommended yet.
- Launch options that change one run: LULLABY_AVX=0, LULLABY_DLSS=0, WINEMSYNC=0, LULLABY_GCMOUSE_SCALE=<number>, LULLABY_LOW_LATENCY=0, LULLABY_NATIVE_FULLSCREEN=0, LULLABY_FULLSCREEN_SIZE=0, LULLABY_AUDIO_FOLLOW=0.

Windows games from your Steam library on a Mac, in the ordinary Steam for macOS, on the Dormison r7 engine.
- Engine: Dormison r7 (Wine with wine-staging), msync+ always on, signed downloads with an update that can be rolled back.
- Game properties in Steam (Compatibility): renderer (Auto, D3DMetal, DXMT, mtld3d, WineMetalGL, MoltenVK), Retina, Metal HUD, Native full screen; Advanced settings: final filter (Off, Bilinear, Lanczos, MetalFX Spatial), thread-waiting tuning (experimental), unified memory, raw mouse, V-Sync (experimental).
- The window of a windowed game is the Mac's own: resize it, use the green button for native full screen; the size of the window and a full screen you chose by hand are remembered for the next launch.
- Raw mouse through GameController: no pointer curve, its speed follows the mouse's own resolution, the trackpad is left to the system; a launch option LULLABY_GCMOUSE_SCALE sets the speed for one run.
- NVIDIA Reflex and DLSS (through MetalFX) are answered for D3DMetal games; the game's Dock icon is rebuilt in the macOS shape from its own art.
- D3DMetal is Apple's: you add it yourself from the Game Porting Toolkit (4.0 beta 3), Lullaby does not distribute it.
- Everything updates from signed releases: the engine, the Steam bridge, the Steam signature database and the app itself. A Steam build without signatures is held back until they exist.
