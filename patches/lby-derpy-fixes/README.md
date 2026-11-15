# lby-derpy-fixes

The small fixes of other people's code, in one place. Two parts:

**Fixes in Wine (the engine), links in this folder.** The patches stay in the series `patches/engine/patches/<module>/` (the bridge build
reads them there, in order of their numbers); the links here are named like the patches:
- ENG-01 `0001-ntdll-commit-charge-is-the-footprint.patch`: `PagefileUsage` is the physical footprint (games compare it with memory);
- ENG-02 `0001-win32u-d3dkmt-hardware-gpu-scheduling.patch`: hardware GPU scheduling reported on (Streamline offers frame generation);
- ENG-03 `0001-winemac-retina-horzres-not-doubled.patch`: `HORZRES`/`VERTRES` are not doubled on Retina;
- ENG-10 `0005-winemac-winemetalgl-client-view.patch`: WineMetalGL gets the engine's own metal view (the window follows moves, the title bar is opaque);
- ENG-11 and ENG-14 `0001-winecoreaudio-follow-default-devices.patch`: a render stream on the default output device and a capture stream on the default input device move with them (headphones or a headset in and out);
- ENG-04 and ENG-05 `0002-ntdll-d3dmetal-4b3.patch` and ENG-06 `0002-winemac-d3dmetal-find-best-window.patch`: the adaptation to D3DMetal 4.0 beta 3 (the dispatch table layout and the window search; only for that toolkit).
Not here: the V-Sync and present feed (ENG-07), GCMouse (`lby-octavia-gcmouse`), native full screen (`lby-trixie-fullscreen`).

**Fixes in WineMetalGL (OpenGL on Metal, CMP-10), the injected library `glfixes.m` -> `lullaby-glfixes.dylib`.** Injected into the Wine
loader's process (`DYLD_INSERT_LIBRARIES`, set by `compat_run.sh`); does nothing unless the process runs WineMetalGL (`WINEDLLOVERRIDES`
names `winemetalgl`). Names only (a symbol, a label), no offsets; arm64 and x86_64. Registry ID GLF-02. (GLF-01, 32 colour bits, is gone: WineMetalGL 3.9.0 lists 32 itself.)
- **GLF-02, a black window texture.** The colour texture of a window (label `default framebuffer`, private storage) is never cleared,
  at the start and when the window changes size; a game that swaps before it has drawn (a loading screen) showed the GPU's old memory,
  a flat magenta rectangle at the switch to native full screen. `MTLTexture setLabel:` is taken, and a texture given that label is
  cleared to black at once (waited for, before WineMetalGL copies the old picture into it). Switch: `LULLABY_GL_CLEAR=0`. Report:
  `agent/reports/winemetalgl-issue-draft-resize-uninitialised.md` (private).
- It goes when WineMetalGL mends it: `release/check-components.py` shows a newer WineMetalGL; read its notes, then remove what no
  longer applies.
- Tests: `make glfixes-tests` (a Metal texture, in a program named like the Wine loader; on, off and "not
  WineMetalGL"; arm64 and x86_64).
