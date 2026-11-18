Lullaby r6 (1.1.0)

Changes since r5
- Lullaby is open: the repository and its releases are public, and updates of the app, the engine, the Steam bridge and the signature database are read without a GitHub token. A friend installs Lullaby and it updates itself like yours.
- Mouse look stays in the game: while a game hides the cursor (aiming, a camera), the real pointer is held where the game put it, so it no longer runs into the Dock, the menu bar or a hot corner, and a motionless arrow no longer shows; a game's own menu pointer (Resident Evil Requiem) still moves (ENG-16). LULLABY_MOUSELOOK=0 turns it off for one run.
- A game that asks for a display mode no longer switches the whole Mac's screen (Modern Warfare Remastered set it to 48 Hz); the game gets its answer and the picture is scaled (ENG-17). LULLABY_KEEP_DISPLAY_MODE=0 turns it off for one run.
- In native full screen a picture whose shape is within 5% of the screen's fills it instead of leaving a thin strip (ENG-18). LULLABY_FULLSCREEN_FILL=0 turns it off for one run. Both follow the game's "Native full screen" row.
- Call of Duty: Modern Warfare Remastered on DXMT plays its campaign: no abort after a mission loads, no tessellation pipeline errors and no GPU hang that froze the display (MTL-01, MTL-02, MTL-03, worked around from outside DXMT v0.80; not tied to one game). LULLABY_MESH_FS=0, LULLABY_TESS_FIT=0 and LULLABY_INDIRECT_ARGS=0 turn each off for one run.
- A small Wine message box is no longer taken for the game's window (its size squeezed the real window).
- Steam bridge dormison-r7-4 (engine Dormison r7, unchanged) carries ENG-16, ENG-17 and ENG-18; close engine patches are joined into one each (14 become 11, the Wine they build is byte for byte the same).
- Components: Sparkle 2.10.1, mtld3d 0.15.3, WineMetalGL 3.9.0 (it lists 32 colour bits itself, so Lullaby's own fix for that is gone).

Known limits
- The app is not signed by an Apple Developer ID: the first time, macOS has to be told to open it (README, "First start").
- Resident Evil Requiem froze once when a save was changed during testing and did not again; if it happens to you, Lullaby does not know why yet.
- Dormison r8 is not supported yet (its archive carries Apple's files).
- On OpenGL (WineMetalGL) the picture can stay at the old size after a window changes size; the Metal HUD frame counter does not show there.
- Resident Evil Requiem with HDR on shows a pale picture; not rechecked in native full screen yet.
- Native Vulkan games run on MoltenVK; KosmicKrisp is opt-in only (LULLABY_VULKAN=kosmickrisp) and not recommended yet.
- Launch options that change one run: LULLABY_AVX=0, LULLABY_DLSS=0, WINEMSYNC=0, LULLABY_GCMOUSE_SCALE=<number>, LULLABY_LOW_LATENCY=0, LULLABY_NATIVE_FULLSCREEN=0 (also turns Direct off), LULLABY_FULLSCREEN_SIZE=0, LULLABY_AUDIO_FOLLOW=0, LULLABY_MOUSELOOK=0, LULLABY_KEEP_DISPLAY_MODE=0, LULLABY_FULLSCREEN_FILL=0, LULLABY_MESH_FS=0, LULLABY_TESS_FIT=0, LULLABY_INDIRECT_ARGS=0.

Windows games from your Steam library on a Mac, in the ordinary Steam for macOS, on the Dormison r7 engine.
- Engine: Dormison r7 (Wine with wine-staging), msync+ always on, signed downloads with an update that can be rolled back.
- Game properties in Steam (Compatibility): renderer (Auto, D3DMetal, DXMT, mtld3d, WineMetalGL, MoltenVK), Retina, Metal HUD, Native full screen; Advanced settings: final filter (Off, Bilinear, Lanczos, MetalFX Spatial), thread-waiting tuning (experimental), unified memory, raw mouse, V-Sync (experimental).
- The window of a windowed game is the Mac's own: resize it, use the green button for native full screen; the size of the window and a full screen you chose by hand are remembered for the next launch.
- Raw mouse through GameController: no pointer curve, its speed follows the mouse's own resolution, the trackpad is left to the system; a launch option LULLABY_GCMOUSE_SCALE sets the speed for one run.
- NVIDIA Reflex and DLSS (through MetalFX) are answered for D3DMetal games; the game's Dock icon is rebuilt in the macOS shape from its own art.
- D3DMetal is Apple's: you add it yourself from the Game Porting Toolkit (4.0 beta 3), Lullaby does not distribute it.
- Everything updates from signed releases: the engine, the Steam bridge, the Steam signature database and the app itself. A Steam build without signatures is held back until they exist.
