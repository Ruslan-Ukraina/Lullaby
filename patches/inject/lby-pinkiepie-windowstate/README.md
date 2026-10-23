# lby-pinkiepie-windowstate

Remembers the state a game's window was left in and puts it back at the next launch, without touching Dormison.

- States: **Window** (and its size), **Native Fullscreen**, **Window (full screen)** (borderless, covering the screen).
- Injected into the Wine loader's process (`DYLD_INSERT_LIBRARIES`, set by `compat_run.sh`); uses only AppKit's public
  `NSWindow` API and notifications. The state is kept in `<prefix>/.sevo/lullaby-window.json`, never in the game's files.
- A state counts once it has stood for a second, so a game leaving full screen only because it is closing is not kept.
- Window size is restored; Native Fullscreen is re-entered; the game's own borderless mode is the game's to put back.
- **Native full screen switch** (the game's setting "Native full screen", `LULLABY_NATIVE_FULLSCREEN`, on by default): a game whose
  window covers the screen is shown by the engine in a window (`SEVO_RESIZABLE_WINDOWS=window`, always set); with the switch on
  this library takes that window to macOS's native full screen once, on its own desktop, at the game's resolution. With it off the
  window stays a window (the green button still works). For such a window the switch decides, not the saved state.
  The engine's `presentationWindowed` is read through key-value coding; an engine without it only loses this.
- Off for one run: launch option `LULLABY_WINDOW_STATE=0` (this switch too).
- Tests: `make windowstate-tests` (decisions in plain C; the library in a process with a `WineWindow`, arm64 and x86_64).
