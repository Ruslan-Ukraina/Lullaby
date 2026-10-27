# patches
Everything Lullaby adds to other people's code, in one place (docs/PROJECT_RULES.md). `REGISTRY.md` lists every patch/inject with ID, origin, verified releases and switch.
- `engine/` patches to Dormison modules, per module, plus the ntdll hook (lby-discord-ntdllhook) and the rebuild/rehearsal tools.
- `inject/` components injected without rebuilding the engine (lby-rainbowdash-reflex).
- `steam/` links to `../steam/hook` and `../steam/overlay` (components that patch Steam itself).
- `lby-derpy-fixes/` the small fixes of other people's code: the injected library for WineMetalGL and links to the small fixes of the engine series (the patches themselves stay in `engine/patches/`).
