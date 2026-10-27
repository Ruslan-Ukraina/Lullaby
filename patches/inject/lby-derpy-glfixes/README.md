# lby-derpy-glfixes

Two faults of WineMetalGL (OpenGL on Metal, CMP-10) worked around from outside until its author mends them. Injected into the
Wine loader's process (`DYLD_INSERT_LIBRARIES`, `lullaby-glfixes.dylib`, set by `compat_run.sh`); does nothing unless the process
runs WineMetalGL (`WINEDLLOVERRIDES` names `winemetalgl`). Uses names only (a symbol, a label), no offsets; arm64 and x86_64.

- **GLF-01, 32 bits of colour.** WineMetalGL lists its RGBA8 pixel formats with `cColorBits` 24 (colour without alpha); NVIDIA, AMD,
  Intel and Wine's own driver say 32, and a game that asks for `WGL_COLOR_BITS >= 32` finds no format (Euro Truck Simulator 2 on
  OpenGL: "no devices found", `[gl] wglChoosePixelFormatARB failed`). The unix side of WineMetalGL gets the list with
  `dlsym(wmgl_get_pixel_formats)`; the library takes that one lookup (`__DATA,__interpose`) and gives back a function that sets 32 in
  the list the call fills. Switch: `LULLABY_GL_COLOR_BITS=0` turns it off for a run. Report to the author:
  `agent/reports/winemetalgl-issue-draft-color-bits.md` (private).
- **GLF-02, a black window texture.** The colour texture of a window (label `default framebuffer`, private storage) is never cleared,
  at the start and when the window changes size; a game that swaps before it has drawn (a loading screen) showed the GPU's old memory,
  a flat magenta rectangle at the switch to native full screen. `MTLTexture setLabel:` is taken, and a texture given that label is
  cleared to black at once (waited for, before WineMetalGL copies the old picture into it). Switch: `LULLABY_GL_CLEAR=0`. Report:
  `agent/reports/winemetalgl-issue-draft-resize-uninitialised.md` (private).
- Both go when WineMetalGL mends them: `release/check-components.py` shows a newer WineMetalGL; read its notes, then remove what no
  longer applies (and the library when nothing is left).
- Tests: `make glfixes-tests` (a fake core library and a Metal texture, in a program named like the Wine loader; on, off and "not
  WineMetalGL"; arm64 and x86_64). By hand: `patches/engine/tests/wgl-pixel-formats.c` under WineMetalGL (`COLOR_BITS>=32` finds formats).
