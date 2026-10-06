# PROGRESS — журнал работ

Новая сессия: прочитай `CLAUDE.md`, затем этот файл сверху вниз; открытые вопросы — в `docs/BLOCKERS.md`.

---

## 2026-10-06 01:05 CEST — Подготовка и Фаза 0 (разведка)

**Состояние:** Фаза 0 завершена и **ждёт одобрения** (контрольная точка). Код проекта не менялся, коммит содержит только `docs/`.
База: ветка `dormison` @ `eb11a54` (= upstream `main` v1.0.2 + `CLAUDE.md`).

### 1. Инструменты (проверено)

| Инструмент | Версия / путь | Статус |
|---|---|---|
| Xcode | 27.0 (27A266a), `xcode-select` → `/Applications/Xcode.app`; Swift 6.4; macOS SDK 27.0 | ок (CI делает `sudo xcode-select`, локально не нужно) |
| mingw-w64 | 14.0.0_3, `x86_64-`/`i686-w64-mingw32-gcc` 16.2.0 | ок |
| bison | 3.8.2 (brew, keg-only `/opt/homebrew/opt/bison/bin`; системный 2.3 — скрипты ставят brew-версию первой в PATH) | ок |
| flex | 2.6.4 | ок |
| autoconf | 2.73 | ок |
| cmake | 4.4.4 (Dobby собирается без правок) | ок |
| python3 | 3.14.8 (Homebrew) + capstone 5.0.7 (уже стоит, `.venv` пока не понадобился) | ок |
| gh | 2.102.0, вход как `Ruslan-Ukraina`, scopes `repo, workflow` | ок |
| Rosetta 2 | `oahd` работает, `arch -x86_64` запускается | ок |
| shellcheck, ninja, meson | есть | ок |
| pkg-config, automake, llvm/lld | нет | не блокирует, см. `BLOCKERS.md` |

### 2. Сборка неизменённого NotProton по шагам `.github/workflows/app.yml`

Логи — в scratchpad сессии (не в репозитории). Все команды запускались из корня репозитория.

| Шаг workflow | Команда | Код выхода | Последние строки |
|---|---|---|---|
| Clone Dobby at the pinned commit | `git clone --no-checkout … vendor/dobby && checkout 5dfc8546…` | 0 | `HEAD зараз на 5dfc854 Fixup typo` |
| Build Dobby | `make dobby` | 0 | `[100%] Built target dobby_static` |
| Build the dylib | `make all` | 0 | `==> Built: out/notproton.dylib` (0 предупреждений) |
| Build the overlay shim | `make overlay-shim` | 0 | `Architectures in the fat file: out/overlay-shim.dylib are: x86_64 arm64` |
| Build helpers | `make iconmaker appinfo` | 0 | `==> Built out/appinfo` |
| Build the bridge | `make bridge` (~25 мин: клон wine-11.15, два configure, ntdll.so, lsteamclient, steam-shim) | 0 | `lsteamclient.dll i386 29872029 B 282c0b51…`, `x86_64 33885207 B 7a0c1cdd…`, `lsteamclient.so x86_64 3344808 B unsigned`, `arm64 4402352 B linker-signed`, `steam.exe x86_64 14238477 B ecb982b0…` |
| Stage the app payload | `make app-payload` | 0 | `==> Staged app payload in app/Sources/NotProtonApp/Resources/payload` |
| **Build the app** | **`make app`** | **0** | `codesign --verify --strict "out/NotProton.app"` / `==> Built out/NotProton.app (1.0.2)` |
| hermetic C suites | `make -s sigcheck` | 0 | `1790904859.json: 17 signatures, all referenced` |
| | `make -s callscheck` | 0 | `31 call-shape cases resolve as expected` |
| | `make -s webpatch-fixtures` | 0 | `gate table and 3 webpatch fixtures: anchors intact, drift refused` |
| | `make -s peicon-fixtures` | 0 | `hostile resources bounded, valid icon intact` |
| | `make -s panel-behavior` | 0 | `renders as expected, no stale arguments` |
| | `make -s spawn-env` | 0 | `steam_osx and Steam Helper keep the insert, every other child loses it` |
| | `make -s compatcheck` | 0 | `layout probes hold, the tool array walk is bounded…` |
| | `make -s compatsvc-check` | 0 | `the tool list, the none entry, the priorities…` |
| (вне CI) | `make -s overlay-shim-tests` | 0 | `overlay shim tests: 6 passed, 0 skipped` |
| Run the Swift tests | `make -s app-tests` | 0 | `Test run with 366 tests in 48 suites passed after 16.916 seconds.` |
| Package the app bundle | `ditto -c -k --keepParent out/NotProton.app out/artifact/NotProton.zip` | 0 | 17 МБ, sha256 `2c32787e71d3c38d…` |

Все артефакты сборки (`vendor/dobby`, `build/`, `scratch/`, `out/`, `payload/`, `steam-shim/proton-headers/`) входят в `.gitignore`. `git status` после сборки — только новая папка `docs/`.
Собранное приложение **не устанавливалось**, `make deploy` не запускался, Steam и `~/Library/Application Support/notproton` не трогались.

### 3. Фаза 0 — документы

- `docs/MIGRATION_PLAN.md` — «файл → что от CrossOver → что делаем», 15 находок сверх CLAUDE.md (§0), порядок фаз, архитектурные заметки, вопросы В1–В4.
- `docs/RISKS.md` — 24 риска с вероятностью, влиянием, мерами и проверкой.
- `docs/BLOCKERS.md` — что нужно от тебя.

Главное из разведки:
1. **Sparkle-фид указывает на апстрим** — собранный форк сам «обновится» до CrossOver-версии (R7).
2. В Dormison `WINEDLLPATH` не перекрывает DLL движка, перекрывает только `WINEDLLPATH_PREPEND` (0.6).
3. У Dormison свой механизм бандла игры: `SEVO_LOADER`/`SEVO_LOADER_TREE` (0.7), плюс ловушки, ведущие в Sevoflurane: `open sevoflurane://`, `/usr/local/bin/sevo` (0.8, 0.9).
4. Маркер `notproton-msync` переносит старый `WINEMSYNC=0` на существующие префиксы (0.2).
5. Настройки игры уже встроены в Steam через webpatch (0.4) — вопрос В3.
6. На диске есть следы прошлого эксперимента (`notproton/engines/dormison`, `bridge/engine`), их не трогал (0.13, В2).
7. `upstream/dev` опережает `main` на 16 коммитов (0.12, В1).

### 4. Уведомление

