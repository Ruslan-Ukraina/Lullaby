# План миграции NotProton: CrossOver → Dormison (Фаза 0)

Статус: **план с твоими правками от 2026-10-06**. Решения — в `docs/DECISIONS.md` (В1–В4, S1). Фазу 1 запускаешь ты отдельной целью. Код проекта не менялся.
База: ветка `dormison` = upstream `main` v1.0.2 (`6ba74eb`) + `CLAUDE.md`.
Источники: код NotProton; исходники Dormison `52c2a4b918` (`~/Projects/dormison`);
README Sevoflurane (`~/Projects/sevoflurane`). Риски — в `docs/RISKS.md`.

## 0. Что нашлось при разведке (сверх CLAUDE.md и расхождения с ним)

| # | Факт | Где | Что из этого следует |
|---|---|---|---|
| 0.1 | Раскладка не `runners/<version>`, а `runners/crossover-<CFBundleVersion>[-fex]/CrossOver`; `current` — относительный симлинк на `crossover-…/CrossOver` | `SupportPaths.swift`, `RunnerInstaller.pointCurrent` | новые папки `runners/dormison-<tag>/`, `current` → `dormison-<tag>` |
| 0.2 | Кроме `WINEMSYNC=0` по умолчанию есть маркер `<compatdata>/notproton-msync`: он **переносит прошлое значение** на следующие запуски | `compat_run.sh`, `PrefixTools.syncBackend` | без миграции маркера старые префиксы останутся с `WINEMSYNC=0` |
| 0.3 | Имя инструмента в Steam задано как `TOOL_DISPLAY_NAME "CrossOver Preview"`. Папка `notproton` должна содержать «proton», иначе Steam Cloud не мапит пути | `dylib/feats/compat.c` | меняем только отображаемое имя |
| 0.4 | **Настройки игры в Steam уже есть.** webpatch встраивает панель в «Свойства → Совместимость»: `CX_GRAPHICS_BACKEND`, MetalFX для DXMT, DLSS, Metal HUD, AVX, MSync, Retina. Значения хранятся как параметры запуска игры и приходят в `compat_run.sh` как `NAME=VALUE` | `dylib/feats/webpatch.c` | **В3**: панель упрощается до выбора рендерера, основное — окно в NotProton.app, источник правды — `.sevo/apps/<exe>.env` |
| 0.5 | Sparkle-фид в `app/Info.plist` указывает на **апстрим** (`NotProtonNot/NotProton/…/appcast.xml`, его ключ) | `Info.plist`, `AppUpdater.swift` | **В4**: автопроверку выключаем уже в Фазе 1, свой фид — в Фазе 6 |
| 0.6 | В Dormison `WINEDLLPATH` просматривается **после** каталога движка и не перекрывает встроенную DLL. Перекрывает только `WINEDLLPATH_PREPEND` | dormison `dlls/ntdll/unix/loader.c`, `set_dll_path` | lsteamclient (его в движке нет) найдётся через `WINEDLLPATH`. Рендерер и, возможно, пропатченный `ntdll.dll` можно подключить через `PREPEND`, не трогая дерево движка (проверить в Фазе 1) |
| 0.7 | Дочерние Windows-процессы Dormison запускает через `<каталог ntdll.so>/wine`, а не через `$WINELOADER`. Копию загрузчика из бандла игры он берёт, только если в `.sevo/apps/<exe>.env` задан `SEVO_LOADER=<путь>` (тогда сам ставит `SEVO_LOADER_TREE`) | `loader.c` `loader_exec`, `loader/main.c` | саму игру запускает steam.exe-шим, то есть она дочерний процесс. Без `SEVO_LOADER` в Dock может оказаться «wine» без Game Mode |
| 0.8 | Копия загрузчика, запущенная **без аргументов** из пути вида `…/<число>/<Имя>.app/Contents/MacOS/…`, выполняет `open sevoflurane://play/<число>`. Раскладка NotProton `launchers/<appid>/<Имя>.app` подходит под этот шаблон, а Sevoflurane на этом Mac установлен | `loader/main.c:186–206` `open_in_sevoflurane` | **S1**, Фаза 1: `SEVO_LOADER_TREE` в launcher, нецифровой каталог бандла, launcher без аргументов не стартует загрузчик |
| 0.9 | Меню View в игре (Upscaler, Filter, FPS, FPS graph, Windows) сохраняет настройки через `$SEVO_CLI app config <appid> <key> <value>`. Без `SEVO_CLI` вызывается `/usr/local/bin/sevo`, то есть CLI Sevoflurane | `winemac.drv/cocoa_app.m:1160–1176` `sevoStoreSetting` | **S1**, Фаза 1: `SEVO_CLI` всегда задан и указывает на заглушку NotProton (§3.4) |
| 0.10 | Профиль пользователя в префиксе Dormison называется по имени пользователя macOS (`getpwuid`/`USER`), у CrossOver — `crossover`. NotProton создаёт `users/steamuser` и алиас `users/crossover → steamuser` | `compat_run.sh` `lay_out_proton_profile`, `PrefixRebuild` | нужен алиас `users/$USER → steamuser` или `USER=steamuser` в env. Проверить в Фазе 1 |
| 0.11 | CI запускает другой набор тестов, чем перечислен в CLAUDE.md: `sigcheck callscheck webpatch-fixtures peicon-fixtures panel-behavior spawn-env compatcheck compatsvc-check app-tests`. `anchorcheck` и `sigdb-fixtures` требуют настоящий `steamclient.dylib` | `.github/workflows/app.yml` | локально гоняю набор CI плюс `overlay-shim-tests` |
| 0.12 | `upstream/dev` ушёл на 16 коммитов (113 файлов, +3744/−2573) | git | **В1**: база `main` v1.0.2, из `dev` ничего не переносим |
| 0.13 | На этом Mac были следы прошлого эксперимента: `notproton/engines/dormison/…` и `notproton/bridge/engine/…`. Ещё установлен Sevoflurane с движком `~/Library/Application Support/Sevoflurane/Engines/dormison-b1` | диск | **В2**: удалены 2026-10-06. Steam Play не работает до деплоя Фазы 1 |
| 0.14 | У CrossOver cave в i386 `ntdll.dll` — 2000 байт (детур на 1376 помещался), у Dormison — 368 (§2.3 CLAUDE.md) | `NtdllPatcher.swift` | подтверждает: для 32-битных игр нужен B1 или новая PE-секция |
| 0.15 | Детур `detour2.bin` линкуется с абсолютными адресами конкретного `ntdll.dll` (`--defsym CAVE_VA, BM_RESUME, LDR_*`) | `ntdll-patch/build.sh` | бинарь детура привязан к версии движка и должен ехать в артефакте моста, а не в ресурсах приложения |

