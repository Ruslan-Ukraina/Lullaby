# lby-pinkiepie-windowstate

Remembers the state a game's window was left in and puts it back at the next launch, without touching Dormison.

- States: **Window** (and its size), **Native Fullscreen**, **Window (full screen)** (borderless, covering the screen).
- Injected into the Wine loader's process (`DYLD_INSERT_LIBRARIES`, set by `compat_run.sh`); uses only AppKit's public
  `NSWindow` API and notifications. The state is kept in `<prefix>/.sevo/lullaby-window.json`, never in the game's files.
- A state counts once it has stood for a second, so a game leaving full screen only because it is closing is not kept.
- Window size is restored; Native Fullscreen is re-entered; the game's own borderless mode is the game's to put back.
- **Borderless covering window** (the usual "Window (full screen)" of a game; no setting, always on, `LULLABY_NATIVE_FULLSCREEN=0` as a launch option
  turns it off for one run): the window the game made, no title bar and as big as the screen, is taken to native full screen as it is;
  this library gives it AppKit's full-screen-primary behaviour first. macOS puts it below the menu bar and notch (1512x949 points on a
  14" MacBook Pro, 3024x1898 pixels); the engine tells the game that size ([ENG-12](../../engine/patches/winemac.so/0006-winemac-native-fullscreen-reports-its-size.patch), `LULLABY_FULLSCREEN_SIZE=0` keeps the scaled picture).
  Not turned into a titled window, so the window is never 32 points taller than the screen. Checked again 1.5 and 4 seconds after each
  change of the window (a game centres its window a moment after sizing it and says nothing).
- **Native full screen switch** (`LULLABY_NATIVE_FULLSCREEN`, on by default): a game whose
  window covers the screen is shown by the engine in a window (`SEVO_RESIZABLE_WINDOWS=window`; not the default: it turned a borderless full screen into a titled window, docs/DECISIONS.md); with the switch on
  this library takes that window to macOS's native full screen once, on its own desktop, at the game's resolution. With it off the
  window stays a window (the green button still works). For such a window the switch decides, not the saved state.
  The engine's `presentationWindowed` is read through key-value coding; an engine without it only loses this.
- **When it asks**: a game opens a launcher window first; native full screen is asked for the screen-covering window once it has stood
  still for 2 seconds, again (up to three times, 4 seconds apart) only during the first 30 seconds, when the engine takes it out
  of full screen while the game rearranges. The state file also keeps `covering`: a saved native full screen of a screen-covering
  window is not put on a launcher window.
- **Layout put back**: after a change of a screen-covering window the engine's own `layoutPresentation` is asked for again. Without it the
  content view stands at x = 0 instead of the centred box's x after the full-screen animation (picture at the left, empty strip at the
  right, pointer off by the same amount); found with the layer dump below.
- Diagnosis: `LULLABY_LAYER_DUMP=1` (or a file `layer-dump` beside the state file) prints the window's layer tree to the log.
- Off for one run: launch option `LULLABY_WINDOW_STATE=0` (this switch too).
- Tests: `make windowstate-tests` (decisions in plain C; the library in a process with a `WineWindow`, arm64 and x86_64).
