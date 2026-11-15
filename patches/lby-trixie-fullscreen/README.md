# lby-trixie-fullscreen

Native full screen of a game in macOS (winemac.so, the engine series `patches/engine/patches/winemac.so/`; the links here are named like the patches).

- ENG-12 and ENG-15, one patch `0006-winemac-native-fullscreen.patch`: a program in native full screen is told the size it has (the screen under the notch), not the size it drew at (ENG-12); a window smaller than the screen (1920x1200 on a 3024x1964 screen) keeps its size and is scaled up by the engine's stage to the whole screen, also when the game makes its window smaller while in full screen (a resolution chosen in its settings) (ENG-15). A window that covers the screen goes to full screen by itself (with `lby-pinkiepie-windowstate`).

- ENG-17 `0008-winemac-keep-the-display-mode.patch`: a game's request for a display mode (Modern Warfare Remastered asks for 3024x1964 at 47 Hz) is answered "done" without switching the Mac's display; before, the whole screen went to a low-resolution mode and the desktop shrank into a corner. `LULLABY_KEEP_DISPLAY_MODE=0` gives the old behaviour.

Both parts above are on by default; `LULLABY_NATIVE_FULLSCREEN=0` turns the full screen off for a run, `LULLABY_FULLSCREEN_SCALE=0` or `LULLABY_FULLSCREEN_SIZE=0` give the old behaviour. The patches stay in the series (the bridge build reads them there, in order of their numbers).
