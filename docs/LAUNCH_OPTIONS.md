# Launch options for one run

Steam: game Properties > General > Launch options, `VARIABLE=value %command%`. They last for that run only;
remove the line and the default is back. Everything below is on for every game and has no row in the properties.

| Variable | Turns off | Notes |
|---|---|---|
| `WINEMSYNC=0` | msync+ (Dormison's thread sync) | falls back to the slower server-based sync |
| `LULLABY_DLSS=0` | DLSS through MetalFX (DXMT's and D3DMetal's switches) | the card the game sees stays NVIDIA under the chip's name |
| `LULLABY_LOW_LATENCY=0` | Lullaby's own NVIDIA Reflex answer for a D3DMetal game | to compare, or for a game that misbehaves with it; D3DMetal's own stubs answer instead |
| `LULLABY_AUDIO_FOLLOW=0` | the game's sound and microphone following the Mac's default output and input device (microphone: next bridge) | for a game that misbehaves when the device changes; the stream then stays on the device it opened |
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


## Upscaling and frame generation (test build; patches/inject/lby-starlight-nss/README.md has every option and switch)
For a game with DLSS that D3DMetal runs: DLSS on in the game (and DLSS Frame Generation for frame generation). The
components must be installed (`components/fsr4`, and `components/nss` for the LOD bias); without them these variables
change nothing.

| Variable | Value | Meaning |
|---|---|---|
| `LULLABY_UPSCALER=` | `fsr4` | AMD FSR 4 Lite in place of MetalFX's upscaler; MetalFX's frame generation then runs at the game's size |
| `LULLABY_FG=` | `anr` | ANR 2x in place of MetalFX's frame generation (`anr2`, `anr2x` mean the same) |
| `LULLABY_FSR4_SHARPNESS=` | `0.3` | RCAS after FSR 4; `0` turns it off |
| `LULLABY_FSR4_PROFILE=` | `int8-lite-lossy` | a cheaper FSR 4 (network every other frame, less detail) |
| `LULLABY_LOD_BIAS=` | `-0.3` | textures a little sharper with our upscaler; `0` turns it off, `-0.58` is RE9's full value |
| `LULLABY_ANR_SCALE=` | `0.68` | the size ANR generates at, a fraction of the picture; `auto` is the game's size, `render` its render size |
| `LULLABY_ANR_DETAIL=` | `0.5` | the real frame's fine detail added to ANR's frames, 0..1 |
| `LULLABY_MFX_SIZE=window` | | MetalFX's frame generation at the window's size, as D3DMetal makes it |
| `LULLABY_RAIN=1` | | keeps FSR 4 from turning drops that fall on the same spot into glowing lines (may ripple wet surfaces) |
| `LULLABY_CAS=` | `0.3` | CAS sharpening after MetalFX's upscaler |
| `LULLABY_REFLEX_AGGRESSIVE=0` | | the tighter Reflex margin Lullaby uses with frame generation, off |
| `LULLABY_STREAM=1` | | every frame the game shows goes to a Syphon server for OBS ("Syphon Client"), without screen capture |

## Presentation (test build, lby-ponthree-pacer)
| Variable | Meaning |
|---|---|
| `LULLABY_THREAD_QOS=1` | every thread of the game starts at the user-interactive quality of service (no gain measured in RE9) |
| `LULLABY_DRAWABLES=2` | the game's layer keeps two drawables instead of three (a shorter queue, to compare) |
