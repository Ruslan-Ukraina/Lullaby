# lby-photofinish-stream (test build)

Streaming a game without screen capture. Screen capture (ScreenCaptureKit, OBS's "macOS Screen Capture") reads the
composited screen and can take a game off direct-to-display, which costs frames and latency. `lullaby-stream.dylib`
instead copies each frame the game presents, on the GPU, into a Syphon server's IOSurface just before it goes to the
screen; OBS's **Syphon Client** source reads that surface. The game keeps its window, its settings and Direct; nothing is
drawn into its frame.

| Launch option or game setting | Effect |
|---|---|
| `LULLABY_STREAM=1` | the server, named `Lullaby: <game exe>`; log in the loader's `lullaby-stream.log` |
| `LULLABY_STREAM_SYNC=1` | the present waits for the copy (Metal 4 path; by default it does not, see below) |
| `LULLABY_SYPHON_FRAMEWORK=<path>` | a Syphon.framework of one's own |

In OBS: Sources, +, Syphon Client, server `Lullaby: <game>`.

## How

Loaded into the Wine loader's process (`DYLD_INSERT_LIBRARIES`, `steam/hook/feats/compat_run.sh`, when
`~/Library/Application Support/lullaby/components/stream/lullaby-stream.dylib` exists and `LULLABY_STREAM=1`).
- Metal 3 (`-[MTLCommandBuffer presentDrawable:...]`, DXMT and native Metal): the copy goes into the game's command
  buffer, before its present.
- Metal 4 (`-[MTL4CommandQueue signalDrawable:]`, D3DMetal): the game's queue signals a shared event after its frame, a
  Metal 3 queue of ours waits for it and copies. The present does not wait: a drawable returns to the layer's pool only
  after a later one is on the screen, long after a one-frame copy.
- The layer's drawables must be readable: `framebufferOnly` is turned off for every layer while streaming.
- Syphon.framework (BSD-2, Syphon/Syphon-Framework) is opened at run time, never linked: `components/stream/`, then
  OBS's own copy in `/Applications/OBS.app`. Without either the library does nothing. OBS users therefore need nothing
  more.

Cost (to be measured in a game): one GPU copy of the frame (about 0.1 ms at 2294x1290 on M4 Pro is the estimate) and one
IOSurface of the frame's size.

## Build and test

`patches/inject/lby-photofinish-stream/build.sh <out dir>` builds `lullaby-stream.dylib` (arm64 + x86_64) and
`stream_test`. The test presents frames both ways through a CAMetalLayer and reads them back through a Syphon client
(pixels and orientation); run it directly (not through `arch` or `timeout`, which drop `DYLD_INSERT_LIBRARIES`):
`LULLABY_STREAM=1 DYLD_INSERT_LIBRARIES=<out>/lullaby-stream.dylib <out>/stream_test`. With no Syphon.framework it says
SKIP. 2026-11-25: both paths pass on arm64 and under Rosetta (x86_64), with and without `LULLABY_STREAM_SYNC`.

## Still open

- In a game: whether screen capture really leaves Direct (Metal HUD), the copy's cost, OBS's picture.
- HDR games: the surface takes the drawable's format as is; OBS may show an RGB10A2 or float frame differently.
- Release: Syphon.framework from source with its licence notice, if Lullaby ships one at all (OBS brings its own).