- `PushNotification` (пуш на телефон): **не отправлен**, оба раза ответ `Push not sent — mobile push is disabled in /config`. Как включить — в `BLOCKERS.md`, п. 3.
- Отправлено системное уведомление macOS (`osascript display notification`, код выхода 0) — «Фаза 0 готова и ждёт твоего «ок»…».
- Документы Фазы 0 отправлены файлами в сессию (`SendUserFile`, proactive), их видно и с другого устройства.

### Дальше

- Ждать «ок» по Фазе 0 и ответов В1–В4.
- После «ок» — Фаза 1: ветка `spike/dormison`, движок b1 в `runners/dormison-b1`, мост против Dormison `52c2a4b918`, B2-патч x86_64, `docs/SPIKE_TEST.md`.

---

## 2026-10-06 01:18 CEST — Ответы на контрольной точке Фазы 0

- План Фазы 0: **«Сначала правки»** — жду их текстом, Фазу 1 не начинаю.
- В1: база — `upstream/main` v1.0.2. В3: настройки в обоих местах, общий `.sevo/apps/<exe>.env`. Записано в `docs/DECISIONS.md`.
- В2: по твоему решению (подтверждено повторно после предупреждения) **удалены** `~/Library/Application Support/notproton/engines/dormison` (2,1 ГБ: `dormison-b1`, `dormison-b1-steam`, симлинки `current`/`previous`), `notproton/bridge/engine` (1,3 МБ) и опустевшая `notproton/engines`. Перед удалением проверил: процессов Wine нет, Steam не запущен, ничто в командных строках не ссылалось на эти пути.
- Последствие: установленный `notproton.dylib` в `/Applications/Steam.app` (от прошлого эксперимента, 3 ссылки на `engines/dormison`) больше не находит движок, поэтому Steam Play для Windows-игр не работает до развёртывания сборки Фазы 1.
- Открыто: правки к плану, вопрос В4 (Sparkle), включение пушей в `/config` (`BLOCKERS.md`).

---

## 2026-10-06 01:27 CEST — Правки к плану Фазы 0 приняты

- Твои итоговые решения записаны в `docs/DECISIONS.md`:
  - В1 — `main` v1.0.2, из `dev` ничего не переносим;
  - В2 — эксперимент удалён;
  - В3 — оба варианта, источник правды `.sevo/apps/<exe>.env`, панель в Steam — только рендерер;
  - В4 — Sparkle выключить уже в Фазе 1;
  - S1 — форк никогда не вызывает Sevoflurane.
- `docs/MIGRATION_PLAN.md` обновлён под эти решения: §0.4–0.13, строки 1.2–1.5, порядок Фазы 1, §3.4 заглушка `SEVO_CLI`, §4.
- `docs/RISKS.md`: обновлены R7 (Sparkle в Фазе 1), R9 (S1) и R16 (из `dev` ничего не берём).
- По S1 проверены исходники Dormison `52c2a4b918`. В движке ровно два вызова Sevoflurane:
  - `loader/main.c:204–205` — `open sevoflurane://play/<id>`;
  - `dlls/winemac.drv/cocoa_app.m:1165–1166` — `SEVO_CLI`, при пустом значении `/usr/local/bin/sevo`.

  Меню View вызывает его из пяти пунктов: `upscaler`, `filter`, `fps`, `fps-graph`, `windows`. Если `SEVO_CLI` задан, запасной путь не используется, поэтому для Фазы 1 хватит заглушки. Скрыть пункты без пересборки `winemac.so` нельзя.
- Расхождение: ты пишешь, что `pkgconf` установлен, но его нет: `/opt/homebrew/bin/pkg-config` отсутствует, `brew list --versions pkgconf` пуст. Фазу 1 не блокирует, команда — в `BLOCKERS.md`.
- Пуши, по твоим словам, включены; тестовую отправку не делал — ты у терминала.
- Фазу 1 не начинаю: ты запускаешь её отдельной целью.

---

## 2026-10-06 02:45 CEST — Фаза 1 (spike): сборка готова, ждёт ручной проверки игр

**Состояние:** ветка `spike/dormison`, контрольная точка — ручная проверка игр по `docs/SPIKE_TEST.md` и твоё GO / NO-GO.
Решения — `DECISIONS.md` (P1-1…P1-10, S1-impl, B4-impl), риски — `RISKS.md` (статусы и новые R25–R32).

### Что сделано и чем проверено

| Шаг | Команда / коммит | Код выхода | Результат |
|---|---|---|---|
| Движок b1: загрузка и проверка | `engine/fetch-dormison.sh --activate` (`fef092c`) | 0 | подписи `engine.json` и тарбола валидны (ключ `7uDuIZdC…`); sha256 `23e25aa4…235de` и размер 232989872 совпадают с манифестом; подделанный манифест отвергнут (код 1); `5004 entries match engine-manifest.json (dormison-b1, commit 52c2a4b918d6)`; `runners/current -> dormison-b1` |
| Загрузчики движка | `codesign -d --entitlements -` | — | оба ad-hoc, без hardened runtime и entitlements (R4 закрыт); `wine --version` → `dormison-b1 (Staging)` |
| Мост против Dormison `52c2a4b918` | `make bridge` с `MAKEFLAGS=-j14` (`7dd49cb`) | 0 | worktree `scratch/dormison-src`; `register-components.diff` лёг со смещениями (R10 закрыт); `lsteamclient.dll` i386 29876125 B `e6c7994f…`, x86_64 33885207 B `7ba78c7c…`; `lsteamclient.so` x86_64 3346128 B unsigned; `steam.exe` 14242573 B `cc39e199…`; все ntdll-импорты `.so` есть в `ntdll.so` движка; 2 мин 11 с |
| Патч ntdll x86_64 (B2) | `ntdll-patch/patch-dormison.sh` (`3e51102`) | 0 | хук `0x52f36`, cave `0x82760` (2208 Б), payload 864 Б `b363a77d…`; `verify.py` → `PASS`; чистый `4af19ee6…` → пропатченный `dbc4099e…` (детерминированно); `link.ld` апстрима не линковался из-за `//`-комментария — исправлено |
| Патч под Wine | `ntdll-patch/tests/` | 0 / 1 | с патчем: `RESULT: redirected to lsteamclient, DllMain suppressed`; контроль без патча: `not redirected` |
| Защита `rm` | по твоему указанию (`aba3265`) | — | все `rm`/`find -delete`/`rsync --delete` с переменными — через `${var:?}`; правило записано в память |
| Запуск игр на Dormison | `compat_run.sh` (`225d6f4`, `cc2f4ff`) | — | пути движка, `WINEMSYNC=1`, `.sevo/bottle.env`, DXMT через `WINEDLLPATH_PREPEND` + `winemetal.dll` в префиксе, `SEVO_LOADER`, защиты S1; имя «Dormison (NotProton)» |
| Приложение | `f557714`, `3353a78`, `21943fe` | — | Sparkle выключен (В4), статус «Dormison b1», `PrefixTools` под Dormison, мост по sha256 (ошибка апстрима, R28), `--install-into-steam` |
| C-тесты | `runcheck scriptcheck sigcheck callscheck webpatch-fixtures peicon-fixtures panel-behavior spawn-env compatcheck compatsvc-check overlay-shim-tests` | 0 у всех | `overlay shim tests: 6 passed, 0 skipped`, `spawn live: …` тоже 0 |
| Swift-тесты | `make app-tests` | 0 | `Test run with 367 tests in 48 suites passed` |
| Сигнатуры Steam | `make anchorcheck` | 0 | билд клиента 1788652215: `17 anchors resolved, 0 unresolved`, vptr OK, `0 wrong` |
| **`make app`** | `make app` | **0** | `codesign --verify --strict` ok; `==> Built out/NotProton.app (1.0.2)` |
| **Установка** | `ditto` в `/Applications/NotProton.app`, `NotProtonApp --install-into-steam` | 0 | `NotProton 1.0.2 in Steam, Steam was not running`; `components complete (17 of 17)`; dylib в Steam.app = `out/notproton.dylib`, подпись ok; мост совпадает с payload по байтам |

