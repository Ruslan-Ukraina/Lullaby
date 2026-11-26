# lby-ponthree-pacer

Frame pacing of a game's presentation on Metal, without touching Dormison or D3DMetal (S8, `docs/DECISIONS.md`).

- Injected into the Wine loader's process (`DYLD_INSERT_LIBRARIES`, set by `compat_run.sh` when `lullaby-pacer.dylib` is in the support
  folder), so it sees the Metal calls a game's frames go through: command-buffer and drawable presents, Metal 4's queue
  `signalDrawable:`/`waitForDrawable:`, the layer's `nextDrawable`.
- **Direct (always on with the "Native full screen" setting, S13):** for D3DMetal and DXMT games `compat_run.sh` sets
  `LULLABY_DIRECT=1`; the library then turns the layer's RGB-ordered pixel format (RGB10A2, RGBA8) into its BGR twin when the
  layer is made, which is what lets macOS show it straight to the display ("Direct" in the Metal HUD, no compositor; HDR is
  kept), and keeps V-Sync on for such a layer once its window is in native full screen, which on a ProMotion display lets the
  refresh follow the game (VRR). Anything it does not recognise (another renderer, a layer that is not opaque or not
  Direct-capable, a window that is not in native full screen) is left as the game made it: the plain V-Sync of the game's own
  settings. No setting of its own and no off switch: it rides with "Native full screen" (`LULLABY_NATIVE_FULLSCREEN=0` turns both
  off for a run). The log shows `pacer: direct: ...` lines. Measured: docs/BACKLOG.md S13. Test: `make pacer-tests`.
- **Off unless asked** (the dev modes below). `PACER_MODE` (environment, or `<prefix>/.sevo/lullaby-pacer.conf`, KEY=VALUE): `off` (default), `probe`.
  `PACER_LOG=<path>` sends the lines to a file (default: the game's log).
- `probe`: counts which present calls the game's Metal path makes and logs a summary every 5 s (class, selector, calls, the thread,
  the argument range of the `atTime:`/`afterMinimumDuration:` forms). Changes nothing.
- The modes that time a frame's presentation (`adaptive`, `fixed`) are added only after the probe has said which path to take, and
  only if they hold on the measurements in `tools/perf/` (docs/DECISIONS.md, S8). Priority: stability and wide compatibility; a
  game the pacer cannot handle is left alone.
- `LULLABY_DRAWABLES=2` (an experiment, off unless asked): a game layer keeps two drawables instead of three, one frame
  less waiting to be shown; to be measured with frame generation (2026-11-26).
- `LULLABY_THREAD_QOS=1` (an experiment, off unless asked): every thread of the game's process starts at the
  user-interactive QoS class (pthread_create interposed; checked: 0x21 instead of 0x15, arm64 and x86_64).
- Build: `make pacer` (arm64 + x86_64). Measure: `tools/perf/presentfeed.py` (on-screen intervals) with `LULLABY_PRESENT_FEED=1`.
