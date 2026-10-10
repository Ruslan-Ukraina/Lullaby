# Переименование NotProton → Lullaby — план

Решение владельца 10.10.2026 (~19:10 CEST, ответы в чате):
- **объём — полностью**: видимое имя, Bundle ID, ID инструмента в Steam, папка данных, имена в коде, переменные окружения;
- **Bundle ID — `com.ruslanukraina.Lullaby`**;
- **имя в Steam — «Dormison (Lullaby)»**;
- **истоки — только `NOTICE`** (копирайты NotProton по GPL-3 остаются там обязательно; в credits NotProton — среди остальных авторов, как сейчас; в окне и Steam — только Lullaby).

Репозиторий уже `Ruslan-Ukraina/Lullaby` (Фаза 9). Работа — в ветке `phase-8`, отдельной сессией. Фаза 6 после переименования: Sparkle, Keychain и ключи сразу привязываются к новому Bundle ID и `feed.json` → `Ruslan-Ukraina/Lullaby`.

## Масштаб (по коду 10.10)

`notproton` (без учёта регистра, без `docs/`) — в **211 файлах, 1228 местах**: `app/` 103 файла, `dylib/` 60, `release/` 9, `ntdll-patch/` 9, `perf/` 5, `engine-fixes/` 4, `.github/` 4, `lsteamclient/`, `bridge/`, `steam-shim/`, `overlay-shim/`, `engine/`, `Makefile`, `README.md`, `NOTICE`, `.gitignore`, `CLAUDE.md`.

## Что не переименовываем

- **`NOTICE`, credits, `LICENSE*`**: копирайты и ссылки на NotProton (NotProtonNot) — как есть (GPL-3 требует сохранить уведомления).
- **Ссылки на апстрим**: `upstream` = `NotProtonNot/NotProton`, ссылки на коммиты и issues апстрима в docs и комментариях.
- **История** (`PROGRESS`, `DECISIONS`, старые записи `BLOCKERS`, `SPIKE_TEST`): журнал прошлого не переписываем; новые записи — с Lullaby. В шапки этих файлов — одна строка «до 10.10 проект назывался NotProton».
- **`CLAUDE.md`** — файл владельца: предложу правку (заголовок, пути), без «ок» не меняю.
- **Папки проектов** `~/Projects/NotProton`, `~/Projects/NotProton-phase8` — ваши, не трогаю. Предложу переименовать после закрытия сессии (git это не мешает).
- **Префиксы игр** (`Steam/steamapps/compatdata/<appid>`): внутри них нет имени инструмента в путях — не трогаем. `.sevo/*.env` — свои настройки, имя проекта в них не встречается (проверить в шаге 1).

## Шаги

### 1. Опись и словарь замен (Я, без изменений, ~30 мин)
Таблица «было → стало» по группам; проверка, что в префиксах и `.sevo/*.env` нет `notproton`:

| Группа | Было | Станет |
|---|---|---|
| Приложение | `NotProton.app`, `CFBundleName` NotProton | `Lullaby.app`, Lullaby |
| Bundle ID | `com.notproton.NotProton` | `com.ruslanukraina.Lullaby` (+ помощник Rosetta: `com.ruslanukraina.Lullaby.RosettaCheck`) |
| Swift | `NotProtonApp`, `NotProtonSettings`, `notproton-settings` | `LullabyApp`, `LullabySettings`, `lullaby-settings` |
| dylib и помощники | `notproton.dylib`, `notproton-sevo`, логи `notproton*.log` | `lullaby.dylib`, `lullaby-sevo`, `lullaby*.log` |
| Инструмент Steam | каталог `compatibilitytools.d/notproton`, ID `notproton`, «Dormison (NotProton)» | `lullaby`, «Dormison (Lullaby)» |
| Папка данных | `~/Library/Application Support/notproton` | `~/Library/Application Support/lullaby` |
| Переменные | `NP_*`, `NOTPROTON_*` (в `compat_run.sh`, Makefile, CI, Info.plist `NP*`) | `LB_*`, `LULLABY_*` |
| C-префиксы | `np_*` в dylib | `lb_*` (последним, отдельным коммитом, с обновлением базовой линии `__text` в тестах) |
| Панель в Steam | тексты и ключи `notproton` в `panel.js` | `lullaby` |
| Тексты | en/uk/ru в `Localizable.xcstrings` и каталоге настроек | Lullaby (тест полноты локализаций) |
| Публикация | `release/feed.json` → `Ruslan-Ukraina/NotProton`, имена тарболов `notproton-*` | `Ruslan-Ukraina/Lullaby`, `lullaby-*` |

