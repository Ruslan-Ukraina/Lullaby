Lullaby r1 (1.1.0)

Windows games from your Steam library on a Mac, in the ordinary Steam for macOS. Rebuilt on the Dormison r7 engine.

What is new
- Engine: Dormison r7 (Wine with wine-staging), msync+ always on, signed downloads with an update that can be rolled back.
- Game properties in Steam (Compatibility): renderer (DXMT, DXVK, D3DMetal, WineD3D), Retina, Metal HUD; Advanced settings: final filter (Off, Bilinear, Lanczos, MetalFX Spatial), thread-waiting tuning (experimental), unified memory, raw mouse, V-Sync (experimental).
- Game windows are always the Mac's own: resize them, use the green button for native full screen; the size of the window and a full screen you chose by hand are remembered for the next launch.
- Raw mouse through GameController: no pointer curve, its speed follows the mouse's own resolution, the trackpad is left to the system; a launch option LULLABY_GCMOUSE_SCALE sets the speed for one run.
- NVIDIA Reflex and DLSS (through MetalFX) are answered for D3DMetal games; the game's Dock icon is rebuilt in the macOS shape from its own art.
- D3DMetal is Apple's: you add it yourself from the Game Porting Toolkit (4.0 beta 3), Lullaby does not distribute it.
- Everything updates from signed releases: the engine, the Steam bridge, the Steam signature database and the app itself. A Steam build without signatures is held back until they exist.

Known limits
- Native full screen for a game that covers the screen by itself is postponed (the game is told a window slightly too tall); the green button works for windowed games.
- Dormison r8 is not supported yet.
- Launch options that change one run: LULLABY_AVX=0, LULLABY_DLSS=0, WINEMSYNC=0, LULLABY_GCMOUSE_SCALE=<number>.