## 1. Файл → что от CrossOver → что делаем

### 1.1 Приложение: модель (`app/Sources/NotProtonApp/Model`)

| Файл | Что связано с CrossOver | Что делаем | Фаза |
|---|---|---|---|
| `SupportedRunner.swift` | allow-list CX 27.0.0.40921 Rosetta/FEX, sha256 загрузчика и `ntdll.dll` | `EngineRelease`: версия и commit из `engine-info.json`, sha256 из подписанного манифеста. Хеши ntdll — из `bridge-manifest.json`, не в коде. `WineArch.aarch64Windows` убрать | 2, 4 |
| `CrossOverSource.swift` | поиск `CrossOver*.app`, ручной выбор, хеш загрузчика | удалить; вместо него `EngineProvider` + `DormisonEngine` (§3.1) | 2 |
| `CrossOverLicense.swift` | проверка лицензии через `openssl` | удалить | 2 |
| `RunnerInstaller.swift` | `cp -c` CrossOver → `runners/crossover-<v>/CrossOver`, проверка хеша, `pointCurrent` | Фаза 2: установка из локального тарбола. Фаза 4: `EngineUpdater` — манифест → подпись → загрузка с докачкой → `.sig` и sha256 → распаковка в `runners/dormison-<tag>/` → проверка по `engine-manifest.json` → патч/оверлей → smoke-test → атомарный `current`, предыдущая версия остаётся. Код установщика Sevoflurane (MIT) — с атрибуцией | 2, 4 |
| `RunnerSetup.swift` | лицензия → клон → ntdll → патч → активация с откатом | конвейер `EngineSetup` без лицензии, откат оставить | 2 |
| `RunnerStore.swift` | состояние по `current` → `crossover-<build>` | разбор `dormison-<tag>`, версия из `engine-info.json`, список установленных версий для отката | 2 |
| `RunnerPatcher.swift` | пропатченный ntdll и lsteamclient копируются **в дерево CrossOver**; загрузчики переподписываются с `allow-dyld-environment-variables` | в дерево движка не писать без необходимости: lsteamclient — через `WINEDLLPATH`, ntdll (B1/B2) — через `WINEDLLPATH_PREPEND` или замену с записью в список оверлеев. Подпись: сначала проверить entitlements `wine/bin/wine` у Dormison (R4) | 1–3 |
| `NtdllPatcher.swift` + `Resources/detour*.bin` | RVA, cave и хеши по билду CX; FEX-варианты | B2: те же параметры, но из `bridge-manifest.json` (их в CI считает `resolve.py`); FEX удалить. При B1 файл удаляется: `ntdll.dll` приходит готовым в артефакте моста | 1, 3 |
| `PrefixTools.swift` | `CX_ROOT`, `CX_HOME`, `CrossOver-Hosted Application/wineserver*`, ветка aarch64 | пути из `EngineProvider` (`wine/bin/wine`, `wine/bin/wineserver`), `WINEMSYNC=1`, без `CX_*`; `SEVO_CLI` на заглушку (S1) и для инструментов префикса | 2 |
| `PrefixRebuild.swift` | алиас `users/crossover → steamuser`, слияние профиля `crossover` | слияние старого `crossover` оставить (миграция), алиас — на имя профиля Dormison (0.10) | 2 |
| `PrefixPrompt.swift` | текст про переключение Rosetta/FEX CrossOver | текст про переход с CrossOver | 2 |
| `PrefixStore.swift`, `PrefixesModel.swift` | ожидаемая архитектура префикса (arm64 для FEX) | только x86_64; префиксы FEX (aa64) — предлагать пересоздание | 2 |
| `BridgePayload.swift`, `InstallPayload.swift`, `PayloadManifest.swift`, `Resources/payload.manifest` | файлы моста, в т.ч. `aarch64-unix-lsteamclient.so` | убрать aarch64; мост привязать к версии движка (`bridge-dormison-<tag>-<rev>`); Фаза 5 — `BridgeUpdater` | 2, 5 |
| `UpdateBlock.swift` | — (Steam) | оставить; в Фазе 5 добавить гейт «нет сигнатур для билда N» | 5 |
| `ValveFetcher.swift`, `ValvePackageManifest.swift`, `valve-packages.manifest` | — (Windows steamclient от Valve) | без изменений: нужен для детура steamclient → lsteamclient | — |
| `SteamInstaller`, `SteamRepair`, `SteamBundle`, `Uninstall` | — | без изменений; `Uninstall` проверить на `runners/` | 2 |