### 2. Код (Я, 1–1,5 сессии, коммитами по группам)
Порядок: Swift-модули → Info.plist/Bundle ID → Makefile/CI/release → dylib (`compat.c` `TOOL_DIR_NAME`, `TOOL_DISPLAY_NAME`, `panel.js`) → `compat_run.sh` и переменные → тексты → C-префиксы. После каждой группы: `make app`, `make app-tests`, C-проверки (`compatcheck`, `compatsvc-check`, `sigcheck`, `runcheck`, `webpatch-fixtures`, `panel-behavior`, `spawn-live`) с кодом 0.
**Проверка:** `git grep -i notproton -- ':!docs' ':!NOTICE'` даёт только ссылки на апстрим и код миграции.

### 3. Миграция для уже установленного (код + тесты, Я, ~0,5 сессии)
Кнопка Install/Update в Lullaby, если находит следы NotProton:
1. **Папка данных:** `notproton/` → `lullaby/` — одним `rename` (тот же диск, мгновенно, без копирования ~3 ГБ). Если `lullaby/` уже есть — остановка с понятным сообщением, ничего не сливаем. Потом пересоздаются файлы с абсолютными путями: `runners/current/…-engine.env`, лаунчеры игр (`launchers/`, бандлы с копией загрузчика), симлинки `current`/`previous`.
2. **Steam:** при закрытом Steam — Repair старого патча NotProton, затем Install патча Lullaby (новый каталог инструмента `lullaby`; старый `compatibilitytools.d/notproton` удаляется).
3. **Привязка игр в Steam** (`config/config.vdf` → `CompatToolMapping`, у вас **5 игр** с `notproton`): заменить `"notproton"` на `"lullaby"` только в значениях имени инструмента; **резервная копия** `config.vdf.before-lullaby` рядом; Steam закрыт. Иначе игры откроются без Steam Play.
4. **Настройки приложения** (новый Bundle ID — новый домен `UserDefaults`): перенести то, что важно (бейдж уже показан, канал движка, ручной блок обновлений Steam). Keychain токена нет (Фаза 6), переносить нечего.
5. **Разрешения macOS:** «Управление приложениями» (App Management) и др. выдаются заново — окно уже объясняет это (P8-19).
6. Запись в `app.log` каждого шага миграции; повторный запуск ничего не ломает (идемпотентно).
**Тесты:** временное дерево (старая папка → новая; обе есть → отказ; `config.vdf` с 0/1/5 привязками, с чужими инструментами — не трогаются; повторный запуск).

### 4. Перенос на вашем Mac (ВЫ + Я, ~20 мин) — **только по вашему «можно»**
1. Закрыть игры и Steam; резервная копия `~/Library/Application Support/notproton` уже не нужна (rename без копирования), но `config.vdf` копируется.
2. `/Applications/NotProton.app` → `scratch/applications-backup/`; поставить `Lullaby.app`; Install → миграция (шаг 3).
3. Проверка: в Steam у PEAK и RE9 выбран «Dormison (Lullaby)»; `spike-check` 0 failed (игры — по «играю»/«ушёл»); настройки игр (`.sevo`) на месте.
**Откат:** вернуть `NotProton.app`, `rename lullaby → notproton`, `config.vdf.before-lullaby` → `config.vdf`, Repair → Install NotProton.

### 5. Документы и закрытие (Я, ~30 мин)
README (Lullaby), `RELEASING.md`, `PHASE6_PLAN.md`, `LOGS.md`, `SPIKE_TEST.md` (новый раздел ручной проверки), строки в шапках журналов; `DECISIONS`/`PROGRESS`; предложение правки `CLAUDE.md`.

## Риски

| Риск | Мера |
|---|---|
| Игры в Steam теряют Steam Play | миграция `CompatToolMapping` с копией; проверка в шаге 4 |
| Старый патч NotProton остаётся в Steam.app рядом с новым | Repair старого перед Install нового (шаг 3.2); тест |
| Абсолютные пути `…/notproton/…` в созданных файлах | пересоздание env-файла и лаунчеров; поиск `notproton` по папке после миграции |
| C-переименование ломает хуки (смещения `__text`) | отдельным последним коммитом, базовая линия в тестах, `sigcheck`/`anchorcheck` |
| Пропущенная строка перевода | тест полноты локализаций (уже есть) |
| Апстрим-исправления (A1010-*) труднее переносить | имена файлов в `dylib/` по возможности сохранить; в коде — словарь замен из шага 1 |
