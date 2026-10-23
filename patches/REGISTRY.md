# Реестр функций: что смешивается с движком и что обновляется

Один список всего, что Lullaby добавляет к чужому коду (Wine, Steam) или обновляет отдельно, и правила, по которым это встраивается так, чтобы обновление основы не превращалось в ручную работу. Создан 2026-10-18, ведётся вместе с кодом: `patches/engine/check-registry.sh` (цель `make patchcheck`) падает, если патч есть в `patches/engine/`, а в этом файле его нет, и наоборот.

Связанные документы: `WINEFORGE_PORT.md` (план переноса, исследования), `STACK_PLAN.md` (общий план, этапы), `PERF_STAND.md` (замеры).

## 1. Правила встраиваемости патчей

Цель: новый релиз основы (Dormison, WineForge) либо проходит проверки автоматически, либо не ставится и говорит почему. Для этого каждый патч устроен так:

1. **Один патч — одна функция — одна запись здесь.** Имя файла `NNNN-модуль-суть.patch`; в таблице §3 его ID, назначение, затронутые файлы.
2. **Заголовок патча** (текст до первой строки `diff`): что делает и зачем, откуда взят (проект, коммит, лицензия), на каких релизах проверен и когда, чем включается и выключается, чем проверяется. Без заголовка патч не принимается.
3. **Чужой код трогаем минимально.** Новый код — в новых функциях и по возможности в новом файле; в чужие файлы — только крючки. Нового `.c` не добавляем в `Makefile.in` (это точка конфликта): его подключают строкой `#include` из существующего файла той же единицы трансляции. Не переформатировать, не переименовывать, не переносить чужие строки; контекст hunk — 3 строки.
4. **Поведение под переключателем.** Исправление явной ошибки (commit charge, HAGS, retina) включено всегда. Всё, что меняет поведение игр (V-Sync, лента показа, прямой вывод), выключено, пока не включено переменной `LULLABY_*`; сломавшуюся на обновлении функцию тогда можно выключить для одной игры, не откатывая движок.
5. **Независимость.** Патч не зависит от другого, кроме явной строки `Requires:` в заголовке; порядок применения — по номеру.
6. **Серия на основу.** `patches/engine/<основа>/<модуль>/NNNN-….patch`. Патчи, которые «не для этой основы», лежат в `patches/engine/patches/` (Dormison) и не копируются в чужую серию, пока не переписаны.
7. **Гейт на новый релиз основы** (CI; пилот — `patches/engine/rehearse.sh`, исследования в §2.7 `WINEFORGE_PORT.md`): 
   1. `patches/engine/rehearse.sh` — патчи применяются к новому тегу;
   2. собираются только затронутые модули (минуты, не весь Wine);
   3. экспортируемые символы равны релизным;
   4. модуль без патчей совпадает с релизом по инструкциям (Dormison: `build-fixes.sh`, измерено для `winemac.so` dormison-b2: 126 067 инструкций, различий нет; WineForge: под вопросом, §2.7 `WINEFORGE_PORT.md`);
   5. проходят тесты: стенд `perf/`, пробные программы `patches/engine/tests/`, `make app-tests`;
   6. публикуется подписанный манифест `engineFiles` (sha256 чистого и патченого файла, патчи с sha256), как у моста;
   7. не прошёл любой шаг — новая основа у пользователей не ставится, в интерфейсе причина.
8. **Откат.** Рядом с заменённым модулем лежит `<файл>.lullaby-orig`; предыдущая пара «основа + оверлей» хранится.
9. **Компоненты — не патчи.** DXMT, DXVK, прокси, шим — отдельные файлы с закреплённым источником и sha256, подключаются через путь поиска DLL и обновляются независимо от основы.
10. **Лицензии.** Патч на Wine — LGPL-2.1+ (в заголовке автор и источник); код из других проектов — с сохранением их уведомления; список в `NOTICE`.

## 2. Что обновляет что

| Событие | Какие записи затрагивает | Что делает система |
|---|---|---|
| Релиз основы (Dormison / WineForge) | ENG-*, SRV-*, SYN-*, BRG-*, BASE-* | гейт из правила 7; новый мост под коммит основы; пара ставится целиком |
| Новая сборка macOS Steam | STM-01, STM-09 | якоря сигнатур (`anchorcheck`), нарезка базы, подписанный `signatures-manifest.json`; пока нет сигнатур — Steam не обновляется (`UpdateBlock`) |
| Новый коммит DXMT (закрепление) | CMP-01 | сборка в CI, А/Б со старым на трёх играх, иначе остаёмся |
| Новая версия GPTK | CMP-03 | ставит пользователь (импорт); Lullaby проверяет раскладку и версию, ничего не копирует в движок сам |
| Релиз Lullaby | APP-*, RUN-*, STM-02…08 | Sparkle, подписанная лента; встроенный скрипт и dylib сравниваются по хешу с установленными |
| Новые данные об играх | DAT-06 | подписанный каталог, независимо от приложения |

