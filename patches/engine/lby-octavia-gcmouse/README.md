# lby-octavia-gcmouse

Raw mouse movement through Apple's GameController (up to ~500 reports a second instead of the engine's ~120), for the winemac driver of Dormison. The patch itself is in the series, `patches/engine/patches/winemac.so/0004-winemac-lby-octavia-gcmouse.patch` (linked here); it builds in order after 0001-0003.

- Origin and licence: Elvin Hayatov's Wine merge request !11799 via WineForge 0.6.0.7, LGPL-2.1-or-later, his notice kept (see NOTICE).
- No build-file edits: `cocoa_gcmouse.m` is included from `cocoa_event.m`; GameController is loaded at run time, not linked.
- Trackpad: movement GameController does not report is not touched; AppKit's own events are left out only for 40 ms after a GameController report.
- Speed: `LULLABY_GCMOUSE_SCALE=<number>` or automatic (480 / counts per inch from the mouse's `HIDPointerResolution`, 0.05 to 2; 0.3 when it reports none).
- Switch: `LULLABY_GCMOUSE` (Diagnostics > GCMouse); the app writes `LULLABY_GCMOUSE_SCALE=auto`.

Checks by hand (no test rig can plug a mouse in): the mouse feels as before at its usual sensitivity; the trackpad moves at its normal speed with a mouse connected; unplugging and replugging the mouse keeps working.