### 1.2 Приложение: UI, поддержка, тесты

| Файл | Что связано | Что делаем | Фаза |
|---|---|---|---|
| `SystemStatus.swift` (42 упоминания), `Views/StatusView.swift` (27), `Support/AppLog.swift` | строки CrossOver, лицензия, переключение билдов, размеры клонов | строки «Движок Dormison bN (beta/stable) — обновить/откатить», «Мост», «Сигнатуры Steam»; лог состояния движка | 2, 4, 5 |
| новое | — | окно «Настройки игры» — **основное место настроек (В3)**: рендерер, изменяемое окно, апскейлер и финальный фильтр, FPS, raw mouse, удержание курсора, лимит ядер, msync+ (отладка), подсказка (i) у каждого пункта → `.sevo/apps/<exe>.env` | 2 |
| `Support/AppUpdater.swift`, `app/Info.plist` | Sparkle-фид и ключ **апстрима** | **В4**: в Фазе 1 (spike) выключить автопроверку и фид апстрима; в Фазе 6 — свои `SUFeedURL` и `SUPublicEDKey` | 1, 6 |
| `Package.swift` | ресурсы `detour32-fex.bin`, `detour64-fex.bin` | убрать FEX; при B1 — все `detour*.bin` | 2–3 |
| `app/Tests`: `CrossOverLicense`, `CrossOverSource`, `RunnerInstaller`, `RunnerSetup`, `RunnerSwitch`, `RunnerState`, `RunnerPatcher`, `NtdllPatcher`, `Detection`, `RealRebuild`, `PrefixTools` (53), `SystemStatus`, `PrefixStore` | фикстуры CrossOver | заменить тестами Dormison: раскладка провайдера, запись профиля `.sevo`, проверка подписи манифеста (вектор из настоящего `engine.json`), установщик, откат | 2, 4 |

