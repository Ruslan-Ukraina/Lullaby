Lullaby r2 (1.1.0)

Fixes two regressions of r1 that players noticed. Update from r1.

Fixed
- A game that goes to full screen by itself ("Window (borderless)" in the game's own settings) covers the whole screen again; in r1 it became an ordinary window with a title bar.
- Frames per second are back: Lullaby's own NVIDIA Reflex answer held D3DMetal games back (RE9's menu: 83 frames a second instead of 96). It is off by default again; the launch option LULLABY_LOW_LATENCY=1 turns it on for one run.

Windows games from your Steam library on a Mac, in the ordinary Steam for macOS, on the Dormison r7 engine.
- Engine: Dormison r7 (Wine with wine-staging), msync+ always on, signed downloads with an update that can be rolled back.
- Game properties in Steam (Compatibility): renderer (DXMT, DXVK, D3DMetal, WineD3D), Retina, Metal HUD; Advanced settings: final filter (Off, Bilinear, Lanczos, MetalFX Spatial), thread-waiting tuning (experimental), unified memory, raw mouse, V-Sync (experimental).
- The window of a windowed game is the Mac's own: resize it, use the green button for native full screen; the size of the window and a full screen you chose by hand are remembered for the next launch.
- Raw mouse through GameController: no pointer curve, its speed follows the mouse's own resolution, the trackpad is left to the system; a launch option LULLABY_GCMOUSE_SCALE sets the speed for one run.
- DLSS is answered through MetalFX for D3DMetal games; the game's Dock icon is rebuilt in the macOS shape from its own art.
- D3DMetal is Apple's: you add it yourself from the Game Porting Toolkit (4.0 beta 3), Lullaby does not distribute it.
- Everything updates from signed releases: the engine, the Steam bridge, the Steam signature database and the app itself. A Steam build without signatures is held back until they exist.

Known limits
- Native full screen for a game that covers the screen by itself is postponed (the game would be told a window slightly too tall).
- Dormison r8 is not supported yet.
- Launch options that change one run: LULLABY_AVX=0, LULLABY_DLSS=0, WINEMSYNC=0, LULLABY_GCMOUSE_SCALE=<number>, LULLABY_LOW_LATENCY=1.
