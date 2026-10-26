# lby-spitfire-apiscout (CMP-07, S10)

Status (2026-10-26): the code lives in `steam/hook/feats/compat_run.sh` between `# --- apiscout begin` and `# --- apiscout end` (one run script, so no new file to ship) and is wired in LOG ONLY mode: it writes `apiscout: api=... source=... backend=... (log only, ...)` to the Lullaby log and remembers the places of the verdict in `compatdata/<appid>/lullaby-apiscout`; the renderer is not changed by it. It reads the Steam option's arguments, Source 2 `boot.vcfg`, RE Engine `config.ini` (`Capability=DirectX12`), SCS `config.cfg`, Unity `Player.log` (last run), D3D12 hints and the MonoGame build (DesktopGL or SharpDX) beside the exe. Tests: `make apiscout-tests` (38 checks, made-up fixtures, they extract the block from the run script). Not written yet: switching the renderer by the verdict, the catalog, the error text.

What it does: before a game's first launch, within 3-5 seconds, it collects evidence for the API the game will draw with and picks one backend per API: DX12 D3DMetal, DX11 DXMT, DX9 mtld3d, Vulkan KosmicKrisp, OpenGL WineMetalGL. It remembers where each verdict came from (path, mtime, size, value) and, before the next launch and once after the game exits, re-reads only those places, so a backend the player changed in the game is noticed.

Order of evidence: the launch option chosen in Steam; the game's own saved settings (read only, per engine); memory of the last run; the catalog; files beside the exe; default DXMT. The player's manual choice wins and switches the scout off for that game.

Rules:
- Read only: it never writes a game's files or settings.
- No recursive scans; a hard 3 s deadline, then the best verdict so far.
- It runs inside the process tree Steam already started: no new permission prompts from macOS (no Documents, Desktop, Downloads or removable-volume reads, no Accessibility, Screen Recording or Full Disk Access).
- Nothing known: DXMT. If the game then does not start: an error on screen that tells the player to open the game's Properties > Compatibility in Steam and change the backend for this game (no picker of our own; only the backend is mentioned).
- A trial launch of the game stays as the last resort, so that it does not happen all the time: only when every other source gave nothing, once per game and game version, and its result is remembered (it is never repeated at the next launch). It is the only moment a window may open and close or the Play button blink. The VAC rule still applies (online VAC games: menu only).
- No silent switch to a backend of another API.
- Invisible: while the player launches a game, nothing opens, closes or flickers and Steam's Play button does not blink (the one exception is the rare trial launch above). No window, no dock icon, no sound, no notification, no extra prompt. The player notices it only through a game that starts on the right backend. The one visible thing is the error that points to Properties > Compatibility, and only when the game did not start.
- No felt delay: the verdict is prepared ahead of the launch (after the game exits and when the game's files change) and a launch only reads the saved verdict and checks the remembered places; the 3-5 s collection is the worst case of a game seen for the first time.

## Where it keeps its memory
`<Steam library>/steamapps/compatdata/<appid>/lullaby-apiscout`: one line per remembered place of the last verdict (`path|mtime size`), beside `lullaby-msync` and `lullaby-run.log` in the game's own compatdata (Lullaby's file, not one of Steam's). The run script reads and rewrites it at each launch (`apiscout_remember`, `apiscout_changed` in `steam/hook/feats/compat_run.sh`); deleting it only makes the scout judge the game afresh.

In this folder: `compat_run.sh` is a link to the run script that holds the code (PROJECT_RULES 2.1); `compatdata` is a link to the Steam `compatdata` folder, where each game's `<appid>/lullaby-apiscout` is kept. It is a relative link (`../../../../../Library/Application Support/Steam/steamapps/compatdata`, no user name), so it can be committed; it works while the repository is `~/Lullaby-Project/Lullaby` and Steam is in the default place, and elsewhere it simply points nowhere.
