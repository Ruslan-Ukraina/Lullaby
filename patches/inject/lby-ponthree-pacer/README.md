# lby-ponthree-pacer

Frame pacing of a game's presentation on Metal, without touching Dormison or D3DMetal (S8, `docs/DECISIONS.md`).

- Injected into the Wine loader's process (`DYLD_INSERT_LIBRARIES`, set by `compat_run.sh` when `lullaby-pacer.dylib` is in the support
  folder), so it sees the Metal calls a game's frames go through: command-buffer and drawable presents, Metal 4's queue
  `signalDrawable:`/`waitForDrawable:`, the layer's `nextDrawable`.
- **Off unless asked.** `PACER_MODE` (environment, or `<prefix>/.sevo/lullaby-pacer.conf`, KEY=VALUE): `off` (default), `probe`.
  `PACER_LOG=<path>` sends the lines to a file (default: the game's log).
- `probe`: counts which present calls the game's Metal path makes and logs a summary every 5 s (class, selector, calls, the thread,
  the argument range of the `atTime:`/`afterMinimumDuration:` forms). Changes nothing.
- The modes that time a frame's presentation (`adaptive`, `fixed`) are added only after the probe has said which path to take, and
  only if they hold on the measurements in `tools/perf/` (docs/DECISIONS.md, S8). Priority: stability and wide compatibility; a
  game the pacer cannot handle is left alone.
- Build: `make pacer` (arm64 + x86_64). Measure: `tools/perf/presentfeed.py` (on-screen intervals) with `LULLABY_PRESENT_FEED=1`.
