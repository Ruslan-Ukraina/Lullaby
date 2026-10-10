# Задача: Lullaby — форк NotProton на движке Dormison (без CrossOver) с самообновлением — v2

Положи этот файл в корень своего форка как `CLAUDE.md` (или вставь первым сообщением в Claude Code). Работай по фазам, после каждой фазы — коммит и короткий отчёт мне.

---

## 1. Цель

Удобное для обычного пользователя macOS-приложение — форк https://github.com/NotProtonNot/NotProton (Steam Play в нативном macOS Steam), в котором:

1. **CrossOver полностью убран**: поиск CrossOver.app, проверка лицензии, клонирование в `runners/`, пути `CrossOver-Hosted Application/…`, FEX-ветка.
2. **Движок — Dormison** (https://github.com/kageroumado/dormison) с его фирменными возможностями, включёнными по умолчанию:
   - **msync+ всегда включён** (`WINEMSYNC=1`). Выключение только как отладочный переключатель на конкретную игру.
   - **Игры в нативных окнах macOS**: изменяемый размер с сохранением разрешения игры (`ResizableWindows`), нативный полноэкранный режим, апскейлер (Lanczos / MetalFX Spatial / Anime4K / CuNNy), счётчик FPS и график кадров, raw mouse (`LinearMouse`), удержание курсора (`CursorConfine`), меню View в игре.
   - Настройки на игру и на префикс — через env-файлы движка (см. §2.2), из понятного UI.
3. **Всё самообновляется**: движок, мост (lsteamclient + steam-shim), база сигнатур Steam-клиента, само приложение.
4. Для пользователя: поставил приложение → оно скачало движок → в macOS Steam появился Steam Play → игры запускаются из библиотеки.

## 2. Проверенные факты (не трать время на повторное исследование)

### 2.1 NotProton — где он завязан на CrossOver
- `app/Sources/LullabyApp/Model/SupportedRunner.swift` — allow-list CrossOver Preview `27.0.0.40921` (Rosetta и FEX) с sha256 загрузчика и `ntdll.dll`.
- `Model/CrossOverSource.swift`, `CrossOverLicense.swift` — поиск CrossOver и проверка лицензии.
- `Model/RunnerInstaller.swift`, `RunnerSetup.swift`, `RunnerStore.swift`, `RunnerPatcher.swift` — копия CrossOver в `~/Library/Application Support/lullaby/runners/<version>`, симлинк `runners/current`.
- `Model/NtdllPatcher.swift` + `ntdll-patch/` (`resolve.py`, `apply.py`, `detour*.c`, `shim*.S` — удалены, O3/P9-9, есть в истории git) — **бинарный патч ntdll.dll по захардкоженным RVA**. Детур при загрузке `steamclient64.dll`/`steamclient.dll` перенаправляет их экспорты и entry point на `lsteamclient.dll`. Это та же идея, что `steamclient_setup_trampolines` в Proton-Wine (`ValveSoftware/wine`, `dlls/ntdll/loader.c`, функции `use_lsteamclient` и далее + unix-вызов `unix_steamclient_setup_trampolines`).
- `dylib/feats/compat_run.sh` (встраивается в dylib через `embed_script.py`) — запуск игры. Там `CX_ROOT`, `WINELOADER=$CX_ROOT/lib/wine/{aarch64,x86_64}-unix/…`, `WINESERVER=$CX_ROOT/CrossOver-Hosted Application/wineserver…`, `WINEDLLPATH`, `WINEDLLOVERRIDES="steamclient=n;steamclient64=n;lsteamclient=b"`, **`WINEMSYNC` по умолчанию 0** (менять на 1), симлинк `users/crossover`, фильтр env `CX_GRAPHICS*`. Там же создаётся **per-game .app-бандл с копией wine-загрузчика** (имя и иконка игры в Dock + macOS Game Mode), а `overlay-shim.dylib` подключается через `DYLD_INSERT_LIBRARIES`.
- `bridge/setup-wine-tree.sh` — собирает lsteamclient и steam.exe-shim против **wine-11.15** (под CrossOver 27). Для Dormison нужна сборка против **его же исходников**.
- Steam: `signatures/macos.arm64/<steam_build>.json` (AOB-сигнатуры `CCompatManager::*` и др.), `Model/UpdateBlock.swift` (`BootStrapperInhibitUpdateOnLaunch`), `Model/ValveFetcher.swift` + `valve-packages.manifest`.
- Приложение обновляется через Sparkle (`Support/AppUpdater.swift`, `SUFeedURL`/`SUPublicEDKey` в `app/Info.plist`).
- Сборка — корневой `Makefile` (`make bridge`, `make app-payload`, `make app`, тесты `app-tests sigcheck anchorcheck sigdb-fixtures webpatch-fixtures overlay-shim-tests`).

### 2.2 Dormison — проверено на релизе `b1`
- Манифест: `https://github.com/kageroumado/dormison/releases/download/manifest/engine.json` + `engine.json.sig`. Схема 2: `channels.{stable,beta}.{version,minAppVersion,url,sha256,sizeBytes,notes}`, `components.{dxmt,dxvk}[]`. Сейчас есть только `beta = dormison-b1`.
- `.sig` — base64 сырой Ed25519-подписи над байтами файла. Публичный ключ (закреплён в Sevoflurane, `Core/Setup/EngineSignature.swift`): `7uDuIZdCZyobjZcPL12zL+UNOCpHSvLXvVRFHA7bzzA=`. **Проверено: подписи `engine.json` и `dormison-b1.tar.xz` этим ключом валидны, sha256 тарбола совпадает с манифестом.**
- Тарбол `dormison-b1.tar.xz` (~233 МБ, распакован ~1.1 ГБ) → папка `dormison-b1/`:
  - `engine-info.json` (`version`, `commit`, `wine: "11.16 + wine-staging 11.16"`, `sync: "msync (WINEMSYNC=1)"`, `server: "arm64"`, `renderers: [auto, dxmt, dxvk, d3dmetal, wined3d]`), `engine-manifest.json` (sha256 каждого файла);
  - `wine/bin/wine` — **x86_64** (Rosetta), `wine/bin/wineserver` — **arm64**;
  - `wine/lib/wine/{x86_64-unix,x86_64-windows,i386-windows}`; в `x86_64-unix` есть `ntdll.so`, `win32u.so`, `winemac.so`, `winemetal.so`, `winevulkan.so`, `winegstreamer.so`;
  - `dxmt/` (D3D10/11 через Metal, + `i386-windows/`, `nvapi64.dll`, `nvngx.dll`), `dxvk/`;
  - `libsevodockshim.dylib`, `sevo-steamstub*.exe`, `sevo-discord-bridge.exe`, `sevo-fpsunlock*`.
  - Отдельного `aarch64-unix` и FEX нет.
- Оконные функции — **в самом движке** (`winemac.so`: `reapplyResizableWindows`, `sevoToggleResizableWindows:`, `toggleFullScreen:`). Sevoflurane для них не нужен.
- Управление (README Sevoflurane, раздел «Dormison switches»):
  - реестр `HKCU\Software\Wine\Mac Driver`: `ResizableWindows`, `Presenter`, `Upscaler`, `FinalFilter`, `FrameRate`, `FrameRateGraph`, `OpenGLPresenter`, `LinearMouse`, `CursorConfine`, `StatusItems`;
  - env: `SEVO_RESIZABLE_WINDOWS`, `SEVO_PRESENTER`, `SEVO_UPSCALER`, `SEVO_FINAL_FILTER`, `SEVO_FPS`, `SEVO_FPS_GRAPH`, `SEVO_LINEAR_MOUSE`, `SEVO_CURSOR_CONFINE`, `SEVO_SHADER_DIR`, `SEVO_GPU_*`, `SEVO_CPU_COUNT`, `SEVO_LARGE_ADDRESS_AWARE`, `SEVO_QUIET`;
  - движок при каждом старте процесса читает `<prefix>/.sevo/bottle.env`, затем `<prefix>/.sevo/apps/<exe>.env` (`<exe>` — имя exe в нижнем регистре). `WINEDLLPATH_PREPEND` добавляет каталог перед встроенными DLL.
- Dock-шим Dormison (`build-macos/dock-shim/sevo_dock_shim.c`) работает через `DYLD_INSERT_LIBRARIES` и env (`WINEPREFIX`, `WINELOADER`, `SEVO_LOADER_TREE`, `SEVO_OWNER_PID`, `SEVO_SUPPRESS_WINDOWS`, `SEVO_QUIET`). Пишет логи и иконки в пути Sevoflurane. Клик по плитке в Dock «запускает игру через Sevoflurane» — это функция приложения, в форке её нет.
- Меню View в игре для части действий вызывает `SEVO_CLI` (CLI `sevo`). Без него эти пункты не работают — реши, что с ними делать.
- **D3DMetal (DX12) в движке нет.** Только из Apple Game Porting Toolkit, который пользователь скачивает сам через Apple Account. Распространять GPTK нельзя.
- Референсный установщик — Sevoflurane (MIT): `Core/Setup/EngineManifest.swift`, `EngineSignature.swift`, `EngineInstaller.swift`.

### 2.3 Результат `ntdll-patch/resolve.py` на ntdll от Dormison b1 (запущено)
- `x86_64-windows/ntdll.dll`: место хука найдено (`hookRVA 0x52f36`, та же инструкция `cmp qword ptr [rsp+0xf0],0`, `wm rsi`, `load_path rsp+0xd0`), code cave 2208 байт, payload 864 → **помещается**.
- `i386-windows/ntdll.dll`: место хука найдено (`hookRVA 0x4f940`), но **cave 368 байт при payload 1376 → не помещается**. Бинарный патч для 32-битных игр в текущем виде не работает.

## 3. Жёсткие ограничения

- Лицензии: форк GPLv3. Дополнить `NOTICE`: Dormison — LGPL 2.1+, код из Sevoflurane — MIT с сохранением копирайта, lsteamclient — Steamworks SDK License, steam-shim — BSD-3, Mullion (если добавим) — LGPL 2.1+. GPTK не встраивать и не скачивать в обход Apple.
- Никогда не доверять скачанному без проверки: манифест проверять по Ed25519, тарбол — по `.sig` и sha256 из манифеста.
- Обновления атомарные: новая папка → проверка → переключение `current`. Предыдущая версия остаётся для отката. Не обновлять, пока запущены Steam или игра.
- Не ломать то, что не связано с движком: хуки dylib, webpatch, overlay-shim, префиксы.
- Без sudo и без изменений системных настроек macOS.
- Перед необратимым действием (удаление чужих префиксов, перезапись данных Steam) — остановись и спроси.

## 4. Архитектура

1. **`EngineProvider`** вместо прямых путей CrossOver: `wineloader` (`wine/bin/wine`), `wineserver` (`wine/bin/wineserver`), `dllPaths(arch:)`, `version`, `capabilities` из `engine-info.json`. Реализация — `DormisonEngine`. `compat_run.sh` берёт пути и переменные из `runners/current/notproton-engine.env` (его пишет приложение при установке), а не из структуры CrossOver.
2. **Профиль Dormison по умолчанию** (пишется в `<prefix>/.sevo/bottle.env` при создании и миграции префикса):
   `WINEMSYNC=1`, `SEVO_RESIZABLE_WINDOWS=1`, апскейлер выключен, FPS выключен, `SEVO_LINEAR_MOUSE` и `SEVO_CURSOR_CONFINE` выключены. Значения сверить с README Sevoflurane и `dlls/winemac.drv` Dormison.
   Пер-игровые оверрайды — в `<prefix>/.sevo/apps/<exe>.env`. В UI — окно «Настройки игры»: рендерер (DXMT / DXVK / D3DMetal / wined3d / Mullion — эксперимент), изменяемое окно, апскейлер и финальный фильтр, FPS, raw mouse, удержание курсора, лимит ядер, msync+ (отладка). Подсказка (i) у каждого пункта.
3. **Окна и Dock.** NotProton уже делает per-game .app-бандл (имя, иконка, Game Mode). Его оставить. Dormison dock-шим подключать только если он даёт что-то сверх этого (например, скрытие служебных процессов из Dock). Тогда цепочка `DYLD_INSERT_LIBRARIES` = overlay-shim + dock-shim + Steam. Проверить, что нативный полноэкранный режим и изменение размера работают внутри бандла.
4. **Подгрузка lsteamclient (главный технический риск).** Выбрать по доказательствам, решение записать в `docs/DECISIONS.md`:
   - **B1 (предпочтительно): C-хук в исходниках ntdll Dormison.** Перенести логику `ntdll-patch/detour.c` (или Proton-патч `steamclient_setup_trampolines`) в `dlls/ntdll/loader.c` форка Dormison. Собрать **только PE `ntdll.dll` (x86_64 и i386) из того же коммита**, что и релиз Dormison, и наложить их на апстрим-тарбол. Unix-интерфейс не менять, чтобы `ntdll.so` и server protocol остались совместимыми. Если нужен unix-вызов, как в Proton, — собирать движок целиком (`package-engine.sh`, донор = апстрим-тарбол через `SEVO_LIVE_ENGINE`).
   - **B2 (запасной для x86_64): бинарный патч.** `resolve.py` автоматически находит место хука в Dormison (§2.3). Запускать его в CI на каждый релиз Dormison и публиковать хеши в манифесте моста, а не зашивать в Swift. Для i386 нужен другой cave (новая PE-секция или расширение последней) — иначе 32-битные игры без Steamworks.
   - **A (эксперимент):** старый подход Proton — `lsteamclient` под именем `steamclient(64).dll` в префиксе. Может ломать игры с DRM, которым нужен настоящий Windows steamclient (поэтому NotProton и качает `bins_win64`).
5. **`EngineUpdater`**: манифест → проверка подписи → канал beta/stable → загрузка с докачкой → проверка `.sig` и sha256 → распаковка в `runners/dormison-<tag>/` → наложение патча ntdll из п. 4 → smoke-test (`wine --version`, `wineboot --init` во временном префиксе) → переключение `current` → одна предыдущая версия для отката.
6. **`BridgeUpdater`**: lsteamclient (`.dll` x86_64/i386 + `.so` x86_64) и `steam.exe` собирать против **исходников Dormison того же коммита** (`engine-info.json → commit`). Это отдельный артефакт `bridge-dormison-<tag>-<rev>`, подписан моим Ed25519-ключом. `bridge-manifest.json` описывает совместимость движок ↔ мост ↔ патч ntdll. Новый движок не ставится, пока для него нет моста.
7. **`SignatureUpdater` + гейт обновлений Steam**: подписанный `signatures-manifest.json` в релизах форка. Steam не обновляется на билд без сигнатур (`UpdateBlock`), UI показывает «ждём поддержку билда N». Когда сигнатуры появились — блок снимается.
8. **CI (GitHub Actions, macOS-раннер)**:
   - расписание: новый тег Dormison → сборка ntdll-патча и моста → тесты → публикация с подписью;
   - расписание: свежий macOS Steam → `anchorcheck` → публикация сигнатур или issue;
   - релиз приложения: подпись + Sparkle appcast с моим `SUFeedURL`/`SUPublicEDKey`.
   Ключи — только в GitHub Secrets.
9. **Рендереры**: DXMT по умолчанию для D3D10/11. D3DMetal — после импорта GPTK пользователем (экран «Импортировать Game Porting Toolkit»). **Mullion** (https://github.com/dttdrv/mullion, LGPL, D3D10/11/12 на Metal поверх DXMT, только 64-битные игры, M3+, macOS 15+, pre-release) — **экспериментальный рендерер на игру, по умолчанию выключен**. Устанавливается в отдельную папку (раскладка как у DXMT: `x86_64-windows`, `x86_64-unix`) и подключается через `WINEDLLPATH_PREPEND`/оверрайды, а не через перезапись файлов движка. Версия и sha256 закреплены, в идеале сборка из исходников в моём CI.

## 5. Фазы и критерии приёмки

Фазы 1–6 — по этому файлу (для Фазы 6 плюс правка из docs/ROADMAP.md §3). Старое описание Фазы 7 отменено: вместо него Фазы 7A–7D, 8 и 9 из docs/ROADMAP.md. Общие правила §7 действуют для всех фаз. Если ROADMAP противоречит CLAUDE.md в описании фаз — главнее ROADMAP; в правилах безопасности — главнее CLAUDE.md.

**Фаза 0 — разведка (без правок кода).** Прочитай файлы из §2.1. Составь `docs/MIGRATION_PLAN.md` (файл → что от CrossOver → что делаем) и `docs/RISKS.md`. Покажи мне до правок.

**Фаза 1 — SPIKE «go / no-go» на моём Mac (M4 Pro).** Минимальные грязные правки в отдельной ветке `spike/dormison`, без UI и без автообновления:
1. Распаковать `dormison-b1` в `runners/dormison-b1`, `current` → туда. В `compat_run.sh` поменять пути на §2.2, `WINEMSYNC=1`.
2. Собрать мост против исходников Dormison коммита `52c2a4b918d6`.
3. Наложить x86_64-патч ntdll (B2 через `resolve.py`/`apply.py` — самое быстрое).
4. Проверить на 3 играх: 64-битная со Steamworks-ачивками, DX11-игра (DXMT), игра, проверяющая Steam при старте.

Критерии GO (каждый с доказательством из логов или скриншотом):
- Steam Play-опция видна в macOS Steam, игра стартует.
- В логе загрузки видно, что `lsteamclient` загружен и трамплины поставлены, ачивка или статистика работает.
- `WINEMSYNC=1` в логе, нет зависаний steam.exe-шима при выходе из игры.
- Окно игры нативное: меняет размер с сохранением разрешения, уходит в нативный полноэкранный режим и выходит из него.
- Оверлей Steam (overlay-shim) не конфликтует с презентером Dormison. Если конфликтует — описать.

NO-GO по любому пункту — остановись, опиши причину и варианты. Дальше не идём, пока я не решу.

**Фаза 2 — EngineProvider, профиль Dormison, UI настроек игры.** Критерий: `make app` собирается, `make app-tests` зелёные (тесты CrossOver заменены тестами Dormison), настройки из UI попадают в `.sevo/*.env` и действуют на следующем запуске.

**Фаза 3 — lsteamclient «по-взрослому»** (B1, или B2 + решение для i386). Критерий: работает и 64-битная, и 32-битная Steamworks-игра.

**Фаза 4 — EngineUpdater.** Тесты: поддельный манифест, поддельный тарбол, несовпадение sha256, нет сети, прерванная загрузка, откат, попытка обновления во время игры.

**Фаза 5 — BridgeUpdater, SignatureUpdater, гейт Steam.** Тесты: несовместимая пара движок/мост, билд Steam без сигнатур, появление сигнатур.

**Фаза 6 — CI и Sparkle.** `docs/RELEASING.md`: генерация ключей, секреты, dry-run на теге.

**Фаза 7 — GPTK, Mullion (эксперимент), онбординг, чистка.** Онбординг: Rosetta → движок → Steam → готово. `grep -ri crossover` даёт только `NOTICE`, документацию и атрибуцию msync. README.

## 6. Как работать

- Фаза 0 — только чтение и документы в `docs/`, жди моего «ок». Фаза 1 — после сборки жди моего «GO» по ручной проверке игр.
- Маленькие коммиты. После каждой фазы — тесты и отчёт: что сделано, что проверено, что не удалось.
- Не выдумывай API Dormison, Steam, Mullion — проверяй по исходникам и логам. Если чего-то не знаешь — скажи и предложи, как проверить.
- Если этот файл противоречит реальному коду — верь коду и сообщи о расхождении.

## 7. Автономный режим (я часто не у компьютера)

Рабочие папки: `~/Projects/NotProton` (форк, теперь Lullaby; папку можно переименовать в `~/Projects/Lullaby`), `~/Projects/dormison` (мой форк Dormison, клон без блобов), `~/Projects/sevoflurane` (эталон, только чтение).

1. **Журнал.** Веди `docs/PROGRESS.md`: дата и время, фаза, что сделано, что дальше, ссылки на коммиты. Обновляй после каждого заметного шага. Новая сессия должна продолжить работу, прочитав только `CLAUDE.md` и `docs/PROGRESS.md`.
2. **Не простаивай.** Если шаг заблокирован, запиши проблему в `docs/BLOCKERS.md` (что нужно от меня, точная команда или действие) и переходи к следующей незаблокированной задаче той же фазы. Останавливайся, только когда незаблокированной работы не осталось.
3. **Контрольные точки — только человек:** одобрение плана Фазы 0; ручная проверка игр в Фазе 1 (подготовь `docs/SPIKE_TEST.md` — пошаговую инструкцию «для чайника» с ожидаемым результатом каждого шага и местом, где смотреть логи); создание ключей подписи и секретов GitHub в Фазе 6 (подготовь инструкцию в `docs/RELEASING.md`, ключи сам не создавай). Дойдя до контрольной точки, заверши остальную работу фазы, отправь уведомление на телефон и жди.
4. **Не устанавливай системные инструменты сам**: никаких `sudo`, `curl | bash`, `brew install`. Если чего-то не хватает — запиши в `BLOCKERS.md` точную команду для меня. Python-пакеты — только в виртуальное окружение внутри проекта (`.venv`, добавить в `.gitignore`).
5. **Git:** работай в ветке `dormison` (и `spike/dormison` для Фазы 1), пушь только в свой `origin`, никогда не делай force push и не трогай `main` апстрима. Перед рискованной правкой — коммит. Секреты и ключи никогда не коммить.
6. **Ничего не удаляй вне репозиториев**, кроме собственных временных файлов сборки. Данные Steam, префиксы и `~/Library/Application Support/lullaby` меняй только так, как требует задача, с резервной копией рядом.
7. **Сборки и тесты** запускай сам и прикладывай в журнал код выхода и последние строки вывода. Не пиши «готово» без проверки.
8. **Тесты с играми без меня** — только то, что можно сделать без интерфейса Steam: запуск через `open steam://rungameid/<appid>`, чтение логов, `screencapture` для скриншотов. Всё, что требует кликов в Steam, — в `SPIKE_TEST.md` для меня.

## 8. Требования пользователя (из ручных тестов)

Требования, которые появились по ходу проверок. Каждое — обязательное, если ниже не сказано иное.

**Установка в Steam (Status в NotProton.app), 2026-10-06:**
1. Сравнивать установленное в Steam.app и в `notproton/` (dylib, `compat_run.sh`, мост) со встроенным в приложение по хешу или build id, а не только по номеру версии.
2. Если отличается — в Status «Update available» и кнопка Update. Она сама закрывает Steam (с предупреждением), ставит новое и предлагает открыть Steam.
3. Кнопка Reinstall доступна всегда — на случай, если что-то сломалось.
4. В Status видно build id и дату установленного патча.
5. Тесты на сравнение версий; запись в `app.log` при установке.
6. Repair и Remove не трогать.
7. Steam закрывать мягко (`steam://exit`, Quit через AppleEvent), ждать до N секунд. Если не закрылся — сообщение «закройте Steam вручную» и кнопка «Повторить». Тест на это.

**Конфиги игр (правило владельца, 2026-10-10):**
- NotProton и агент **не меняют файлы настроек самих игр** (`config.ini`, `*.cfg`, реестр игры, сохранения): только предлагают и пишут шаги для игрока. Для замеров — тоже не менять; если без этого никак, спросить.
- Свои настройки NotProton (каталог, `.sevo/*.env`, реестр Wine вроде `Mac Driver`) — можно, как раньше.

**Проверки:**
- 32-битные игры: живую проверку пропускаем, у пользователя таких игр нет. i386-путь покрыт `test-b1.sh`, кандидат на будущее — Alien Swarm (630), `docs/BACKLOG.md` п. 11.
- Онлайн-игры с VAC не запускать (Deadlock — только до меню).
- Растягивание картинки при меньшем разрешении: включать по умолчанию только то, что проверено и безопасно (`docs/BACKLOG.md` п. 9).