### 1.3 dylib (хуки Steam)

| Файл | Что связано | Что делаем | Фаза |
|---|---|---|---|
| `feats/compat_run.sh` | `CX_ROOT`, `CX_HOME`; загрузчик и сервер из `lib/wine/{aarch64,x86_64}-unix` и `CrossOver-Hosted Application/…`; `WINEDLLPATH`, `PATH`; `WINEMSYNC=0` и маркер; `refuse_foreign_prefix` (тексты FEX/Rosetta); алиас `users/crossover`; фильтр `CX_GRAPHICS*`; `verify_runner` (ntdll моста = ntdll раннера); бандл с симлинками `$wine_unix/*`; launcher с `DYLD_INSERT_LIBRARIES` | читать `runners/current/notproton-engine.env` (его пишет приложение); `WINEMSYNC=1` по умолчанию и миграция маркера; пропускать `SEVO_*`; выбор рендерера → `WINEDLLPATH_PREPEND`; `SEVO_LOADER` для exe игры; `verify_runner` по `bridge-manifest`; текст отказа для FEX-префиксов. **S1:** launcher экспортирует `SEVO_LOADER_TREE` и `SEVO_CLI` (заглушка), без аргументов не запускает загрузчик, каталог бандла — не только цифры (`launchers/app-<appid>/`). Новые переменные добавить в список `--env` у `open -a`, иначе они не дойдут до бандла | 1 (грязно), 2 |
| `feats/compat.c` | `TOOL_DISPLAY_NAME "CrossOver Preview"`, `np_compat_register_crossover` | отображаемое имя → «Dormison (NotProton)»; функцию переименовать. Каталог `notproton` не трогать | 2 |
| `hooks/hook_compat.c`, `feats/compat.h` | имена и комментарии «CrossOver default» | переименовать | 2 |
| `feats/webpatch.c` | панель CX-опций, текст «Enable CrossOver under Properties…» | **В3**: в панели остаётся только выбор рендерера, остальные CX-опции убираем; тексты. Якоря (строки самого Steam) не меняются | 2 |
| `tests/compatsvc-check.c`, `tests/panel-behavior/*.js` | ожидаемые строки CrossOver | обновить вместе с кодом | 2 |
| `overlay-shim/` | только комментарий про FEX | без изменений; совместимость с презентером Dormison проверяется в Фазе 1 | 1 |

### 1.4 Мост и сборка