### Проверки без Steam (имитация запуска в `scratch/sim`)

- `compat_run.sh` с поддельными `STEAM_COMPAT_*` (данные Steam не трогались): префикс создан Dormison, `sync: WINEMSYNC=1`, `bottle.env` записан, `pointed ruslanukraina at steamuser`, `runner: x86_64 ntdll is the patched copy`, `renderer: dxmt`, `SEVO_LOADER` для `steam.exe` и игры, сессия завершилась, процессов Wine не осталось.
- В шиме `steam.exe` детур сработал: `lsteamclient.dll … builtin` загружен прямо перед `steamclient64.dll` Valve. Дальше — ожидаемый `assert`: без запущенного Steam `lsteamclient` не находит `steamclient.dylib` (R32).
- Дочерний процесс: `sevo:loader … exe=load_steamclient.exe loader=bundle=…/Contents/MacOS/wine` (R8).
- DXMT: `engine/tests/d3d11_probe.c` → `D3D11CreateDevice hr=0 feature level 0xb000`, `adapter: Apple M4 Pro`, `winemetal.dll loaded`, `sevo:gfx … renderer=dxmt`, и в 64, и в 32 бит. Без каталога рендерера wined3d даёт только 9_3 (R31). Первая версия не находила `winemetal.dll` (R30) — исправлено в `cc2f4ff`.
- S1: заглушка `SEVO_CLI` отвечает 0 и только пишет строку в лог; лаунчер без программы и с `-psn_…` выходит; Sevoflurane.app не запускался.
- `engine/spike-check.sh` (`bc54ecb`) на имитации: 8 ok; 2 FAIL ожидаемы без Steam (`steamclient_init`, игра не стартовала).
- Артефакты имитации (бандл `launchers/app-4000000001`) удалены и сняты с регистрации в LaunchServices.

### Что изменено вне репозитория (с резервными копиями)

- `~/Library/Application Support/notproton/runners/dormison-b1` (+ `current`) — движок; в нём заменён только `x86_64-windows/ntdll.dll`, исходный — `ntdll.dll.notproton-orig`.
- `notproton/bridge` — новый мост; прежний сохранён в `notproton/bridge.bak-20261006-spike`.
- `notproton/renderers/dxmt` (ссылки), `notproton/notproton-sevo` (заглушка).
- `/Applications/NotProton.app` — установлен впервые.
- `/Applications/Steam.app`: `notproton.dylib` заменён, подпись ad-hoc обновлена установщиком. Прежние `Info.plist` и dylib — в `notproton/backups/spike-20261006/` и копией в `scratch/backups/spike-20261006/`.

### Найдено по ходу (подробности в `RISKS.md`)

- На Mac две копии Steam, иконка в Dock открывает копию без NotProton (R25).
- В процессы игры попадает чужой Vulkan из `/usr/local` (R26).
- Ошибка апстрима: мост раскладывался по размеру, и старый `lsteamclient.so` оставался на месте (R28) — исправлено.
- Dormison не грузит builtin без файла в префиксе (R30); wined3d даёт DX11 только уровня 9_3 (R31).
- Отклонено тобой: удаление с `"$users/$mac_user"` — переделано на `${var:?}` везде (`aba3265`).

### Пуш и уведомление (02:44 CEST)

- Ветка запушена: `git push -u origin spike/dormison` → `* [new branch] spike/dormison -> spike/dormison`, код 0.
- `PushNotification`: **не отправлен** — `Push not sent — mobile push is disabled in /config`. Как включить — `BLOCKERS.md`, п. 2.
- `docs/SPIKE_TEST.md` отправлен файлом в сессию (`SendUserFile`, доставлен), его видно с другого устройства.
- Системное уведомление macOS (`osascript display notification`) — код 0.

### Дальше

- Ты: `docs/SPIKE_TEST.md` → GO / NO-GO.
- После GO: Фаза 2 (`EngineProvider`, профиль `.sevo` из UI, замена тестов CrossOver).

---

## 2026-10-06 04:30 CEST — Фаза 1 закрыта: GO

**Состояние:** Фаза 1 пройдена — твоё решение GO после ручной проверки. Фазу 2 не начинаю, пока ты не запустишь её целью.
Ветка `spike/dormison` — эталон, её не удаляю. Код, движок, данные Steam и префиксы в этой записи не менялись, только `docs/`.

### Твоя проверка: 4 игры

| Игра | spike-check | Итог |
|---|---|---|
| PEAK (3527290) | 9 ok / 1 FAIL — финал лога | работает: окно, полный экран, оверлей, меню View; ~78 fps при 3024×1890 |
| ETS2 (227300) | 10 ok / 0 FAIL | работает, HDR, 78–120 fps, уведомления оверлея |
| Deadlock (1422450) | 7 ok / 3 FAIL — 2 интерфейса lsteamclient; wineserver и Sevoflurane.app твои | меню и матч с ботами, ~60 fps |
| RE9 (сторонний ярлык) | 9 ok / 1 FAIL — финал лога | DX12: «Unsupported graphics card», ожидаемо |

Полные таблицы и решения — `DECISIONS.md`: P1-GO, S1-check, VAC, DX12, spike-ref, backlog и раздел «Итоги Фазы 1».

### Что я разобрал по логам после отчёта

Только чтение, игры не запускал.

