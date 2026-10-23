# lby-pinkiepie-windowstate

Remembers the state a game's window was left in and puts it back at the next launch, without touching Dormison.

- States: **Window** (and its size), **Native Fullscreen**, **Window (full screen)** (borderless, covering the screen).
- Injected into the Wine loader's process (`DYLD_INSERT_LIBRARIES`, set by `compat_run.sh`); uses only AppKit's public
  `NSWindow` API and notifications. The state is kept in `<prefix>/.sevo/lullaby-window.json`, never in the game's files.
- A state counts once it has stood for a second, so a game leaving full screen only because it is closing is not kept.
- Window size is restored; Native Fullscreen is re-entered; the game's own borderless mode is the game's to put back.
- Off for one run: launch option `LULLABY_WINDOW_STATE=0`.
- Tests: `make windowstate-tests` (decisions in plain C; the library in a process with a `WineWindow`, arm64 and x86_64).
