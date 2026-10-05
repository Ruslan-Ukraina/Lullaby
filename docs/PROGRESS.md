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