- **Финал лога** — две причины, обе в коде апстрима (BACKLOG 1):
  - при остановке из Steam скрипт не выходит по сигналу, уходит в `wait_prefix_idle`, и Steam убивает его до финала;
  - при обычном выходе финал пишется через ~11 секунд после того, как Steam вернул «Играть».
- **Deadlock** рисовал, скорее всего, через DXMT. Vulkan записан в `boot.vcfg` при выходе и включится со следующего запуска (BACKLOG 4).
- **Интерфейсы `SteamNetworkingSocketsSerialized005` и `SteamAppDisableUpdate001`** отсутствуют и в закреплённом Proton `164e0ccd`, и в текущих ветках Proton на 2026-10-06 (BACKLOG 2).
- **Sevoflurane:** его демон трогает только процессы своих бутылок, мы — только свой префикс. Ошибался `spike-check.sh`. Найдено слабое место — имя msync из одного inode (BACKLOG 3, R34).
- **RE9:** встроенный `d3d12` Wine вместе с `dxgi` от DXMT — устройство D3D12 не создаётся (BACKLOG 5).
- **`spike-check.sh` даёт ложный ok** в п. 5 (DXMT) для игры без единого кадра (BACKLOG 4).
- **Повторный `spike-check.sh` в 04:25** по тем же логам: PEAK 10/0, ETS2 10/0, Deadlock 9/1 (только интерфейсы), RE9 9/1 (финал).

### Бэклог (подробно — `docs/BACKLOG.md`)

| # | Задача | Фаза |
|---|---|---|
| 1 | Run-скрипт не пишет финал сессии (PEAK, RE9) | 2 |
| 2 | `SteamNetworkingSocketsSerialized005`, `SteamAppDisableUpdate001` в lsteamclient | 3 |
| 3 | Сосуществование с Sevoflurane: наш wineserver против чужого, префиксы не пересекаются | 2 |
| 4 | Производительность (PEAK, Deadlock до 120 fps) и какой API рисует Deadlock | после 7 |
| 5 | DX12-игры (RE9): D3DMetal / Mullion | 7 |
| 6 | Модальные окна ошибок не блокируют автотесты | 2 |
| 7 | Риски VAC от хука steamclient (добавил я из отчёта) | 3, предложение |

### Документы

- `docs/BACKLOG.md` — новый.
- `docs/DECISIONS.md` — шесть решений и «Итоги Фазы 1».
- `docs/RISKS.md` — статусы R5, R6, R26, R31, R32 (закрыт), новые R33 (VAC) и R34 (msync).
- `docs/BLOCKERS.md` — ждём цель Фазы 2; что учесть, пока играешь на spike-сборке.

### Пуш и уведомление (04:33 CEST)

- `git push origin spike/dormison` → `82ae660..abbc5fd  spike/dormison -> spike/dormison`, код 0.
- `PushNotification`: **не отправлен** — `Push not sent — mobile push is disabled in /config`, как и на прошлых контрольных точках (`BLOCKERS.md`, п. 2).
- `docs/BACKLOG.md` отправлен файлом в сессию (`SendUserFile`, доставлен), его видно с другого устройства.
- Системное уведомление macOS (`osascript display notification`) — код 0.

### Дальше

- Жду твою цель для Фазы 2.
- Как начать Фазу 2, предлагаю так: fast-forward `dormison` на `spike/dormison`, `spike/dormison` не трогать (`BLOCKERS.md`, п. 1).
- Первые пункты бэклога в Фазе 2: 1, 3 и 6, плюс ложный ok в п. 5 `spike-check.sh`.

---

## 2026-10-06 10:12 CEST — `dormison` перемотан на `spike/dormison`

- По твоему указанию: `git fetch . spike/dormison:dormison` дал fast-forward `b0acfd8..2259474` (16 коммитов). `git push origin dormison` → `b0acfd8..2259474  dormison -> dormison`, код 0, без force push.
- Рабочая копия переключена на `dormison`. Коммит тот же, файлы не менялись.
- `spike/dormison` не тронут: `2259474` и локально, и в `origin`.
- Дальше работаю в `dormison`. Фазу 2 не начинаю — жду твою цель.

---

## 2026-10-06 — Фаза 2 начата (по «Продолжи»)

- BACKLOG 1 (часть run-скрипта): `terminate()` в `compat_run.sh` теперь игнорирует повторные сигналы, гасит префикс, пишет `=== termination signal, session ending ===` и выходит с кодом 143, не заходя в `wait_prefix_idle`.
- Тест: `dylib/tests/termcheck.sh` (подключён к `make runcheck`): вырезает обработчик из реального скрипта, шлёт два `TERM`; ждёт код 143, финальную строку, один `wineserver -k`. `make runcheck compatcheck` — код 0.
- Не сделано по п. 1: ожидание финала в `spike-check.sh`.
- Дальше: п. 3 (`spike-check.sh` и проверка «идёт ли игра» только по нашим префиксам), п. 6, ложный ok в п. 5, затем `EngineProvider` и окно «Настройки игры».

## 2026-10-06 — Фаза 2: настройки игры, пункты 1 и 3 бэклога

- **Бэклог 1** закрыт: `terminate()` (коммит `a737833`) и ожидание финала в `engine/spike-check.sh` до 30 с; остановка из Steam считается чистым завершением.
- **Бэклог 3** закрыт в коде: `spike-check.sh` считает «нашими» только Wine из `notproton/runners|launchers` и нашей `compatdata`, чужой Wine показывает отдельно без FAIL; Sevoflurane, запущенный до начала сессии, — ok, после старта — FAIL. Приложение: `SteamBundle.gameIsRunning` смотрит только наши пути (`Shell.processIsRunning(commandLineContaining:)`, тест). Живой проверки с открытым Sevoflurane не было.
- **Меню View переживает перезапуск:** заглушка `notproton-sevo` пишет `upscaler/filter/fps/fps-graph/windows` в `.sevo/apps/<exe>.env`; имя exe — в `.sevo/game-exe` (пишет run-скрипт). Тест `dylib/tests/stubcheck.sh` в `make runcheck`.
- **Окно «Настройки игры»** (`Views/GameSettingsView.swift`, кнопка в панели и пункт контекстного меню Prefixes): изменяемое окно, апскейлер (off/lanczos/MetalFX), финальный фильтр, FPS, график, raw mouse, удержание курсора, лимит ядер, msync+ (отладка через `notproton-msync`), подсказка (i) у каждого пункта. Модель — `Model/GameSettings.swift`, 5 тестов.
- Проверки: `make runcheck compatcheck` — 0; `make app-tests` — 0, 373 теста; `make app` — 0, `out/NotProton.app`.
- **Не сделано в Фазе 2:** выбор рендерера (DXMT/DXVK/wined3d), шейдерные апскейлеры Anime4K/CuNNy (нужен SEVO_SHADER_DIR), `EngineProvider`, замена тестов CrossOver, бэклог 6 (сторож первого кадра), ручная проверка окна на реальной игре (нужен клик в приложении).