| Файл | Что связано | Что делаем | Фаза |
|---|---|---|---|
| `bridge/setup-wine-tree.sh` | wine-11.15 `2df1ee28`, два дерева (x86_64 и arm64 для FEX) | исходники Dormison `52c2a4b918` через `git worktree` из `~/Projects/dormison` (рабочую копию не пачкать); одно дерево x86_64; `--enable-archs=i386,x86_64`, как в `build-macos/configure.sh` | 1 |
| `bridge/register-components.diff` | смещения под configure 11.15 | перегенерировать под configure Dormison | 1 |
| `lsteamclient/build.sh` | `--install` в дерево CrossOver (`runners/current/lib/wine`), `UNIX_ARCH=arm64` | ставить только в мост; arm64 убрать | 1–2 |
| `steam-shim/build.sh` | — | без изменений | — |
| `Makefile` | `bridge` собирает arm64-дерево, в `BRIDGE_FILES` есть aarch64, `CX_ROOT ?= …CrossOver Preview.app` | убрать arm64; `ntdll-resolve` — по пути движка; новые цели `engine-fetch`, `ntdll-dormison` | 1–3 |
| `ntdll-patch/` | пины CX в `build-ntdll.sh` и `resolve.py`; FEX (`build64.sh`, `shim64.S`, `link64.ld`) | B2: пины Dormison b1 (x86_64); FEX удалить. Фаза 3: B1 — перенос логики `detour.c` в `dlls/ntdll/loader.c` форка Dormison | 1, 3 |
| `.github/workflows/app.yml` | раннер `xcode-27`, кеш Wine 11.15 | Фаза 6: раннер GitHub `macos-*`, кеш дерева Dormison, задания «движок», «мост», «сигнатуры» | 6 |
| `README.md`, `NOTICE` | CrossOver | атрибуция: Dormison (LGPL 2.1+), Sevoflurane (MIT), lsteamclient (Steamworks SDK License), steam-shim (BSD-3), Mullion (LGPL 2.1+) | 7 |

### 1.5 Данные на диске пользователя

| Что | Сейчас | Что делаем |
|---|---|---|
| `notproton/runners/crossover-*` | копии CrossOver | после успешной установки Dormison предложить удалить (спросить) |
| префиксы `compatdata/<id>/pfx` от CX Rosetta (x86_64) | работают под CX | переиспользуем: `wineboot --init` обновит их; дописать `.sevo/bottle.env` |
| префиксы от CX FEX (aa64) | — | `refuse_foreign_prefix` уже отказывает → пересоздание через `PrefixRebuild` (сейвы сохраняются) |
| `compatdata/<id>/notproton-msync` | `0` | при первом запуске под Dormison переписать в `1` |
| `notproton/engines/dormison/*`, `bridge/engine/*` | — | **удалено 2026-10-06 (В2)** |
| `notproton.dylib` в `/Applications/Steam.app` | от прошлого эксперимента, ссылается на удалённый `engines/dormison` | заменить сборкой Фазы 1 |

## 2. Порядок работ по фазам

- **Фаза 1, spike** (ветка `spike/dormison`, грязно; запускаешь ты отдельной целью):
  - выключить автопроверку Sparkle (**В4**) до первой установки spike-сборки;
  - распаковать b1 в `runners/dormison-b1` (из проверенного тарбола или копии движка Sevoflurane), `current` → туда;
  - в `compat_run.sh` пути §2.2 CLAUDE.md и `WINEMSYNC=1`, плюс защита **S1**: `SEVO_LOADER_TREE` и `SEVO_CLI` (заглушка) в launcher, нецифровой каталог бандла, отказ запускать загрузчик без аргументов;
  - мост — `setup-wine-tree.sh` на worktree Dormison `52c2a4b918`;
  - x86_64-патч ntdll — `resolve.py` + `build.sh` + `apply.py`;
  - гипотезы 0.6–0.10 и R4–R6 проверить по логам;
  - `docs/SPIKE_TEST.md` для ручных проверок. Если S1 не закроется — описать в нём обход.
- **Фаза 2**: `EngineProvider`/`DormisonEngine`, `notproton-engine.env`, профиль `.sevo`, окно «Настройки игры» и упрощённая панель в Steam (В3), заглушка `SEVO_CLI` превращается в настоящую запись в `.sevo/apps/<exe>.env`, замена тестов.
- **Фаза 3**: B1 (PE `ntdll.dll` x86_64 и i386 из коммита релиза) или B2 + новая секция для i386; решение — в `docs/DECISIONS.md`.
- **Фазы 4–7** — как в CLAUDE.md; свой Sparkle-фид — в Фазе 6 (В4).

## 3. Архитектурные заметки

