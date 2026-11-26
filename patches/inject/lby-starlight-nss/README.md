# lby-starlight-nss (T9–T11, test build)

Upscaling and frame generation over the MetalFX that D3DMetal makes out of a game's DLSS. `lullaby-nss.dylib` is
loaded into the Wine loader's process (`DYLD_INSERT_LIBRARIES`, like `lby-ponthree-pacer`), catches
`-[<MetalFX temporal scaler> encodeToCommandBuffer:]`, and either runs NSS itself or lets the upscaler inside it (MetalFX,
or FSR 4's hook) run into a texture of its own. Nothing happens without the launch options below; MetalFX stays the fallback.

| Launch option | Effect |
|---|---|
| `LULLABY_UPSCALER=nss` | Arm's NSS (MaximKotliar/nss-metal) instead of MetalFX; `LULLABY_NSS_QUALITY=fast\|low\|mid\|high`. Hidden: for measuring only, not in `docs/LAUNCH_OPTIONS.md`, its weights not shipped to players |
| `LULLABY_UPSCALER=fsr4` | AMD FSR 4.1.2 (UzenUPoZiTiV4ik/fsr4-native-macos) instead of MetalFX; `LULLABY_FSR4_PROFILE` (`int8-lite`, `int8-lite-lossy`), `LULLABY_FSR4_SHARPNESS` (RCAS, 0.3) |
| `LULLABY_FG=anr` or `anr3x` | ANR FG-V.B20 on Metal (same project) instead of MetalFX frame generation; DLSS FG on in the game |
| `LULLABY_CAS=0.3` | CAS sharpening after NSS or MetalFX (HDR-safe) |

The run script (`steam/hook/feats/compat_run.sh`) finds the components in `~/Library/Application Support/lullaby/components/`
(`nss/`: `lullaby-nss.dylib`, `nss.metallib`, weights; `fsr4/`: the fsr4-native-macos tree with its hook, model and
shader caches, `build/anr_runtime_v20` from Apex's addon).

Texture LOD bias: the library counts the `lodBias` the game gives its samplers (in the log), and `LULLABY_LOD_BIAS=<-2..0>`
adds that much to every mipmapped, filtered, non-comparison sampler (not shadows); the device reads it when it builds the
sampler. The usual value under upscaling is log2(render/output), RE9 about -0.58.

The library keeps its wrapper the outermost one on MetalFX's temporal scaler: FSR 4's hook swizzles after it, and a few
seconds later ours goes back on top, so dumps and the shadow see FSR 4's frames. With FSR 4 and nothing to measure, the
wrapper only passes the call on.

`components/nss/live.conf` is read again whenever it changes, about once a second, so a setting can be compared in a running
game: `upscaler`, `quality`, `cas`, `trust`, `still`, `flat`, `tune`, `shadow=1` (the other upscaler on the same inputs into a
texture of ours), `dump=N` (N frames of the shown output, the shadow and the game's colour, motion and depth into
`components/nss/dumps/`), `stage` (write through our texture, default on).

## Measured (RE9, M4 Pro, 1530x860 -> 2294x1290; agent/reports/2026-11-25-fsr4-anr-nss.md)

GPU per frame: MetalFX 0.86 ms, NSS mid 2.21, FSR 4 Lite 3.62, FSR 4 Lite Lossy 2.78. On the same frames, FSR 4 Lite with
RCAS 0.3 is sharper than NSS and calmer in motion in every series; NSS (with the patch below) has the least ghosting.

## Patches to other projects (applied by `build.sh` to a copy; the checkouts stay clean)

- `nss-metal/0001-guards-and-temporal-tuning.patch` (on the commit in `nss-metal/BASE`): NaN/Inf guards (a NaN once in
  history kept the frame black), exposure clamp, and the temporal step's tuning: history bypasses the clamp freely only
  below 4 px of motion, above it where it agrees with this frame; in still areas old raindrops on flat ground are dropped.
- `fsr4/0001-logical-render-to-output-scale.patch` (on the v4.1 release): the render-to-output mapping from logical sizes;
  with the 8-aligned one an output like 2294x1290 came out stretched by 0.46%.
- `fsr4/0002-prepared-shaders-no-toolchain.patch`: `FSR4_PREPARED=1` skips every preparation step (python3, `xcrun metal`):
  the shaders and model data come compiled with Lullaby, and macOS turns them into GPU code like any game's shaders.
  On a recorded case the output is bit-identical to the port's own preparation.
- `fsr4/0003-anr-ignore-distortion-field.patch`: `FSR4_ANR_IGNORE_DISTORTION=1` lets ANR generate frames when the game
  sends DLSS-G's distortion field (RE9 always does; without it ANR quietly left the frames to MetalFX).
- `fsr4/0004-anr-output-offset.patch`: a picture inside a larger texture (D3DMetal's letterbox: RE9's 3024x1701 at y 98 of
  3024x1898, `outputOffset`) is handed to ANR in textures of its own size and put back at the offset.
- `fsr4/0005-anr-3x-at-output-offset.patch`: the 3x frame is presented at the same offset.
- `fsr4/0006-anr-at-the-games-size.patch`: `FSR4_ANR_SCALE=auto` generates frames at the size the game draws (its MetalFX
  scaler's output, RE9 2294x1290) instead of the stretched window size, and stretches the result: 3.66 ms instead of
  6.32 ms per real frame on M4 Pro (stand, 2x), colours exact. A number 0.5..1 scales by it.
- `fsr4/0007-anr-depth-dilated-motion.patch`: `FSR4_ANR_DILATE=1` takes motion from the nearest of the 3x3 render pixels.
  Measured on recorded RE9 frames (tests/anr_eval.mm + agent tools/anr-eval-metric.py): edge error -3 % in an orbit
  around the heroine, +1 % in a room transition. On by default in Lullaby (owner, RE9 2026-11-26: the halo around the
  heroine is weaker with it); `LULLABY_ANR_DILATE=0` turns it off.
- `fsr4/0008-anr-3x-diagnostics.patch`: the first 3x extra frames and the present events in the hook log, with the
  extra frame's middle-row mean (an empty frame tells from one lost on the way).
- `fsr4/0009-anr-3x-game-drawable-only.patch`: only presents of the game's drawable (the frame-generation output's
  size) move ANR's 3x sequence on; the first 40 presents are logged.
- `fsr4/0010-anr-3x-pair-lag.patch`: D3DMetal encodes frame generation for its next frame before it presents this
  frame's pair, so the newest t=2/3 frame belonged to a later pair (in RE9: constant back-and-forth jumps).
  `FSR4_ANR_3X_LAG=1` (Lullaby's default) hands an extra frame out when one newer waits behind it; the file
  `dist/crossover/anr3x.conf` (`lag=N`) changes it in a running game. With it 3x plays in order in RE9.
- `fsr4/0011-anr-reuse-network-across-interpolators.patch`: a game makes a new frame interpolator at scene changes and
  ANR built its network again (45-60 ms, a hitch); a released or idle owner's network is taken over instead
  (stand: 60 -> 12.9 ms for the new interpolator's first frame, picture exact).

- `fsr4/0012-anr-frame-dump.patch`: `dump=N` in `dist/crossover/anr-dump.conf` records N generated frames and the game's
  frames they came from (ANR's size) into `$FSR4_ROOT/dumps/anr-<time>/`; for looking at artefacts in a running game.
- `fsr4/0013-anr-depth-direction-from-upscaler.patch`: `FSR4_ANR_DEPTH=auto` takes the depth direction from the game's
  temporal scaler (a wrong direction costs +46 % edge error on RE9 frames); logs what the interpolator said. In RE9 the
  interpolator was right already (1), so it changes nothing there; kept as a guard for other games.
- `fsr4/0014-anr-present-pacing-stats.patch`: every 600 presents in 3x the hook log gets the interval mean, p95, max,
  bunched (<2 ms) and gap (>2x mean) shares.
- `fsr4/0015-anr-3x-pairs-by-time.patch`: `FSR4_ANR_3X_ORDER=time` (Lullaby's default) tells D3DMetal's pair apart by
  time (the real frame follows the interpolated one within 2 ms), hands the pair its own extra frame (the oldest
  waiting; surplus dropped, so the sequence recovers by itself) and ignores nested presents. The count-based order with
  a fixed lag (0010) broke whenever D3DMetal's pipelining varied: the heroine from another moment, "a white copy".
  `order=count|time` in `anr3x.conf` switches in a running game. The port's live tests (Metal 3/4, SDR/HDR) pass both ways.

- `fsr4/0016-anr-cpu-timing.patch`: ANR's CPU time per frame in the hook log (stand: about 0.4 ms).
- `fsr4/0017-anr-render-size-option.patch`: `FSR4_ANR_SCALE=render` generates at the game's render size (RE9 1530x860):
  2x 2.35 / 3x 2.86 ms instead of 3.85 / 5.32, generated frames softer (edge error +9 % orbit, +19 % room transition). An
  option; `auto` (the game's output size) stays Lullaby's default.
- `fsr4/0018-anr-motion-preparation-ways.patch`: `FSR4_ANR_DILATE=0..4` (nearest, 3x3 nearest-to-camera, bilinear motion,
  3x3 for motion only, 5x5). On three recorded series all within +-3 %; 1 stays the default.
- `fsr4/0019-anr-3x-exact-time-and-background-kernel.patch`: `pace=time` in `anr3x.conf` (or `FSR4_ANR_3X_PACE=time`)
  shows the interpolated frame now, the extra one a step later and the real one two steps later, by time instead of
  minimum durations; and the resample kernel compiles off the game's thread (first frame with frame generation 10.9 ms
  instead of about 40 on the stand; MetalFX shows the frames until it is ready).

- `fsr4/0020-anr-3x-no-self-pacing-freeze-counter.patch`: the 3x step (frame time / 3) is kept below one vsync of a
  120 Hz screen, since the frame time includes the waits the step makes (RE9 was held at 13 fps after a hitch, 31 x 3 =
  94 at best); the real frame waits a step only when its pair had an extra frame; the extra drawable is waited for at
  most 25 ms (nextDrawable's own wait of a second was the 1003 ms freezes); `freeze #N` lines name each freeze's cause
  (drawable wait, ANR encode, network build, the game sent no frame, outside ANR); `on screen:` lines count frames that
  really reached the screen.

- `fsr4/0021-anr-2x-present-duration-cap.patch`: ANR 2x keeps D3DMetal's present durations below one 120 Hz vsync
  (`cap=on|off` in `anr3x.conf`, live); freeze and on-screen counters in 2x too.
- `fsr4/0022-metalfx-fg-counters-and-duration-cap.patch`: the counters for MetalFX frame generation, and the same
  duration cap as an option (`mfxcap=on`). Tried in RE9: MetalFX's own durations are short, no change; off.
- `fsr4/0023-metalfx-fg-at-the-games-size.patch`: `FSR4_MFX_SIZE=game`: the window's picture is taken down to the
  game's upscaled size, a second MetalFX interpolator of that size (made off the game's thread from a copy of the
  game's descriptor) makes the frame, and it is stretched back at the picture's offset. Stand 4.70 -> 3.36 ms; RE9 at
  the rain spot 46 -> 50.5 game fps (92 -> ~101 shown). `FSR4_MFX_DILATE=1`: depth-dilated motion (no gain measured).
- `fsr4/0024-metalfx-fg-live-switches.patch`: `mfxsize=game|window`, `mfxdilate=on|off` in `anr3x.conf`, read live.
- `fsr4/0025-metalfx-fg-edge-fill-tear-fix-distortion-switch.patch`: a pass after MetalFX (`FSR4_MFX_EDGE=1`,
  `mfxedge=on|off`): where the point was outside the last frame (the camera turned), the new frame carried back half
  its motion fills the generated one; where MetalFX is far from both frames carried to the middle while they agree,
  their mean replaces it (`FSR4_MFX_FIX=0` turns that part off). `mfxdistortion=on|off` / `FSR4_MFX_DISTORTION=0`
  leaves out the game's distortion field; its shape is logged once. On 40 recorded RE9 frames
  (`tests/mfx_eval.mm`, `agent/tools/mfx-eval-metric.py`) against the window-size MetalFX: whole -3 %, depth edges
  -4 %, screen edge band -14 %, worst 1 % of pixels -8 %, 3.61 ms instead of 4.70.

- `fsr4/0026-present-hook-counts-a-drawable-once.patch`: a drawable reached the present hook twice (present and
  presentAfterMinimumDuration:), so the pacing and on-screen counters counted it twice (RE9: "200 shown/s" on a 120 Hz
  screen, "bunched 50 %") and the 3x pair logic could run twice; only its first visit counts now.

- `fsr4/0027-metalfx-fg-reveal-snap.patch`: in the same pass, where a moving character reveals what was behind it and
  MetalFX is far from both frames carried to the middle (its blocks), the nearer of them (`FSR4_MFX_SNAP`, 0.25,
  0 = off). RE9 frames: depth edges 14.45 -> 14.29, worst 1 % 201 -> 198. The arc beside fast hair remains.

- `fsr4/0028-metalfx-fg-pass-leaves-the-interface.patch`: the pass after MetalFX leaves the game's interface (its
  texture, and a pixel around it) as MetalFX made it: the pass moved HUD pixels with the scene's motion and the HUD
  flickered in RE9. In the game the owner saw no gain from the pass and beige pixel noise beside the heroine, so
  Lullaby leaves it off (`LULLABY_MFX_EDGE=1` turns it on); the game's size (0023) stays on.

- `fsr4/0029-fsr4-rain-glow-pass.patch`: rain falling on the same lines (RE9: a point lights for one frame in five,
  0.2 -> 9..40) is averaged by FSR 4 into steady glowing lines (5..10) that grow while the camera stands still. After
  FSR 4, per render pixel, its usual level and how often it flashes; where it flashes often the output is kept no
  brighter than the game's current frame (softened 3x3): darkening only, 0.9 % of pixels on the recorded rain. Off by
  default; `FSR4_RAIN=1` or `rain=on` in `dist/crossover/fsr4-live.conf` (live) for the owner's HDR check.

- `fsr4/0030-anr-detail-from-the-real-frame.patch`: ANR made smaller than the picture is stretched back with the
  game's current frame's fine detail (its picture minus that picture at ANR's size) from where the point is in the
  current frame, weighted by how well the two agree there, never on the interface (`FSR4_ANR_DETAIL=<0..1>`,
  `anrdetail=` in `anr3x.conf`, live). 40 RE9 frames: ANR's frames were softer than MetalFX's (sharpness 0.44 vs 0.59);
  at 0.68 with 0.5 detail 0.50, with 1.0 0.62; error unchanged or lower (+0.13 ms). Render size with 0.75: 2.3 ms
  instead of 3.3 (MetalFX's cost), depth edges +5 % against MetalFX. Lullaby: 0.68 with 0.5.

- `fsr4/0031-cpu-runtime-path-once-status-files-off-thread.patch`: ANR looked up its runtime's directory every frame
  (two file checks and its manifest parsed as JSON on the game's thread): 78 % of ANR's CPU time per frame on the stand,
  0.30-0.44 -> 0.054 ms (RE9 under Rosetta: 0.87 -> 0.19 ms). The status files of ANR and FSR 4 (twice a second) are
  written off the game's thread, each from copies of its path and text.

- `fsr4/0032-fsr4-rain-pass-lone-strong-still-flashes.patch`: the rain pass of 0029 also darkened thin bars and
  outlines flickering with the jitter and passers-by (a balcony's railings rippled in RE9). A drop is now a lone flash
  (never two frames running), on a still point, at least 8x brighter than the point usually is (`FSR4_RAIN_RATIO`);
  the 3x3 work moved to the render size and the output is read through a view of itself (no copy). Recorded RE9
  frames: rain glow -24 % (0029: -32 %), outline pixels touched 0.70 % (0029: 1.57 %). In RE9 the owner saw no
  ripple at a balcony and a shorter trail where drops fall on the same spot.

- `fsr4/0033-fsr4-rain-pass-live-strength.patch`: `raingain=` (8) and `rainratio=` (8) in `fsr4-live.conf`, live. Owner's
  calibration in RE9: more strength (12, 16) left the trail as it was and added ripple; threshold x5 shortened the trail
  but rippled; wet still wood rippled at x5, x6.5, x8 and x12 (its highlights and splashes flash like drops). The pass
  is off by default (`LULLABY_RAIN=1` turns it on).

- `fsr4/0034-frame-generation-live-switches-file.patch`: the live frame-generation switches (MetalFX's `mfx*`, ANR's
  `anrdetail` and `cap`, 3x's `lag`, `order`, `pace`) are read from `dist/crossover/fg-live.conf`; the file was named
  `anr3x.conf` from when it held only ANR 3x's lag.

The hook file Lullaby installs is fat: the x86_64 hook plus an empty arm64 half, so arm64 processes the Wine loader
starts (wineserver), which inherit DYLD_INSERT_LIBRARIES, are not stopped by dyld (`fsr4/prepare-set.sh` builds it so).

Measured and left out (RE9 frames, RCAS 0.3): pixfix (owner: much worse), Lite Lossy (-15 % detail walking and in rain,
more shimmer in an orbit; new-look a little better, still below Lite), RCAS costs 0.18 ms of FSR 4's 3.76.

## Build

`patches/inject/lby-starlight-nss/build.sh <nss-metal checkout> out/nss` builds `lullaby-nss.dylib` (arm64 + x86_64), the
kernels and the replay bench `nss_replay`. FSR 4: its own `make tools/bin/fsr4mac dist/crossover/libfsr4hook.dylib` on a
copy with `fsr4/*.patch` applied, then `fsr4/prepare-set.sh` makes the component players get. It and the prepared ANR
runtime are published in Lullaby's `components-1` release (`release/components.json`); the app downloads them when the
player turns FSR 4 or ANR on (`app/Sources/LullabySettings/ComponentStore.swift`, a progress line under the row).

ANR stands (built against the patched port tree, arm64): `tests/anr_offset_test.mm` (pixels at an output offset, 2x and 3x,
scaled or not; `ANR_TEST_BENCH=N` times it), `tests/anr_eval.mm` (ANR on recorded game frames, for a metric).
Tests without a game: `tests/nss_hook_test.m` (a real Metal 4 MetalFX scaler made like D3DMetal's; run it directly, not
through `arch`, which drops `DYLD_INSERT_LIBRARIES`), `tests/nss_replay.m` (a dump replayed through NSS with any tuning).

## Licences

`nss.m` started from Lightscale's `hook/unix/lsfg_nss_hook.m` (MIT). NSSMetal: Apache-2.0; NSS weights: Arm AI Model
Community License (notices, a note of the conversion and the acceptable-use terms before a release ships them).
fsr4-native-macos: MIT; FSR 4.1.2 initializers from AMD FidelityFX SDK 2.3.0 (MIT); Lite Lossy weights GPL-trained data,
fetched by the player. ANR weights: Apex's addon, never shipped by Lullaby.