## 2026-10-06 — Фаза 2: EngineProvider

- `Model/EngineProvider.swift`: протокол `EngineProvider` (`wineloader`, `wineserver`, `unixLoader`, `dllPaths(arch:)`, `version`, `capabilities`) и `DormisonEngine` (раскладка `wine/bin/wine`, `wine/lib/wine/<arch>-windows`, `engine-info.json`). 5 тестов.
- `notproton-engine.env` (в реальной папке движка, пути этой папки): пишет приложение при старте (`DormisonEngine().ensureEnvironmentFile()` в `App.init`); `compat_run.sh` читает его как данные (`engine_env_get`, без `source`) и берёт загрузчик, сервер и unix-каталог оттуда; без файла — прежние жёсткие пути. Проверено вручную: значение с апострофом читается верно.
- `PrefixTools.layout` и `RunnerStore` берут раскладку и версию у `DormisonEngine`.
- `make runcheck compatcheck` — 0, `make app-tests` — 0 (378 тестов), `make app` — 0.
- Не сделано: удаление CrossOver-кода (`CrossOverSource/License`, `RunnerInstaller/Setup/Patcher`, `SupportedRunner`, FEX-ресурсы) и замена их тестов; установка движка из тарбола (`EngineSetup`) — Фаза 2/4; `dllPaths` пока не используется run-скриптом (WINEDLLPATH = только мост, как в спайке).

## 2026-10-06 — Фаза 2 завершена (кроме ручной проверки)

**Сделано** (коммиты `a737833` … последний в ветке `dormison`):
- CrossOver убран из приложения: удалены `CrossOverSource/License`, `RunnerInstaller/Setup/Patcher/Store`, `NtdllPatcher`, `SupportedRunner`, ресурсы `detour*.bin`, 8 файлов тестов. Вместо них — `EngineStore` (состояние `current`, список полных движков, атомарное переключение и удаление неактивных), строки «Engine» в Status, `DormisonEngine` в `PrefixTools`/`PrefixRebuild`.
- `compat_run.sh`: ветка aarch64/FEX убрана (префикс всегда x86_64), сообщения без CrossOver, рендерер и Retina берутся из параметров запуска → `.sevo/apps/<exe>.env` → `bottle.env`.
- Панель в Steam — только список рендереров (`NOTPROTON_RENDERER`); тесты панели переписаны (`panel-behavior`, `webpatch-fixtures`).
- «Настройки игры»: добавлены рендерер, Retina, Metal HUD, AVX.
- Бэклог 1 (финал лога по сигналу + ожидание в `spike-check.sh`), 3 (только наши процессы Wine, Sevoflurane по времени старта), 6 (сторож первого кадра `NOTPROTON_WATCHDOG`, тест `watchdogcheck.sh`), ложный ok в п. 5 `spike-check.sh` — закрыты в коде.
- Решения P2-1…P2-4 — `DECISIONS.md`.

**Проверено** (все с кодом 0): `make runcheck compatcheck scriptcheck panel-behavior webpatch-fixtures sigcheck anchorcheck sigdb-fixtures overlay-shim-tests`; `make app-tests` — 278 тестов; `make app` — `out/NotProton.app`. Запуск собранного приложения на 5 секунд записал `runners/dormison-b1/notproton-engine.env` с верными путями.

**Не проверено / не сделано:**
- В Steam стоит старый dylib со встроенным скриптом (до этих правок). Новые правки `compat_run.sh` попадут туда после кнопки Install в приложении или `make dylib-install`. Игры с новым скриптом не запускал.
- Окно «Настройки игры» и строки Engine глазами не смотрел (нужен клик в приложении) — в `SPIKE_TEST.md` для тебя.
- Выбор D3DMetal в рендерерах — после импорта GPTK (Фаза 7), Anime4K/CuNNy — когда движок получит каталог шейдеров (`SEVO_SHADER_DIR`).
- Установка движка из приложения — Фаза 4 (P2-2).
- Остатки слова crossover: имена внутри C-кода dylib (P2-3), миграция профиля `users/crossover`, тесты миграции, документация — Фаза 7.

## 2026-10-06 ~12:00 CEST — ручная проверка Фазы 2 на PEAK: разбор логов

Твой отчёт: 8.1 ok, 8.3 ok (старую строку `WINEMSYNC=1` из параметров запуска ты убрал), 8.4 окно тянется, нативный полноэкранный режим работает. По Retina и fps повторного запуска в отчёте остались незаполненные поля.

- **Остановка из Steam (8.5) — подтверждено.** Две сессии PEAK:
  - 11:30:58 — Steam снял run-скрипт в 11:33:07 с кодом **143** (`gameprocess_log.txt`); в run-логе `=== termination signal received, killing wine prefix ===` → `=== termination signal, session ending ===`;
  - 11:39:32 — то же в 11:43:50, код 143, та же пара строк.
  - Повторных сигналов и `wait_prefix_idle` после сигнала больше нет. `engine/spike-check.sh 3527290` — **10 ok, 0 failed**; процессов Wine не осталось.
- **Меню View → файл игры:** в 11:31:54 заглушка записала `SEVO_FPS=1` в `.sevo/apps/peak.exe.env`, во второй сессии он подхватился.
- **Retina из «Настроек игры» не применилась:** в обеих сессиях `video: RetinaMode=0`, в `peak.exe.env` нет `NOTPROTON_RETINA`. Значит, настройка не была сохранена в файл (не нажат Save, или ошибка записи). Сохранение пока ничего не писало в лог, поэтому причину не различить. Добавил запись `game settings <appid> <exe>: …` в `app.log` при сохранении и при ошибке; `make app-tests` — 278 ok, `make app` — 0. Нужен повтор: Retina = On → Save → запуск → в run-логе `video: RetinaMode=1`.
- **Производительность:** окружение сессий Фазы 1 и 2 одинаково (msync+ включён, DXMT, Retina выкл.). Подробно — `BACKLOG.md` п. 10.
- **BACKLOG:** добавлены п. 8 (exclusive fullscreen; в Dormison есть `ResizableWindows=window` и `EmulateModeset`, готового «в нативный полноэкранный режим» нет), п. 9 (половинное разрешение и MetalFX — после Фазы 7), п. 10 (регрессия fps — разбор логов).

## 2026-10-06 ~12:15 CEST — **Фаза 2 закрыта** (твоё решение)

