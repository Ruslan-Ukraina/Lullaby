Lullaby r5 (1.1.0)

Changes since r4
- Direct presentation and variable refresh for D3DMetal and DXMT games. A game that goes to native full screen (the "Native full screen" row in the game's properties, on for every game) is now shown straight to the display, as the Metal HUD says ("Direct" instead of "Composited"), with V-Sync on, so a ProMotion screen follows the game's frame rate. Resident Evil Requiem: 70-80 steady frames a second in its heaviest opening scene with no tearing and no ladder steps (20-30 more than before, and even), a faster menu and lighter input; Euro Truck Simulator 2 follows its frame rate between 60 and 120 smoothly. HDR is kept. Games on MoltenVK, mtld3d, WineMetalGL or WineD3D, and a game with the row switched off, are shown as in r4.
- A Unity game that Steam starts with -force-vulkan now follows the renderer you chose: with DXMT or D3DMetal selected, the flag is replaced by -force-d3d11 or -force-d3d12 for that run (PEAK did not start on DXMT before).
- The pacer (lby-ponthree-pacer) is part of the app and always on in Direct; there is no switch for it: switching "Native full screen" off turns it off with the rest.

Known limits
- Resident Evil Requiem froze once when a save was changed during testing and did not again; if it happens to you, Lullaby does not know why yet.
- Dormison r8 is not supported yet (its archive carries Apple's files).
- On OpenGL (WineMetalGL) the picture can stay at the old size after a window changes size; the Metal HUD frame counter does not show there.
- Resident Evil Requiem with HDR on shows a pale picture; not rechecked in native full screen yet.
- Native Vulkan games run on MoltenVK; KosmicKrisp is opt-in only (LULLABY_VULKAN=kosmickrisp) and not recommended yet.
- Launch options that change one run: LULLABY_AVX=0, LULLABY_DLSS=0, WINEMSYNC=0, LULLABY_GCMOUSE_SCALE=<number>, LULLABY_LOW_LATENCY=0, LULLABY_NATIVE_FULLSCREEN=0 (also turns Direct off), LULLABY_FULLSCREEN_SIZE=0, LULLABY_AUDIO_FOLLOW=0.

Windows games from your Steam library on a Mac, in the ordinary Steam for macOS, on the Dormison r7 engine.
- Engine: Dormison r7 (Wine with wine-staging), msync+ always on, signed downloads with an update that can be rolled back.
- Game properties in Steam (Compatibility): renderer (Auto, D3DMetal, DXMT, mtld3d, WineMetalGL, MoltenVK), Retina, Metal HUD, Native full screen; Advanced settings: final filter (Off, Bilinear, Lanczos, MetalFX Spatial), thread-waiting tuning (experimental), unified memory, raw mouse, V-Sync (experimental).
- The window of a windowed game is the Mac's own: resize it, use the green button for native full screen; the size of the window and a full screen you chose by hand are remembered for the next launch.
- Raw mouse through GameController: no pointer curve, its speed follows the mouse's own resolution, the trackpad is left to the system; a launch option LULLABY_GCMOUSE_SCALE sets the speed for one run.
- NVIDIA Reflex and DLSS (through MetalFX) are answered for D3DMetal games; the game's Dock icon is rebuilt in the macOS shape from its own art.
- D3DMetal is Apple's: you add it yourself from the Game Porting Toolkit (4.0 beta 3), Lullaby does not distribute it.
- Everything updates from signed releases: the engine, the Steam bridge, the Steam signature database and the app itself. A Steam build without signatures is held back until they exist.
