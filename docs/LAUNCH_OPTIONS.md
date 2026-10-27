# Launch options for one run

Steam: game Properties > General > Launch options, `VARIABLE=value %command%`. They last for that run only;
remove the line and the default is back. Everything below is on for every game and has no row in the properties.

| Variable | Turns off | Notes |
|---|---|---|
| `WINEMSYNC=0` | msync+ (Dormison's thread sync) | falls back to the slower server-based sync |
| `LULLABY_DLSS=0` | DLSS through MetalFX (DXMT's and D3DMetal's switches) | the card the game sees stays NVIDIA under the chip's name |
| `LULLABY_LOW_LATENCY=0` | Lullaby's own NVIDIA Reflex answer for a D3DMetal game | to compare, or for a game that misbehaves with it; D3DMetal's own stubs answer instead |
| `LULLABY_AUDIO_FOLLOW=0` | the game's sound following the Mac's default output device | for a game that misbehaves when the device changes; the stream then stays on the device it opened |
| `LULLABY_NATIVE_FULLSCREEN=0` | the automatic move of a screen-covering game to macOS's native full screen | the same as the row "Native full screen" in the game's properties, for one run |
| `LULLABY_FULLSCREEN_SIZE=0` | telling the game the size it has in native full screen | the picture is then scaled into the window (a black strip at the side); to compare |
| `LULLABY_AVX=0` | AVX advertised to the game (Rosetta) | for a game that runs slower or crashes with AVX |
| `LULLABY_GCMOUSE_SCALE=0.2` | the automatic mouse speed of GCMouse | a number from 0.01 to 100 instead of 0.3 (about 1600 DPI); lower is slower. Use it when a mouse is too fast or too slow, for example after changing its DPI with the button |

Why they are written into `<prefix>/.sevo/bottle.env` by the run script: the engine applies that file over the process
environment, so a plain environment variable would lose. `lullaby-settings` writes the file again at the next launch.
Tests: `steam/hook/tests/overridecheck.sh`.

## Renderer and Vulkan driver (the list in Properties > Compatibility; these variables do the same for one run)
| Variable | Value | Meaning |
|---|---|---|
| `LULLABY_RENDERER=` | `auto` or nothing | Lullaby names the game's API and picks the renderer (the base choice; only here the automatic choice works) |
| | `d3dmetal`, `dxmt`, `mtld3d`, `winemetalgl` | DX12, DX11, DX9, OpenGL as named; used as it is |
| | `moltenvk` | Vulkan games on the engine's MoltenVK, no Direct3D layer |
| | `dxvk`, `wined3d` | no longer in the list; still read from an old setting or launch option |
| `LULLABY_VULKAN=kosmickrisp` | | Vulkan games on Lullaby's own KosmicKrisp build instead of MoltenVK (experimental, see BACKLOG) |