- Retina из «Настроек игры» работает: сохранение в 12:06:07 (`app.log`: `game settings 3527290 peak.exe: SEVO_FPS=1 NOTPROTON_RETINA=1 …`), сессия 12:06:16 — `video: RetinaMode=1`, финал `=== termination signal, session ending ===`.
- PEAK, Retina, полноэкранный режим по зелёной кнопке: 74–80 fps, 1% low 45–58 — как в Фазе 1. BACKLOG п. 10 закрыт.
- BACKLOG п. 9 дополнен: при меньшем разрешении в игре — чёрные рамки (presenter=off); кандидаты — Upscaler «Final filter only» / MetalFX + Resizable window «Every window».
- Дальше — Фаза 3 (lsteamclient «по-взрослому»: B1 или B2 + i386), жду твоего «начинай».

## 2026-10-06 ~13:30 CEST — Фаза 3: B1 и интерфейсы готовы, жду ручной проверки

**Сделано**
- **B1 (P3-1).** Хук steamclient → lsteamclient в `dlls/ntdll/loader.c` форка Dormison: ветка `notproton/b1-steamclient`, коммит `1e0b5ba000` поверх `52c2a4b918`, запушен в `origin` форка. Копия патча — `ntdll-patch/b1/0001-…patch`. Скрипты:
  - `build-b1.sh` (`--check-base`) собирает PE `ntdll.dll` x86_64 и i386;
  - `test-b1.sh` проверяет хук на APFS-клоне движка во временном префиксе;
  - `install-b1.sh` (`--restore`) ставит в движок и мост с резервными копиями.
- **Воспроизводимость (R2 закрыт).** Релиз собран mingw GCC 16.2.0, как у нас. Непропатченная сборка совпадает с релизной по размеру до байта, а по коду — инструкция в инструкцию.
- **Тест хука:** x86_64 и i386 — `CreateInterface` и точка входа steamclient ведут в lsteamclient, 40 экспортов. С релизной `ntdll.dll` тест падает, причём i386 `steamclient.dll` без B1 вообще не грузится (ошибка 126). R1 закрыт кодом.
- **B1 в движке:** `runners/dormison-b1`, x86_64 `33bca058…`, i386 `e0d5f658…`. Рядом `.notproton-orig` (релиз) и для x86_64 `.notproton-b2` (спайк). Копии — в `bridge/wine/{x86_64,i386}-windows/` и `bridge/wine/b1.json`.
- **Интерфейсы (P3-2).** `lsteamclient/add-interfaces.py` (из `fetch.sh`) добавляет `SteamNetworkingSocketsSerialized005` и `SteamAppDisableUpdate001`. `lsteamclient/tests/ifacecheck.sh` на живом клиенте: оба создаются в x86_64 и i386, `GetSTUNServer` → `162.254.197.38:3478`. Мост обновлён (`build.sh --install`, теперь только в мост, P3-3); прежние файлы — `scratch/backups/bridge-pre-p3`.
- **`compat_run.sh`:** `verify_runner` проверяет обе архитектуры и пишет `(B1)`.
- **`spike-check.sh`:** п. 2 засчитывает запись B1 для `steamclient64.dll` и `steamclient.dll`.
- **Манифест мостa:** добавлен `patched wine/i386-windows/ntdll.dll`.
- **VAC (R33)** оценён в `RISKS.md`, раздел «R33: VAC».
- **32-битная игра** для проверки — The Binding of Isaac: Rebirth (250900), `isaac-ng.exe` i386 + `steam_api.dll`. Сейчас она только в `~/GameHub`; ставить через Steam с принудительным Dormison (SPIKE_TEST §9.2).
- **SPIKE_TEST §9:** проверка PEAK, ETS2, Deadlock (только меню), Isaac и эксперимент п. 8 «Also borderless full screen» на PEAK.

**Проверки (все с кодом 0):** `make runcheck compatcheck scriptcheck panel-behavior webpatch-fixtures sigcheck anchorcheck sigdb-fixtures overlay-shim-tests`; `make app-tests` — 278 тестов; `make app` — `out/NotProton.app` (в payload новый lsteamclient с 005 и скрипт с проверкой B1); `test-b1.sh` и `ifacecheck.sh` — 0 FAIL.

**Не проверено:** игры. Это контрольная точка — ручная проверка по SPIKE_TEST §9. Новый dylib в Steam.app не ставил: Steam был открыт, а Install его закрывает. Это §9.0, для тебя.

**Пуш и уведомление (13:35 CEST).** `git push origin dormison` → `b9ee167..838a717`, ветка совпадает с `origin`. Ветка форка Dormison `notproton/b1-steamclient` запушена. `PushNotification`: `Push not sent — mobile push is disabled in /config` (как раньше, BLOCKERS). Системное уведомление macOS — отправлено. Жду проверки по SPIKE_TEST §9.

## 2026-10-06 ~12:55 CEST — Фаза 3: PEAK с B1 (сессия 12:49)

- `engine/spike-check.sh 3527290` — **10 ok, 0 failed** (код 0). Пункт 2: `steamclient64.dll: 40 exports and the entry point lead to lsteamclient.dll`, `[ok] the B1 loader hook led steamclient to lsteamclient`, ошибок lsteamclient нет. msync+ работает, DXMT нарисовал первый кадр (+7053 мс), сессия завершилась по сигналу, наших процессов Wine не осталось.
- В Steam всё ещё **старый dylib**: в run-логе `runner: x86_64 ntdll is the patched copy` без `(B1)` и без строки i386. Хук работает, потому что B1 уже стоит в `runners/dormison-b1`. Новый скрипт попадёт в Steam после SPIKE_TEST §9.0 (закрыть Steam → Install в NotProton.app).
- Висящий `winedevice.exe` (pid 55389, запущен 4 октября) — не наш, `spike-check` его не считает. Не трогал.
- Не проверено: достижения в оверлее (нужен глаз), ETS2, Deadlock, Isaac (32 бит), эксперимент §9.3.

## 2026-10-06 15:22 CEST — Фаза 3: PEAK запущен без тебя (`open steam://rungameid/3527290`)

- Первый кадр DXMT через 7,2 с, главное меню за ~40 с, 92 fps в меню, отсчёт «новий острів» из сети на месте. Снимки — в scratchpad сессии (`peak-b1.png`, `peak-menu.png`).
- В `notproton-wine.log`: `redirect_steamclient … steamclient64.dll: 40 exports and the entry point lead to lsteamclient.dll` (это трассировка C-хука B1), ошибок `Don't recognize interface` нет.
- Выход через Quit бандла (osascript): `bundle exited status=0` → `game exited status=0, killing wine prefix` → `session ending`.
- `engine/spike-check.sh 3527290` — **10 ok, 0 failed**.
- Не проверено: достижения в оверлее, ETS2, Deadlock, Isaac; в Steam всё ещё старый dylib (§9.0).

