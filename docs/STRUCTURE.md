# Repository map

Paths in the column "Было" are today's locations; moves follow the protocol at the end (one logical move per commit).


| Каталог | Назначение | Что класть | Чего нельзя | Поток | Было |
|---|---|---|---|---|---|
| `app/` | Lullaby.app и `lullaby-settings` (Swift) | исходники, тесты, `Info.plist`, иконка | двоичные payload (они в `.gitignore`), пути на конкретную машину | App | `app/` (без `NotProtonApp/`) |
| `steam/hook/` | библиотека, которая грузится в Steam (`lby-luna-steamhook`): Mach-O, хуки, резолвер сигнатур, окна Steam, панель | C/ObjC/JS, тесты и фикстуры | логику игры (она в `launch/`) | App/Patches | `dylib/` кроме `feats/compat_run.sh` |
| `steam/launch/` | скрипт запуска игры, разрезанный на части (пакет игры, окружение, рендерер, Game Mode, лог) | `.sh` модули, `embed_script.py`, тесты | пересчёт настроек (они в `app/`) | App | `dylib/feats/compat_run.sh` |
| `steam/overlay/` | оверлей Steam в игре (`lby-spike-overlay`) | `.m`, тесты | | Patches | `overlay-shim/` |
| `steam/signatures/` | база сигнатур Steam | JSON по билдам, `manifest.json` | ручные правки | Release | `signatures/` |
| `bridge/` | мост Steam: `lby-applejack-steambridge` (lsteamclient), `lby-bigmack-steamexe` (steam.exe) | исходники, скрипты сборки, `bridge-manifest.json` | VR/Vulkan без записанной причины; пересборку модулей Dormison (это `patches/`) | Bridge | `lsteamclient/`, `steam-shim/`, `bridge/` |
| `engine/` | как получить и проверить Dormison (r8): скрипты загрузки, подпись Ed25519, описание пары | скрипты, проверка | сами файлы движка, патчи | Engine | `engine/` |
| `patches/` | **всё, что мы добавляем к чужому коду** (§1.6) | см. ниже | | Patches | `patches/engine/`, `ntdll-patch/`, `nvapi-shim/` |
| `patches/REGISTRY.md` | единый реестр: ID, заголовок, на каких релизах проверен, переключатель | | | Patches | `docs/PATCH_REGISTRY.md` |
| `patches/engine/` | патчи Dormison, серия на основу (`dormison/ntdll.so/NNNN-….patch` и т.д.) | `.patch` с заголовком, `tests/` | чужой исходник целиком | Patches | `patches/engine/patches` |
| `patches/inject/` | инжекты без пересборки движка: Reflex, пейсер, GCMouse, состояние окна | каждый — каталог `lby-<имя>-<роль>/` | | Patches | `nvapi-shim/` и новые |
| `patches/steam/` | ссылка на `steam/hook` и `steam/overlay` (они — тоже патчи Steam) | только ссылки (§1.6) | | Patches | — |
| `patches/tools/` | `rehearse`, `build-fixes`, `check-registry`, `make patchcheck` | скрипты | | Patches | `patches/engine/*.sh` |
| `release/` | подпись, ленты, CI-скрипты | | ключи, токены | Release | `release/` |
| `tools/` | `check-structure`, импорт данных игр, перф-стенд (`tools/perf/`) | скрипты, фикстуры | личные сценарии (они в рабочей папке ИИ) | Release | `tools/`, `perf/` (часть) |
| `vendor/` | закреплённые чужие файлы (cJSON), как их получать | | Dobby/Sparkle (скачиваются) | Release | `vendor/` |
| `docs/` | для людей: `STRUCTURE`, `NAMING`, `PROJECT_RULES`, `DECISIONS`, `RELEASING`, `DXMT_PIN`, `GAME_FIXES`, … | | журналы, планы ИИ, отчёты | все | `docs/` (разобран) |
| `.github/` | CI | | | Release | `.github/` |
| `LICENSE*`, `NOTICE`, `README.md` | лицензии, атрибуция, вход | | | — | |

**Ссылки (§1.6).** Реальное место → ссылка в `patches/`:
`steam/hook` → `patches/steam/lby-luna-steamhook`, `steam/overlay` → `patches/steam/lby-spike-overlay`. Если ссылка ломает сборку — файл-указатель `*.ptr` с тем же именем.
**Исключения проверок (`tools/check-structure.allow`):** ссылки выше, `app/Sources/*/Resources/payload/` (генерируется), `scratch/` (если останется, в `.gitignore`).

Скрипт `tools/check-structure` сверяет каталоги первого уровня и ссылки с таблицей; только чтение.

### Что переносится и в каком порядке (протокол «Гигиена», п. 4)
1. S2: создать ветку, перенести `engine-fixes → patches` одним коммитом (`git mv`), правки `Makefile` и `.github` в том же коммите, до и после — `make patchcheck`, сборка моста.
2. Затем `nvapi-shim → patches/inject`, `ntdll-patch/b1 → patches/engine/…` (если B1 остаётся), `perf/ → tools/perf`.
3. `dylib/ → steam/hook`, `overlay-shim → steam/overlay`, `lsteamclient`+`steam-shim` под `bridge/` — **последними**, потому что `Makefile` и `embed_script.py` завязаны на пути.
Файлы из рантайма (бандл, `~/Library/Application Support/lullaby`) не двигаются.


