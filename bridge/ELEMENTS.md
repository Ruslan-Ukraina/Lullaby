# Bridge elements and why each is there

Rule (docs/PROJECT_RULES.md, S6): every part of the bridge has a recorded reason; a part without one is removed.

## lby-applejack-steambridge (`lsteamclient/`, Steamworks SDK License)
| Element | Reason |
|---|---|
| `steamclient_main.c`, `build.sh`, `fetch.sh` | The Windows-side `lsteamclient.dll` the engine's ntdll hook points a game's `steamclient64.dll` at; sources are Proton's, fetched at a pinned commit. |
| `unixlib.cpp`, `unix_steam_input_manual.cpp` | The unix half: carries the game's Steamworks calls (achievements, stats, overlay, Steam Input) to the macOS Steam client. |
| `add-interfaces.py` | Adds Steamworks interface versions Proton's tarball lacks (e.g. `SteamNetworkingSocketsSerialized005`, which crashed Deadlock). |
| `tests/ifacecheck.*` | Every interface version a game can ask for resolves. |

## lby-bigmack-steamexe (`steam-shim/`, BSD-3-Clause, from Proton's `steam_helper`)
The Windows program standing in for `steam.exe` in the prefix; the macOS Steam is the real client.
| Element in `steam.cpp` | Reason |
|---|---|
| `steam_command_handler` | `steam://` URLs a game opens go to the macOS Steam; a restart request re-runs the game. |
| `create_steam_window`, `set_active_process_pid`, `set_client_dll_paths`, `set_install_paths`, `setup_steam_registry` | Games look Steam up through its window class and registry keys (install path, user, language, active process). |
| `steam_client_init` / `steam_client_shutdown` | The shim asks the Steam client (through `lsteamclient`) for the user and app data it puts in the registry. |
| `setup_steam_files` | `libraryfolders.vdf` etc. in the prefix, so games find their library. |
| `run_process` | Starts the game (and launchers: EA app, `steam://` forwards, console games), hands it the std handles for the log except for a program with a console of its own (NotProton 1.2.0). |
| `steam_drm_thread` | The handshake Valve's DRM wrapper waits for. |
| `console_ctrl_handler`, `PROTON_HIDE_PROCESS_WINDOW` | Closing a console and hiding a helper's window. |
| `posix_compat.h` | `setenv` (the game's locale) is absent from the mingw runtime. |

Removed in S6, with the reason: SteamVR/OpenXR setup (VR paths, `vrclient`, registry keys, winevulkan queries, OpenVR headers) and the JSON parser it needed (jsoncpp): no VR runtime exists on macOS and the code never ran; the Linux BattlEye/EAC runtime bridges: those Proton runtimes are Linux-only; `PROTON_WAIT_ATTACH`/`is_ptraced`: a Proton developer's debugger wait; the `dlfcn.h` stand-in: only the VR code used `dlopen`. `steam.exe` went from 14 MB to 4.5 MB.

## Scripts and data
| Element | Reason |
|---|---|
| `setup-wine-tree.sh`, `register-components.diff` | The Wine source tree at the engine's own commit that `lsteamclient` and the shim are built in (ntdll from another vintage speaks another server protocol). |
| `strip-debug.sh` | Ships the bridge without debug information. |
| `verify.sh`, `pe-info.py` | Checks what the bridge folder holds, and the architecture of what was built. |
| `fetch-valve.sh` | Fetches Valve's own Windows `steamclient` (`bins_win64`) that games with DRM load alongside the redirect. |
| `bridge-manifest.json` | The signed compatibility list: engine <-> bridge <-> patches. |