### 3.1 EngineProvider
`DormisonEngine(root: runners/current)`:
`wineloader = wine/bin/wine`, `wineserver = wine/bin/wineserver`,
`dllPaths(.x86_64) = [wine/lib/wine/x86_64-windows]`, `dllPaths(.i386) = [wine/lib/wine/i386-windows]`,
`unixDir = wine/lib/wine/x86_64-unix`, `renderers = engine-info.json.renderers`, `version`, `commit`.
Приложение при установке пишет `runners/<tag>/notproton-engine.env` (абсолютные пути и версия), а `compat_run.sh` только читает его (`. "$env_file"` с проверкой формата).
Что такое `wine/bin/wine` — сам загрузчик или симлинк на `x86_64-unix/wine` — проверить на тарболе. От этого зависит, как бандл игры находит `ntdll.so`; при `SEVO_LOADER_TREE` это уже не важно.

### 3.2 Профиль `.sevo/bottle.env` по умолчанию
Сверено с README Sevoflurane (таблица «Dormison switches»):

```
WINEMSYNC=1
SEVO_RESIZABLE_WINDOWS=1   # у движка по умолчанию off — включаем сами
SEVO_UPSCALER=off          # у движка off
SEVO_FINAL_FILTER=lanczos  # у движка lanczos
SEVO_FPS=0                 # у движка off
SEVO_FPS_GRAPH=0
SEVO_LINEAR_MOUSE=0
SEVO_CURSOR_CONFINE=0
SEVO_CLI=<заглушка NotProton>   # S1: запасной /usr/local/bin/sevo не вызывается
```

Формат значений (`0/1`, `on/off`, `y/n`) и семантику `apply_env_file(path, TRUE/FALSE)` (перекрывает ли файл переменные, уже заданные в env процесса) сверить по `dlls/winemac.drv` и `dlls/ntdll/unix/env.c` в Фазе 2. `WINEMSYNC=1` дублируется в env из `compat_run.sh`, потому что `wineserver` должен стартовать с тем же значением.

### 3.3 lsteamclient
Spike — B2 для x86_64 (`resolve.py` нашёл место хука, см. CLAUDE.md §2.3). Пропатченный `ntdll.dll` сначала пробую подать через `WINEDLLPATH_PREPEND`, не трогая дерево движка; если ntdll грузится не по `dll_paths` — замена файла в копии движка с записью в список оверлеев. Фаза 3 — B1 (§4.4 CLAUDE.md).

### 3.4 `SEVO_CLI` и меню View (S1)
- **Фаза 1:** заглушка `notproton-sevo` (рядом с `appinfo`/`iconmaker`). Она ничего не вызывает, только пишет строку в лог. `SEVO_CLI` указывает на неё всегда: в env launcher и в `.sevo/bottle.env`.
- **Фаза 2:** заглушка понимает `app config <appid> <key> <value>` и пишет в `<prefix>/.sevo/apps/<exe>.env`. Ключи из `cocoa_app.m`: `upscaler`, `filter`, `fps`, `fps-graph`, `windows` (`off`/`fixed`/`all`/`window`). Тогда выбор в меню View переживает перезапуск и совпадает с окном «Настройки игры».
- Скрыть пункты меню нельзя без пересборки `winemac.so`. Это unix-часть движка, а B1 собирает только PE `ntdll.dll`.

### 3.5 Dock-шим Dormison
Даёт: скрытие служебных процессов Steam из Dock (`TransformProcessType`), подавление окон, имя/иконку игры. Логи и иконки пишет в пути Sevoflurane, а выход бутылки привязывает к `SEVO_OWNER_PID`. NotProton уже делает бандл с именем и иконкой. **Не подключаем** (S1 и §3 CLAUDE.md). Если после spike служебные процессы будут вылезать в Dock — решаем своим кодом; из `upstream/dev` ничего не переносим (В1).

## 4. Решения

Все вопросы закрыты 2026-10-06, подробности — в `docs/DECISIONS.md`:
- **В1** — `upstream/main` v1.0.2, из `dev` ничего не переносим.
- **В2** — следы эксперимента удалены.
- **В3** — оба варианта, источник правды `.sevo/apps/<exe>.env`; основное — окно в NotProton.app, панель в Steam — только рендерер.
- **В4** — Sparkle выключить уже в Фазе 1, свой фид — в Фазе 6.
- **S1** — форк никогда не вызывает Sevoflurane.
