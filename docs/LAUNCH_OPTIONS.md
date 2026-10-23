# Launch options for one run

Steam: game Properties > General > Launch options, `VARIABLE=value %command%`. They last for that run only;
remove the line and the default is back. Everything below is on for every game and has no row in the properties.

| Variable | Turns off | Notes |
|---|---|---|
| `WINEMSYNC=0` | msync+ (Dormison's thread sync) | falls back to the slower server-based sync |
| `LULLABY_DLSS=0` | DLSS through MetalFX (DXMT's and D3DMetal's switches) | the card the game sees stays NVIDIA under the chip's name |
| `LULLABY_AVX=0` | AVX advertised to the game (Rosetta) | for a game that runs slower or crashes with AVX |
| `LULLABY_GCMOUSE_SCALE=0.2` | the automatic mouse speed of GCMouse | a number from 0.01 to 100 instead of 0.3 (about 1600 DPI); lower is slower. Use it when a mouse is too fast or too slow, for example after changing its DPI with the button |

Why they are written into `<prefix>/.sevo/bottle.env` by the run script: the engine applies that file over the process
environment, so a plain environment variable would lose. `lullaby-settings` writes the file again at the next launch.
Tests: `steam/hook/tests/overridecheck.sh`.
