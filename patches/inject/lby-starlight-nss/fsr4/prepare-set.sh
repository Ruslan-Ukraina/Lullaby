#!/bin/sh
# Prepares FSR 4's shaders and model data once, on a Mac with Xcode, for players who have neither Xcode nor python3
# (they run it with FSR4_PREPARED=1, patch 0002). The port compiles one variant per combination of a game's inputs; this
# makes every variant a game through D3DMetal's MetalFX can ask for, with tiny synthetic frames, and keeps only what the
# runtime loads: the hook, the compiled variants (.metallib, bindings, tables), the model data, and the neural network's
# Metal sources that macOS itself compiles at the first run (no toolchain needed). About 13 MB with both profiles.
#   patches/inject/lby-starlight-nss/fsr4/prepare-set.sh <fsr4 tree, patched and built, fsr412_model imported> <out component dir>
# Checked 2026-11-25: the out dir alone, with FSR4_PREPARED=1 and no PATH, gives output bit-identical to the tree.
# Variants: output tier 1080 / 2160, depth reversed or not, auto exposure or not, motion at render or output size,
# profiles int8-lite and int8-lite-lossy (the latter only if its weights are there).
set -eu
tree=$(cd "${1:?fsr4 tree}" && pwd); comp=${2:?out component dir}
mkdir -p "$comp/build"; comp=$(cd "$comp" && pwd); out="$comp/build"
[ -x "$tree/tools/bin/fsr4mac" ] || { echo "no $tree/tools/bin/fsr4mac (make tools/bin/fsr4mac)" >&2; exit 1; }
[ -f "$tree/dist/crossover/libfsr4hook.dylib" ] || { echo "no hook (make dist/crossover/libfsr4hook.dylib)" >&2; exit 1; }
[ -d "$tree/build/fsr412_model" ] || { echo "no $tree/build/fsr412_model (import the model first)" >&2; exit 1; }
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
# what the runtime reads besides the variants
for d in fsr412_model fsr412_lossy; do [ -d "$tree/build/$d" ] && cp -R "$tree/build/$d" "$out/"; done
profiles=int8-lite; [ -d "$tree/build/fsr412_lossy" ] && profiles="int8-lite int8-lite-lossy"
for tier in 1080 2160; do
  if [ $tier = 1080 ]; then rw=1280 rh=720 uw=1920 uh=1080; else rw=1707 rh=960 uw=2560 uh=1440; fi
  for di in 0 1; do for ae in 0 1; do for lm in 1 0; do
    c="$work/c-$tier-$di-$ae-$lm"
    python3 -I - "$c" $rw $rh $uw $uh $di $ae $lm <<'PY'
import sys, json, pathlib
import numpy as np
c = pathlib.Path(sys.argv[1]); c.mkdir(parents=True); rw, rh, uw, uh, di, ae, lm = map(int, sys.argv[2:])
mw, mh = (rw, rh) if lm else (uw, uh)
for i in range(2):
    np.full((rh, rw, 4), 0.5, np.float16).tofile(c / f"f{i:02d}_color.bin")
    np.full((rh, rw), 0.5, np.float32).tofile(c / f"f{i:02d}_depth.bin")
    np.zeros((mh, mw, 2), np.float16).tofile(c / f"f{i:02d}_mv.bin")
meta = {"preset": "quality", "render_width": rw, "render_height": rh, "upscale_width": uw, "upscale_height": uh,
        "frames": 2, "depth_inverted": bool(di), "low_res_mv": bool(lm), "jittered_mv": False, "colorspace": "linear",
        "auto_exposure": bool(ae), "pre_exposure": 1.0, "rcas": True, "sharpness": 0.3,
        "frame": [{"jitter": [0.25, -0.25], "mv_scale": [mw, mh], "reset": i == 0, "frame_time_ms": 16.6,
                   "camera_near": 0.1, "camera_far": 1000.0, "fovy": 1.0} for i in range(2)]}
(c / "meta.json").write_text(json.dumps(meta))
PY
    for prof in $profiles; do
      (cd "$tree" && ./tools/bin/fsr4mac --fsr-version 4.1.2 "$c" "$c-out-$prof" --profile "$prof" --root "$tree" \
         --builddir "$out" > "$c-$prof.log" 2>&1) || { echo "failed: tier $tier di $di ae $ae lm $lm $prof" >&2; tail -5 "$c-$prof.log" >&2; exit 1; }
      echo "prepared: tier $tier, depth reversed $di, auto exposure $ae, render-size motion $lm, $prof"
    done
  done; done; done
done
mkdir -p "$comp/dist/crossover" "$comp/src/fsr41x" "$comp/src/fsr402"
# The hook serves the x86_64 Wine loader; an empty arm64 half lets the arm64 processes it starts (wineserver), which
# inherit DYLD_INSERT_LIBRARIES, load the file instead of being stopped by dyld (seen 2026-11-25: RE9 did not start).
printf '' > "$work/stub.c"
clang -arch arm64 -dynamiclib -mmacosx-version-min=26.0 -install_name @loader_path/libfsr4hook.dylib -o "$work/stub.dylib" "$work/stub.c"
lipo -create "$tree/dist/crossover/libfsr4hook.dylib" "$work/stub.dylib" -output "$comp/dist/crossover/libfsr4hook.dylib"
codesign -fs - "$comp/dist/crossover/libfsr4hook.dylib" 2>/dev/null
cp -R "$tree/src/fsr41x/shaders" "$comp/src/fsr41x/"; cp "$tree/src/fsr41x/fsr411_model.h" "$comp/src/fsr41x/"
cp "$tree/src/fsr402/i8mpp.metal" "$comp/src/fsr402/"
# ANR's helper kernels (our patches 0007: motion dilation): built from the port's MIT source. ANR's weights and runtime
# graph (Apex's addon) are never shipped: the player's own copy goes to build/anr_runtime_v20.
[ -f "$tree/build/anr_helpers_ui_v2.metallib" ] && cp "$tree/build/anr_helpers_ui_v2.metallib" "$out/"
find "$out" \( -name '*.metal' -o -name '*.air' -o -name '*.log' \) -type f -delete
echo "component in $comp: $(du -sh "$comp" | cut -f1), $(ls -d "$out"/fsr412_2160_* "$out"/fsr412_1080_* 2>/dev/null | wc -l | tr -d ' ') variants"
