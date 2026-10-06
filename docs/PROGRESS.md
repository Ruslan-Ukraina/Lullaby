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