## 3. Реестр

Столбец «WineForge» — результат `rehearse.sh` против 8 релизов (0.6.0.0–0.6.0.7, Wine 11.12–11.20) 2026-10-18: **OK** применяется без правок на всех; **fuzz** — со сдвигом; **FAIL** — не применяется ни на одном (патч не для этого дерева); «—» не проверялось.

### 3.1 Основа (слой 1)

| ID | Функция | Где живёт | Происхождение | Как обновляется |
|---|---|---|---|---|
| BASE-01 | Движок Dormison: wine-staging 11.16 + 185 коммитов (окна, Presenter, msync+, `.sevo/*.env`, мост Steam, медиа, нативный сервер) | `runners/dormison-<тег>/`, лента `engine.json` с подписью Ed25519 | kageroumado, LGPL | `EngineUpdater` (канал beta/stable), атомарно, одна предыдущая версия для отката |
| BASE-02 | Движок WineForge: Wine 11.20 + 50 коммитов (D3DMetal-склейка, WFUSync, GCMouse, WFDXCompat, свой мост Steam) | `Engine/WineForgeCore` внутри `WineForge.dmg` (219 МБ, подпись Developer ID) | Alien4042x, LGPL; ленты нет | кандидат; потребует нашего загрузчика образа и своей подписи |
| BASE-03 | Описание движка для скриптов: `lullaby-engine.env`, `engine-info.json` | рядом с движком | Lullaby | пишет приложение при установке |

### 3.2 Патчи модулей Wine (слой 2, `patches/engine/`)

| ID | Файл патча | Функция | Модуль / файл | Происхождение | Dormison | WineForge |
|---|---|---|---|---|---|---|
| ENG-01 | `0001-ntdll-commit-charge-is-the-footprint.patch` | `PagefileUsage` = phys_footprint, а не адресное пространство (игры сравнивают с физической памятью) | `ntdll.so`, `dlls/ntdll/unix/process.c` | Highball 0018, LGPL | в мосту | OK |
| ENG-02 | `0001-win32u-d3dkmt-hardware-gpu-scheduling.patch` | `KMTQAITYPE_WDDM_2_7_CAPS` = HAGS включён: без него Streamline не предлагает генерацию кадров DLSS | `win32u.so`, `dlls/win32u/d3dkmt.c` | Lullaby | в мосту | OK |
| ENG-03 | `0001-winemac-retina-horzres-not-doubled.patch` | `HORZRES`/`VERTRES` не удваиваются при Retina | `winemac.so`, `dlls/winemac.drv/gdi.c` | athei/wine fa43d6db2 через Highball 0020, LGPL | в мосту | OK |
| ENG-04 | `0002-ntdll-d3dmetal-4b3-dispatch-layout.patch` | раскладка диспетчера win32 для D3DMetal 4.0 beta 3 | `ntdll.so`, `dlls/ntdll/unix/loader.c` | Lullaby | в выпуск (нужен GPTK 4.0 beta 3)| FAIL |
| ENG-05 | `0003-ntdll-d3dmetal-4b3-find-best-window.patch` | поиск окна для D3DMetal 4.0 beta 3 (сторона ntdll) | `ntdll.so`, `dlls/ntdll/unix/loader.c` | Lullaby | в выпуск (нужен GPTK 4.0 beta 3)| FAIL |
| ENG-06 | `0002-winemac-d3dmetal-find-best-window.patch` | то же, сторона winemac | `winemac.so`, `dlls/winemac.drv/d3dmetal.c` | Lullaby | в выпуск (нужен GPTK 4.0 beta 3)| fuzz |
| ENG-07 | `0003-winemac-lullaby-vsync-and-present-feed.patch` | `LULLABY_FORCE_VSYNC`, `LULLABY_PRESENT_FEED` (лента показа для Reflex) | `winemac.so`, `d3dmetal_objc.m`, `macdrv_main.c` | Lullaby | в мосту | FAIL |
| ENG-08 | `0004-winemac-gcmouse-raw-input.patch` | мышь через GameController как WM_INPUT (WineForge, Elvin Hayatov, Wine MR !11799); **выключено**, включается `LULLABY_GCMOUSE=1` или `UseGCMouse=Y` | `winemac.so`, `cocoa_gcmouse.m`, `mouse.c`, `event.c`, `macdrv_main.c`, `Makefile.in` | Hayatov, LGPL | в мосту с r5-5-го (по слову владельца 2026-10-19; включается настройкой «Сира миша», по умолчанию выключено; проба мыши: 500 против 120 событий/с) | FAIL |
| ENG-09 | `0005-winemac-gcmouse-scale.patch` | масштаб сырых отсчётов GCMouse, `LULLABY_GCMOUSE_SCALE` (0,01…100), с переносом дробной части | `winemac.so`, `cocoa_gcmouse.m` | Lullaby | в мосту; Requires: ENG-08 | — |

