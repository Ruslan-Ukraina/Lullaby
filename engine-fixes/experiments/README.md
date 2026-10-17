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
