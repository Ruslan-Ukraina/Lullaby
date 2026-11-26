Lullaby r7 (1.1.0)

Changes since r6
- FSR 4 for DLSS (experimental): in a game's Advanced settings, Diagnostics, "FSR 4 instead of MetalFX" upscales the game's DLSS with AMD's FSR 4 (fsr4-native-macos, prepared by Lullaby, no Xcode or Python needed). The component downloads when you turn it on, with a small progress line under the row. MetalFX's own frame generation then runs at the game's size: in Resident Evil Requiem about 8 % more frames.
- ANR frame generation (experimental): "ANR frame generation" makes the in-between frames with Apex's ANR instead of MetalFX, at the same cost and with fewer artefacts at the screen's edge when the camera turns. It downloads when you turn it on.
- Reflex by Lullaby keeps a tighter margin only while frame generation runs: lower latency with frame generation and V-Sync, nothing changes without it. LULLABY_REFLEX_AGGRESSIVE=0 turns it off for one run.
- The Metal HUD row of a game takes effect again: Lullaby's fixes no longer make a Metal device before the engine applies the game's settings.
- Components: mtld3d 0.15.5, WineMetalGL 4.1.0.

Known limits
- The app is not signed by an Apple Developer ID: the first time, macOS has to be told to open it (README, "First start").
- Resident Evil Requiem froze once when a save was changed during testing and did not again; if it happens to you, Lullaby does not know why yet.
- Dormison r8 is not supported yet (its archive carries Apple's files).
- On OpenGL (WineMetalGL) the picture can stay at the old size after a window changes size; the Metal HUD frame counter does not show there.
- Resident Evil Requiem with HDR on shows a pale picture; not rechecked in native full screen yet.
- FSR 4 and ANR are experiments: they may load the GPU more than MetalFX and may not work with every game. ANR 3x is not offered (it needs a fourth drawable that D3DMetal does not leave).
- Native Vulkan games run on MoltenVK; KosmicKrisp is opt-in only (LULLABY_VULKAN=kosmickrisp) and not recommended yet.
- Launch options that change one run: LULLABY_UPSCALER=fsr4, LULLABY_FG=anr, LULLABY_REFLEX_AGGRESSIVE=0, LULLABY_AVX=0, LULLABY_DLSS=0, WINEMSYNC=0, LULLABY_GCMOUSE_SCALE=<number>, LULLABY_LOW_LATENCY=0, LULLABY_NATIVE_FULLSCREEN=0 (also turns Direct off), LULLABY_FULLSCREEN_SIZE=0, LULLABY_AUDIO_FOLLOW=0, LULLABY_MOUSELOOK=0, LULLABY_KEEP_DISPLAY_MODE=0, LULLABY_FULLSCREEN_FILL=0, LULLABY_MESH_FS=0, LULLABY_TESS_FIT=0, LULLABY_INDIRECT_ARGS=0.

Windows games from your Steam library on a Mac, in the ordinary Steam for macOS, on the Dormison r7 engine.
- Engine: Dormison r7 (Wine with wine-staging), msync+ always on, signed downloads with an update that can be rolled back.
- Game properties in Steam (Compatibility): renderer (Auto, D3DMetal, DXMT, mtld3d, WineMetalGL, MoltenVK), Retina, Metal HUD, Native full screen; Advanced settings: final filter (Off, Bilinear, Lanczos, MetalFX Spatial), thread-waiting tuning (experimental), unified memory, raw mouse, V-Sync (experimental).
- The window of a windowed game is the Mac's own: resize it, use the green button for native full screen; the size of the window and a full screen you chose by hand are remembered for the next launch.
- Raw mouse through GameController: no pointer curve, its speed follows the mouse's own resolution, the trackpad is left to the system; a launch option LULLABY_GCMOUSE_SCALE sets the speed for one run.
- NVIDIA Reflex and DLSS (through MetalFX) are answered for D3DMetal games; the game's Dock icon is rebuilt in the macOS shape from its own art.
- D3DMetal is Apple's: you add it yourself from the Game Porting Toolkit (4.0 beta 3), Lullaby does not distribute it.
- Everything updates from signed releases: the engine, the Steam bridge, the Steam signature database and the app itself. A Steam build without signatures is held back until they exist.