Мост (с 2026-10-19 `bridge-dormison-r5-6`) несёт три изменённых модуля: `ntdll.so`, `win32u.so`, `winemac.so` (`bridge.json`: sha256 чистого и патченого файла); это ENG-01, ENG-02, ENG-03, ENG-07, ENG-08, ENG-09. Список патчей по именам в установленном `bridge.json` не хранится, он есть в репозитории (`patches/engine/patches/`).

Проверка применимости, не правильности: «OK» означает, что строки не менялись, а не что патч нужен или верен; это проверяют сборка и тесты.


Заведены, но патчами не оформлены (нужен анализ, нужны ли они на WineForge): Dormison 90bd24fa0 (спросить про Rosetta один раз, кэш), 5562e98ef (сигнал мёртвому потоку, связан с msync+) — на всех 8 релизах WineForge не применяются.

### 3.3 Синхронизация потоков

| ID | Функция | Где | Происхождение | Состояние |
|---|---|---|---|---|
| SYN-01 | msync+ (Mach-семафоры, бюджеты spin `PerformanceTuning`, обработка смерти процесса и потока, проверка потерянных пробуждений) | в Dormison | CrossOver 26.3 msync (LGPL) + kageroumado | в базе, включён всегда; отключается на игру (`LULLABY_MSYNC`) |

### 3.4 Мост со Steam (на каждый коммит основы)

| ID | Функция | Где | Происхождение | Как обновляется |
|---|---|---|---|---|
| BRG-01 | пара `ntdll.dll` (x86_64, i386) с подгрузкой `lsteamclient` (B1) | `patches/engine/lby-discord-ntdllhook` (`0001-ntdll-redirect-steamclient-to-lsteamclient.patch`), наложение на движок | Lullaby, по идее `use_lsteamclient` Proton | `build-b1.sh`: PE-модуль из того же коммита, что релиз; WineForge строит свой мост |
| BRG-02 | `lsteamclient.dll` (x86_64, i386), `lsteamclient.so` (x86_64) | `lsteamclient/`, `bridge/` | Valve, лицензия Steamworks SDK | `bridge/setup-wine-tree.sh` из исходников **того же коммита** основы |
| BRG-03 | `steam.exe` (шим, std handles, код выхода игры) | `steam-shim/` | BSD-3 | вместе с мостом |
| BRG-04 | подписанный `bridge-manifest.json` (совместимость основа ↔ мост ↔ оверлей, `engineFiles`) | `bridge/`, релиз форка | Lullaby | CI на каждый тег основы; новая основа не ставится, пока нет моста |

### 3.5 Компоненты (слой 3, подключаются через путь поиска DLL)

| ID | Функция | Где | Источник | Состояние |
|---|---|---|---|---|
| CMP-01 | DXMT (D3D10/11 на Metal) | `runners/<основа>/dxmt/` (Dormison), `lib/dxmt` (WineForge) | `3Shain/dxmt`; в Dormison v0.80 | сейчас из основы; план — закреплённый коммит `main` в нашем CI |
| CMP-02 | DXVK | `runners/<основа>/dxvk/` | Gcenx/DXVK-macOS v1.10.3 | из основы |
| CMP-03 | D3DMetal (GPTK 4.0 beta 3) | `lullaby/d3dmetal/<версия>/` | Apple, ставит пользователь; не распространяем | импорт; Dormison: файлы в `wine/lib/external`; WineForge: `D3DMETAL_RUNTIME_DIR=<GPTK>/lib` |
| CMP-04 | `lullaby-nvapi64.dll`: NVIDIA Reflex поверх D3DMetal (`nvapimt` переименован) | `patches/inject/lby-rainbowdash-reflex/` | Lullaby (идея `low_latency_layer`, MIT; код свой) | не зависит от основы; нужна лента показа ENG-07 |
| CMP-05 | Прокси `d3d12`: единая память (UMA=1) | — | Lullaby, по `sevo_uma.c` Dormison | запланирован (Э3) |
| CMP-06 | WFDXCompat (D3D12/D3D11 пробелы D3DMetal) | `lib/wfdxcompat` WineForge | WineForge | оценить на RE9 |

