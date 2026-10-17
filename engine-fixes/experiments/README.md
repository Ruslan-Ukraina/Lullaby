# Engine experiments (not built into any bridge)

Patches here are not in `engine-fixes/patches`, so neither `build-fixes.sh` nor the bridge
workflow applies them. Each applies on top of `patches/winemac.so/0001..0003`.

- `0004-winemac-lullaby-native-fullscreen-at-start.patch` — `LULLABY_NATIVE_FULLSCREEN=1`:
  the first window that can go full screen enters macOS's full screen when it shows; it stays
  there when the program makes it borderless (RE9 does on entering); the D3DMetal layer is
  made opaque; debug lines in the Wine log. RE9 then draws 3024×1898 in full screen below the
  notch. Still "Composited". 2026-10-17, docs/NOTCH_FULLSCREEN.md.
- `0004-winemac-lullaby-direct-display-clear-layers.patch` — the above plus
  `LULLABY_DIRECT_DISPLAY=1`: every second, clear the background colours and images of the
  views above the game's Metal view (WoWSilicon/WoWSilicon#25). Wine refills two of them
  within a second; still "Composited". Next step would be to stop Wine filling them while a
  metal view covers the window, and `LULLABY_TEST_NO_EDR=1` (diagnostic, wrong colours).
- `0004-winemac-lullaby-direct-display-re9.patch` — the source-level fix, only for `re9.exe`
  (image name checked in `macdrv_init`) or `LULLABY_DIRECT_DISPLAY=1`: while the game's Metal
  view covers its window, `WineContentView` keeps the surface image out of its layer
  (`updateLayer`), the black backgrounds stay off, the metal layer is opaque and the content
  view reports itself opaque so AppKit does not fill the window frame. Builds clean against
  r6 (2026-10-17); the first run showed "direct display: on for this program", but the Mac
  locked before the HUD could be read — not yet verified.
- `0004-winemac-lullaby-re9-native-fullscreen-direct.patch` — the owner's target (2026-10-17):
  macOS native full screen (below the camera housing is fine) at the window's own resolution
  and not composited, RE9 only. The direct-display patch above plus: the game's window enters
  macOS full screen the first time it can, and stays there when the game makes it borderless.
  Needs RE9's window treatment "Fixed-size and full-screen games" (`windows = window`) so its
  window can go full screen — to go into the RE9 recipe together with the bridge. Builds clean
  against r6; not yet run (the Mac was locked).
- `0004-winemac-lullaby-re9-native-fullscreen-direct-v2.patch` — run on RE9 2026-10-17 (owner
  present): native full screen enters by itself, 3024×1898, picture fills the screen below the
  housing, 80 fps in the menu. Wine's layers are clear (dump: both WineContentView layers
  without contents or background); AppKit's frame layers (CABackdropLayer, CUIWindowFrameLayer,
  NSVisualEffectView with CAChameleonLayer) hidden in full screen; the hidden toolbar removed —
  the NSToolbarFullScreenWindow (alpha 0, 1512×32) stays. Metal HUD: still "Composited".
  Left to rule out: the game's HDR output (RGB10A2, ITU-R 2100 PQ, EDR) — needs HDR off in
  RE9's own menu.
- `0004-winemac-lullaby-re9-native-fullscreen-direct-v5.patch` — with the owner, RE9 in
  Borderless with HDR off (2026-10-17): native full screen, 3024×1898; additionally the
  full-screen toolbar window ordered out, rounded/masked corners off (there were none), and
  EDR refused for an sRGB picture (D3DMetal asks for EDR even in SDR). Final state of the
  game's layer: RGB10A2Unorm (90), 3024×1898, opaque, framebufferOnly, no EDR, sRGB,
  identity transforms; everything around it hidden. Metal HUD: still "Composited".
  Remaining suspect: the pixel format — D3DMetal presents RE9's 10-bit swapchain as
  RGB10A2Unorm, which the display may not scan out (BGRA8/BGR10A2/RGBA16Float are the
  usual direct formats). Changing it means intercepting how D3DMetal draws into the drawable.