## 2026-10-06 15:30–15:37 CEST — Фаза 3: новый dylib в Steam, PEAK и ETS2 без тебя

- `make app` — 0. Установка: `out/NotProton.app/Contents/MacOS/NotProtonApp --install-into-steam` (то же, что Install; Steam закрыт установщиком) → `NotProton 1.0.2 in Steam, Steam was stopped, 2 bridge file(s) staged, 3 signature database(s)`, `components complete (18 of 18)`. arm64 LC_UUID dylib в Steam.app: был `43B5842E…`, стал `47B89F80…` (= сборка). Steam снова открыт, вход в аккаунт 15:33:11.
- **PEAK** (15:33): `runner: x86_64 … (B1)` и `runner: i386 … (B1)`, `redirect_steamclient … 40 exports`, уведомление оверлея Steam в окне, главное меню 84 fps, выход через Quit → `spike-check.sh 3527290` **10 ok, 0 failed**.
- **ETS2** (15:35): обе строки B1, `redirect_steamclient` ×2, главное меню с профилем, первый кадр DXMT +13,9 с, выход Quit → `spike-check.sh 227300` **10 ok, 0 failed**. У ETS2 `WINEMSYNC=1` всё ещё приходит из параметров запуска (старая строка, безвредно).
- Найдена причина, почему ты не мог обновить патч из приложения: состояние «Installed» считается только по `dylib.version` (номер версии 1.0.2), а не по самому dylib. Чиню (см. следующую запись).
- Для тебя (SPIKE_TEST §9): Isaac (§9.2), достижения в оверлее, Deadlock до меню, §9.3.

## 2026-10-06 ~15:45 CEST — Фаза 3: Update / Reinstall в NotProton.app (твой запрос)

- `Model/PatchComparison.swift` (P3-5): dylib в Steam.app — по LC_UUID, `run` — по sha256 с `compat_run.sh` (теперь в payload, `make app-payload`), мост и вспомогательные файлы — по sha256. Расхождение → `.outdated(deployed:bundled:stale:)` → «Update available», что именно устарело, build Steam против build приложения, кнопка **Update**.
- **Reinstall** — всегда в разделе Steam (`SteamInstaller.run(force:)`; headless: `--install-into-steam --reinstall`).
- Если Steam открыт — вопрос «Close Steam to install?»; после установки, закрывшей Steam, — кнопка **Open Steam**. Пока запущена наша игра — отказ (и в приложении, и в установщике).
- Установщик сразу пишет новый `run` в `compatibilitytools.d/notproton`, если папка есть.
- Status: `Build 47B89F80, installed 6 Oct 2026 at 15:32.`; `app.log`: `install: begin…`, `install: done version=… build=… patched=… stoppedSteam=…`, `state patch build=… installedAt=… stale=…`.
- Тесты: `PatchComparisonTests` (8), `SteamBundleTests` +3, `SteamInstallerTests` +3 (reinstall, run, отказ при игре), `InstallPayloadTests` — `compat_run.sh`. Repair и Remove не трогал.
- Проверки: `make app-tests` — 0, **292 теста**; `make app` — 0; `make runcheck compatcheck` — 0. Живая проверка: собранное приложение пишет `state steam=installed 1.0.2`, `state patch build=47B89F80 installedAt=2026-10-06T13:32:57Z stale=none`, на экране строка build и Reinstall (снимок смотрел).
- Не проверено: клики Update/Reinstall в окне (нужен ты, SPIKE_TEST §9.4a); вид «Update available» на живой системе — появится при следующей сборке с изменённым скриптом.

## 2026-10-06 ~16:45 CEST — Фаза 3: разбор твоей проверки (оверлей, CS:S), итог

- **Оверлей Steam (Shift+Tab)** работает — твоя проверка. В PEAK уведомление оверлея видно и на моём снимке 15:33.
- **CS:S (240) — 64-битная.** Во всех четырёх сессиях (16:14, 16:21, 16:27, 16:28) запускалась `cstrike_win64.exe -steam`. В appinfo у неё два варианта для Windows — `cstrike.exe` (PE32) и `cstrike_win64.exe` (PE32+), и Steam выбирает 64-битный. Хук сработал для `steamclient64.dll` (`redirect_steamclient … 40 exports`), `spike-check.sh 240` — **9 ok, 0 failed**. Строки DXMT нет, потому что D3D9 идёт через `renderer=wined3d-gl` (R38). **i386-хук в настоящей игре по-прежнему не проверен** (R35).
- **32-битная игра:** среди установленных (PEAK, ETS2, Deadlock, CS:S, Stardew) нет ни одной только 32-битной. Остаётся Isaac (250900): SPIKE_TEST §9.2.
- **Deadlock подтверждён по логам, повторять не нужно:** сессия 13:28 — уже с новым lsteamclient (мост 12:40) и B1 (`redirect_steamclient` ×2), **0 строк `Don't recognize interface`** (раньше были 005 и AppDisableUpdate001), игра шла ~14 мин, выход `game exited status=0`.
- `lsteamclient.so` в мосте после установки из приложения — release-копия (`aef7…`, 2,39 МБ, R27 — strip SwiftPM). В ней 22 символа `SteamNetworkingSocketsSerialized005` и 2 `SteamAppDisableUpdate001`, как в сборке. В PE-библиотеках моста x86_64 и i386 хеши совпадают с приложением.
- RISKS: R1 уточнён, добавлены R35–R38.
- Проверки: `make runcheck compatcheck scriptcheck panel-behavior webpatch-fixtures sigcheck anchorcheck sigdb-fixtures overlay-shim-tests` — все 0; `make app-tests` — 0, 292 теста; `test-b1.sh scratch/ntdll-b1/dormison-b1` — 0, x86_64 и i386 OK, пара совпадает по sha256 с установленной в движок.

## 2026-10-06 ~16:55 CEST — **Фаза 3 закрыта**

Твоя проверка: оверлей Steam работает, CS:S работает, Reinstall сработал, но Steam сам не закрылся; 32-битный тест пропускаем.

