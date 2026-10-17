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