### 3.6 Сторона Steam (macOS)

| ID | Функция | Файлы | Как обновляется |
|---|---|---|---|
| STM-01 | Хуки в клиенте Steam: пункт Steam Play, `CCompatManager::*` (Dobby) | `dylib/core`, `dylib/hooks`, `dylib/resolver` | якоря сигнатур на каждую сборку Steam |
| STM-02 | Запись инструмента совместимости и сервис запуска | `dylib/feats/compat.c`, `compatsvc.c` | с приложением |
| STM-03 | Настройки игры в Steam: мост и панель | `settingsbridge.c`, `panel.js` | с приложением |
| STM-04 | Окна Steam (рамка, фокус) | `steamwin.m`, `steamfocus.m`, `steamwin_css.c` | с приложением (отложено, `BACKLOG.md` п. 15) |
| STM-05 | Блокировка обновления Steam без сигнатур | `updategate.c`, `UpdateBlock` | подписанный манифест сигнатур |
| STM-06 | Правки интерфейса Steam (webpatch) | `webpatch.c`, `webui.c` | фикстуры `webpatch-fixtures` |
| STM-07 | Доступ ко вводу | `input_access.c` | с приложением |
| STM-08 | Оверлей Steam в игре | `overlay-shim/` → `overlay-shim.dylib` (arm64 + x86_64) | с приложением |
| STM-09 | База сигнатур клиента | `signatures/macos.arm64/<сборка>.json`, `signatures/manifest.json` | CI по расписанию + `anchorcheck`, подпись |

### 3.7 Скрипт запуска и приложение

| ID | Функция | Где | Заметка |
|---|---|---|---|
| RUN-01 | `compat_run.sh`: запуск игры, пакет игры (имя, значок, Game Mode), настройки `.sevo/*.env`, подготовка рендерера (DXMT, DXVK, D3DMetal), `DYLD_INSERT_LIBRARIES` | `dylib/feats/compat_run.sh`, встроен в dylib (`embed_script.py`) | читает у движка `LB_ENGINE_{NAME,UNIX_DIR,WINELOADER,WINESERVER}`; **опирается на функции Dormison** (§3.1 `WINEFORGE_PORT.md`) |
| APP-01 | Приложение: движок, мост, сигнатуры, установка в Steam, настройки | `app/` | Sparkle |
| APP-02 | Обновление движка, моста, сигнатур, приложения | `EngineUpdater`, `BridgeCatalog`, `SignatureCatalog`, `ReleaseFeed` | подписи Ed25519, атомарно, откат |

### 3.8 Данные

| ID | Данные | Подпись | Заметка |
|---|---|---|---|
| DAT-01 | `engine.json` (лента движка) | Ed25519 Dormison | WineForge ленты не имеет |
| DAT-02 | `bridge-manifest.json` | наш ключ | совместимость основа ↔ мост ↔ оверлей |
| DAT-03 | `signatures-manifest.json` | наш ключ | по сборкам Steam |
| DAT-04 | `valve-packages.manifest` | — | пакеты Valve для установки Steam |
| DAT-05 | `release/feed.json` (Sparkle) | наш ключ | приложение |
| DAT-06 | Каталог исправлений игр (формат по exe: `backend`, `env`, `needs_engine`) | наш ключ | планируется (Э8): MacGameFix (приоритет), `umu-protonfixes` только данными |
| DAT-07 | `.sevo/bottle.env`, `.sevo/apps/<exe>.env` | — | настройки пользователя, не обновляются |

### 3.9 Инструменты проверки (не поставляются)

| ID | Что | Где |
|---|---|---|
| TST-01 | Репетиция патчей против тегов | `patches/engine/rehearse.sh` |
| TST-02 | Сборка и проверка модулей Dormison | `patches/engine/build-fixes.sh` |
| TST-03 | Проверка реестра | `patches/engine/check-registry.sh` |
| TST-04 | Пробные программы движка | `patches/engine/tests/` |
| TST-05 | Стенд замеров | `perf/` (`syncbench`, `gfxbench`, `threadcpu`, `frametap`, `report.py`) |

## 4. Как добавить функцию

1. Придумайте ID (`ENG-`, `SRV-`, `SYN-`, `BRG-`, `CMP-`, `STM-`, `RUN-`, `DAT-`) и допишите строку в §3.
2. Для патча: файл `NNNN-….patch` с заголовком по правилу 2, по правилам 3–5; `patches/engine/rehearse.sh` на теге основы; `make patchcheck`.
3. Для компонента: источник, версия/коммит, sha256, способ подключения, кто обновляет.
4. Записать, что её обновляет (§2) и чем проверяется.