- **Мягкий выход Steam (P3-6).** Причина: `stopClient` слал SIGTERM, который steam_osx игнорирует. В `app.log` 14:38:24 → 14:38:58 видно 30 с ожидания, после чего шёл SIGKILL. Теперь `SteamBundle.quitClient`: `steam://exit` → через половину ожидания Quit Apple event → до 45 с → `StillRunning` («Quit Steam yourself… then press Retry») и кнопка **Retry** в Status. Сигналов нет. Repair и Remove не тронуты. 4 теста (`SteamBundleTests`). Живая проверка: `NotProtonApp --install-into-steam --reinstall` при открытом Steam → `steam quit: closed after 3 s`, `patched=true stoppedSteam=true`. Steam снова открыт (вход 16:52:27), `codesign --verify` Steam.app — ok.
- **Растягивание при смене разрешения** — это CS:S (D3D9 → wined3d-gl масштабирует кадр под окно; окно без рамки 1512×982), а не наша настройка: у PEAK в 16:41 `presenter=off upscaler=off`, §9.3 не включался. Включать по умолчанию нечего, BACKLOG п. 9 дополнен.
- **BACKLOG п. 11:** i386-путь реализован и покрыт `test-b1.sh`, на живой игре не проверен; кандидат — Alien Swarm (630).
- **CLAUDE.md §8 «Требования пользователя (из ручных тестов)»** добавлен (Update/Reinstall, мягкий выход, проверки).
- Проверки: `make runcheck compatcheck scriptcheck panel-behavior webpatch-fixtures sigcheck anchorcheck sigdb-fixtures overlay-shim-tests` — все 0; `make app-tests` — 0, **296 тестов**; `make app` — 0; `test-b1.sh` — x86_64 и i386 OK (16:45).

**Итог Фазы 3:** B1 (x86_64 и i386) в движке; 64-битные игры (PEAK, ETS2, Deadlock, CS:S) — хук, оверлей, интерфейсы 005/AppDisableUpdate001 работают; i386 — только тестом (BACKLOG 11). Status: сравнение по содержимому, Update, Reinstall, build id, мягкий выход Steam с Retry.

**Дальше:** Фаза 4 (EngineUpdater) — в новой сессии, по твоей команде.

## 2026-10-06 ~17:35 CEST — Фаза 4: EngineUpdater (обновление движка из приложения)

**Сделано** (коммит `4b032c1` и следующий):
- `Model/EngineManifest.swift` — `engine.json` проверяется закреплённым Ed25519-ключом Dormison до разбора. Релизы принимаются только из `github.com/kageroumado/dormison/releases/download/`. Каналы stable и beta (правило Sevoflurane), по умолчанию beta (P4-6).
- `Model/EngineSupport.swift` + `engine/support.json` + `engine/stage-support.py` — таблица совместимости. Её и B1-пару `make app-payload` кладёт в `payload/engine-support/` с проверкой sha256. Нет B1 или моста для версии — «Waiting for NotProton support» (P4-1).
- `Support/EngineTransport.swift` — загрузка в `.part` с докачкой по HTTP Range (206; на 200 начинает заново).
- `Model/EngineUpdater.swift` — порядок P4-2, раскладка и откат P4-3 (`previous`, `.previous-dormison-<tag>`, `renamex_np` SWAP), Steam и игры — P4-4. После установки остаётся одна предыдущая версия, кэш загрузок очищается.
- `Model/EngineSmokeTest.swift` — `wine --version`, `wineboot --init` во временном префиксе, B1-`ntdll` в `system32` и `syswow64` (P4-5).
- Status → **Engine**:
  - версия и commit;
  - **Check for Updates** (и сама при открытии);
  - **Install** / **Update** / **Reinstall**;
  - **Roll Back** в строке «Previous engine»;
  - **Update channel**;
  - вопрос «Close Steam to change the engine?», **Retry**, **Open Steam**.
- `NotProtonApp --engine check|install|reinstall|rollback` (P4-7).
- `EngineStore.switchTo` ставит `previous` и синхронизирует копию `ntdll` в мосте; удаление движка убирает висящую ссылку `previous`.

**Тесты:** `EngineUpdaterTests` — 19 тестов:
- подлинный `engine.json` b1 проверяется закреплённым ключом, а с одним изменённым байтом — нет;
- поддельный манифест;
- чужой URL;
- каналы;
- проверка обновлений;
- установка с нуля;
- поддельный тарбол;
- несовпадение sha256;
- изменённый файл;
- нет сети;
- прерванная загрузка с докачкой;
- провал смоук-теста;
- игра или Steam запущены;
- нет моста или B1;
- чужой коммит;
- обновление b1→b2→b3 с откатом;
- переустановка с откатом;
- нечего откатывать;
- встроенная таблица.

**Живая проверка без тебя** — на отдельном дереве в scratchpad, твой `runners/` не тронут:
- `--engine install` загрузил настоящий `dormison-b1.tar.xz`. Я оборвал загрузку на 17,7 МБ, повторный запуск продолжил: `downloading … from byte 17695726`;
- проверка, B1 (`33bca058…`, `e0d5f658…`) и смоук-тест: `dormison-b1 (Staging), wineboot created a prefix with the B1 ntdll.dll (x86_64 and i386)`. Установка заняла 123 с;
- дерево совпадает с твоим `runners/dormison-b1`: те же файлы и те же ссылки. Отличаются только `.notproton-b2` (спайк) и пути в env;
- `--engine reinstall` с обрывом на 16,6 МБ: `server resumed the download at byte 16580535 (206)`. Затем `.previous-dormison-b1` со старым деревом и `--engine rollback` дважды в обе стороны. Временное дерево (2 ГБ) удалено;
- снимок Status → Engine: `Dormison b1`, `Wine 11.16 + wine-staging 11.16, commit 52c2a4b918d6.`, `Up to date. Checked 17:30.`, кнопки Check for Updates и Reinstall, канал Beta.

**Проверки (17:33, все с кодом 0):**
- `make app-tests` — **315 тестов** (было 296);
- `make app` — `out/NotProton.app (1.0.2)`;
- `make runcheck compatcheck scriptcheck panel-behavior webpatch-fixtures sigcheck anchorcheck sigdb-fixtures overlay-shim-tests`.

**Не проверено:** кнопки в окне на твоём настоящем движке и PEAK после переустановки и отката — это контрольная точка, SPIKE_TEST §10.

**Документы:** DECISIONS P4-1…P4-7, RISKS R39–R41, BACKLOG 12–14, SPIKE_TEST §10.

**Дальше:** твоя проверка по SPIKE_TEST §10. Затем Фаза 5 (BridgeUpdater, SignatureUpdater, гейт Steam) — по твоей команде.

**Уведомление (17:42 CEST):** `PushNotification` — `Push not sent — mobile push is disabled in /config` (как раньше, BLOCKERS «Уведомления»). Снимок блока Engine отправлен в сессию файлом, системное уведомление macOS отправлено. Жду проверки по SPIKE_TEST §10.
