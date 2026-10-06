# DECISIONS — принятые решения

Новые решения дописываются вниз. Открытые вопросы — в `docs/BLOCKERS.md`.

| Дата | # | Решение | Как выполняем / последствия |
|---|---|---|---|
| 2026-10-06 | В1 | База — `upstream/main` v1.0.2. Из `upstream/dev` **ничего не переносим** | ветка `dormison` остаётся на `6ba74eb`; `upstream/dev` не отслеживаем |
| 2026-10-06 | В2 | Старый эксперимент не сохраняем. Удалены (01:16 CEST): `~/Library/Application Support/notproton/engines/dormison` (2,1 ГБ), `notproton/bridge/engine` (1,3 МБ) и опустевшая `notproton/engines` | `notproton.dylib` в `/Applications/Steam.app` ссылался на `engines/dormison`, поэтому Steam Play для Windows-игр не работает до развёртывания сборки Фазы 1 |
| 2026-10-06 | В3 | Настройки игры — в двух местах, единственный источник правды `<prefix>/.sevo/apps/<exe>.env`. Основное — окно «Настройки игры» в NotProton.app. Панель в Steam упрощается до выбора рендерера | Фаза 2: CX-опции панели (`D3DM_*`, `DXMT_METALFX*`, `MTL_HUD_ENABLED`, `ROSETTA_*`, `WINEMSYNC`, `NOTPROTON_RETINA`) уходят из панели |
| 2026-10-06 | В4 | Автообновление Sparkle выключить **уже в Фазе 1** (ветка `spike/dormison`): фид указывает на апстрим и может заменить сборку форка. В Фазе 6 переключить на свой фид | Фаза 1: автопроверка выключена до первой установки spike-сборки |
| 2026-10-06 | S1 | **Форк не вызывает Sevoflurane ни при каких условиях**: ни через `sevoflurane://` из копии загрузчика, ни через `SEVO_CLI` из меню View (заглушка или скрытие пунктов). Если к концу Фазы 1 не получится — обход описать в `SPIKE_TEST.md` | см. «Как выполняем S1» ниже |
| 2026-10-06 | P1-1 | **Спайк: lsteamclient — B2 для x86_64.** `ntdll-patch/patch-dormison.sh` патчит `x86_64-windows/ntdll.dll` в копии движка; чистый файл остаётся рядом как `ntdll.dll.notproton-orig`, копия патча — в `bridge/wine/x86_64-windows/`. i386 не патчится (cave 368 < 1376) | окончательный выбор B1 / B2 — в Фазе 3. Через `WINEDLLPATH_PREPEND` ntdll подать нельзя: `load_ntdll()` открывает его только из каталога движка (`dlls/ntdll/unix/loader.c`) |
| 2026-10-06 | P1-2 | Движок ставит скрипт `engine/fetch-dormison.sh`: три проверки (подпись манифеста, подпись + sha256 + размер тарбола, каждый файл по `engine-manifest.json`), распаковка в `.partial`, атомарный `current` | Фаза 4 переносит это в `EngineUpdater` приложения |
| 2026-10-06 | P1-3 | lsteamclient в движок **не** кладём: `WINEDLLPATH=bridge`, Dormison ищет там после своего дерева | движок остаётся как в поставке, кроме ntdll (P1-1) |
| 2026-10-06 | P1-4 | Рендерер DXMT по умолчанию — через `WINEDLLPATH_PREPEND=notproton/renderers/dxmt`: ссылки в `runners/current`, overrides `d3d10core,d3d11,dxgi,winemetal=b`. Builtin-`winemetal.dll` копируется в `system32`/`syswow64` префикса | без файла в префиксе Wine не берёт builtin с dll path (`find_builtin_without_file` работает только при создании префикса). Порядок `d3d10core,d3d11` нужен, чтобы Dormison писал в лог `renderer=dxmt` |
| 2026-10-06 | P1-5 | Бандл игры несёт копию **`x86_64-unix/wine`** (загрузчик с `WINE_RESERVE`), а не `wine/bin/wine` (входная дверь). `SEVO_LOADER` в `.sevo/apps/{steam.exe,<игра>.exe}.env` указывает на эту копию | Dormison перезапускает дочерние процессы через `SEVO_LOADER`, иначе через загрузчик движка: игра потеряла бы имя в Dock и Game Mode |
| 2026-10-06 | P1-6 | `.sevo/bottle.env` пишется при первом запуске под Dormison (профиль по умолчанию); `WINEMSYNC` и `SEVO_CLI` переписываются при каждом запуске; маркер msync времён CrossOver не переносится | профиль — `MIGRATION_PLAN.md` §3.2; источник правды для настроек — Фаза 2 |
| 2026-10-06 | S1-impl | S1 выполнен: заглушка `notproton-sevo` (только пишет в лог) в `SEVO_CLI` и `bottle.env`; лаунчер экспортирует `SEVO_LOADER_TREE` и выходит без программы (и с `-psn_…`); бандлы в `launchers/app-<appid>/` | проверено: заглушка, условие выхода, отсутствие процесса Sevoflurane.app |
| 2026-10-06 | B4-impl | Sparkle не стартует, «Check for Updates…» неактивен, `SUFeedURL`/`SUPublicEDKey` апстрима удалены из `Info.plist`, `SUEnableAutomaticChecks=false` | свой фид — Фаза 6 |
| 2026-10-06 | P1-7 | Имя инструмента в Steam — «Dormison (NotProton)». Внутреннее имя `notproton` не меняется | Steam хранит выбор инструмента по внутреннему имени, а Steam Cloud требует «proton» в имени каталога |
| 2026-10-06 | P1-8 | `NotProtonApp --install-into-steam` — установка в Steam тем же кодом, что кнопка Install, без окна (шаг CrossOver пропущен) | для автономной установки и будущих smoke-тестов |
| 2026-10-06 | P1-9 | Мост раскладывается по sha256, а не по размеру | ошибка апстрима: собранный под Dormison `lsteamclient.so` после strip совпал по размеру со старым, и старый остался |
| 2026-10-06 | P1-10 | `PrefixTools` (Wine Configuration, Registry Editor, Task Manager, Run…, пересборка) использует раскладку и окружение Dormison, как `compat_run.sh`; профиль `users/<пользователь macOS>` → `steamuser` и при запуске, и при пересборке | Фаза 2 переносит это в `EngineProvider` |
| 2026-10-06 | rm-guard | В скриптах каждый `rm`/`find -delete`/`rsync --delete` с переменной в пути — через `${var:?}` | по твоему указанию; коммит `aba3265` |
| — | lsteamclient | B1 / B2 / A — окончательно по итогам Фазы 3 | спайк — B2 (P1-1); **решено: B1 (P3-1)** |
| 2026-10-06 | P1-GO | **Фаза 1 — GO** (твоё решение после ручной проверки четырёх игр). На PEAK, ETS2 и Deadlock работают мост lsteamclient, msync+, DXMT, бандлы с иконкой в Dock, нативные окна и меню View | итоги — раздел «Итоги Фазы 1» ниже; замечания — `docs/BACKLOG.md` |
| 2026-10-06 | S1-check | S1 не нарушен: Sevoflurane.app и его wineserver в проверке Deadlock запускал ты сам. Все 7 вызовов из меню View (PEAK, ETS2, Deadlock) ушли в заглушку `notproton-sevo` | `spike-check.sh` принимал твой Sevoflurane за наш — BACKLOG п. 3, Фаза 2 |
| 2026-10-06 | VAC | Онлайн-матчи в играх с VAC (Deadlock и другие) не запускаем, пока не выяснены риски хука steamclient | BACKLOG п. 7, `RISKS.md` R33 |
| 2026-10-06 | DX12 | Отказ RE9 (DirectX 12, «Unsupported graphics card») ожидаем и провалом Фазы 1 не считается: DXMT — только D3D10/11 | D3DMetal (GPTK) / Mullion — Фаза 7, BACKLOG п. 5 |
| 2026-10-06 | spike-ref | Ветка `spike/dormison` остаётся эталоном и не удаляется. Фаза 2 начинается только по твоей цели | — |
| 2026-10-06 | backlog | Замечания ручной проверки ведём в `docs/BACKLOG.md`, у каждого — фаза | фазы пунктов 1–6 назначил ты, пункта 7 — предложение |
| 2026-10-06 | dormison-ff | `dormison` перемотан на `spike/dormison` (fast-forward до `2259474`) | Фаза 2 — в `dormison`; `spike/dormison` больше не меняется |
| 2026-10-06 | P2-1 | Renderer — единственная настройка на странице игры в Steam (`NOTPROTON_RENDERER=<имя>` в параметрах запуска, значения dxmt/dxvk/wined3d, автоматически — DXMT). Остальное (HUD, AVX, Retina, окно, апскейлер, ввод, ядра, msync+) — в «Настройках игры». Приоритет: параметр запуска → `.sevo/apps/<exe>.env` → `bottle.env` → DXMT. Старый `CX_GRAPHICS_BACKEND` читается как запасной и убирается при выборе в панели | В3; старые параметры `MTL_HUD_ENABLED`, `WINEMSYNC`, `NOTPROTON_RETINA` в параметрах запуска по-прежнему работают |
| 2026-10-06 | P2-2 | Установка движка из приложения — Фаза 4 (`EngineUpdater`). В Фазе 2 приложение показывает движок, переключает установленные версии и удаляет неактивные; ставит движок `engine/fetch-dormison.sh --activate` | CLAUDE.md §5 |
| 2026-10-06 | P2-3 | Внутренние имена C-кода dylib (`np_compat_register_crossover` и др.) не переименовываем до Фазы 7: правка сдвигает базовую линию `__text` ради косметики | Фаза 7, `grep -ri crossover` |
| 2026-10-06 | P2-4 | Сторож первого кадра включается только `NOTPROTON_WATCHDOG=<секунды>` в параметрах запуска (тесты). Игрок окно ошибки видит | BACKLOG 6 |
| 2026-10-06 | P3-1 | **lsteamclient: B1.** Хук в `dlls/ntdll/loader.c` форка Dormison (ветка `notproton/b1-steamclient`, коммит `1e0b5ba000` поверх `52c2a4b918`; патч — `ntdll-patch/b1/0001-…patch`). Собираются только PE `ntdll.dll` x86_64 и i386 и кладутся поверх релиза. Логика — как у Proton (`steamclient_setup_trampolines`): для `steamclient`, `steamclient64`, `gameoverlayrenderer(64)` — переходы в `lsteamclient` и точка входа. 32-битный `steamclient` — без разрешения импортов и с ImageBase из файла, остальные — `LDR_DONT_CALL_DLLMAIN` (флаг Proton, теперь его проверяет `MODULE_InitDLL`). Пишем из PE-части, unix-интерфейс не трогаем, поэтому `ntdll.so` и протокол сервера остаются релизными. Отключение — `PROTON_DISABLE_LSTEAMCLIENT=1` | **Почему не B2:** у i386 нет места (cave 368 байт при детуре 1376), а новая PE-секция означала бы ещё один бинарный патч по смещениям. В B1 тот же код работает для обеих архитектур и пересобирается из исходников под каждый релиз. **Почему B1 безопасен:** релиз собран mingw GCC 16.2.0, как у нас; непропатченная сборка совпадает с релизной по коду инструкция в инструкцию (`build-b1.sh --check-base`). **Почему не A:** игры с DRM ждут настоящий Windows steamclient. **Найдено:** в Dormison флага «не вызывать DllMain» нет, поэтому в спайке B2 DllMain `lsteamclient` вызывался второй раз с адресом `steamclient64`. Обошлось, но в B1 исправлено. Доказательства: `ntdll-patch/b1/test-b1.sh` (x86_64 и i386: OK; с релизной `ntdll.dll` — FAIL) |
| 2026-10-06 | P3-2 | **Интерфейсы `SteamNetworkingSocketsSerialized005` и `SteamAppDisableUpdate001`** добавлены в lsteamclient скриптом `lsteamclient/add-interfaces.py` поверх сгенерированных файлов Proton. Скрипт повторяет раскладку `gen_wrapper.py` и запускается из `fetch.sh`. Сам `gen_wrapper.py` здесь не запустить: он разбирает заголовки под Linux-таргет с системными заголовками Linux | Раскладка 005: 8 методов 003, затем `GetSTUNServer`, `BAllowDirectConnectToPeer`, `BeginAsyncRequestFakeIP` (gbe_fork и SKYNET сходятся). Новые методы возвращают `int32_t`: игра читает из того же регистра то, что объявлено у неё, поэтому ошибка источников «bool или int» ни на что не влияет. `ISteamAppDisableUpdate` — из заголовка Valve (`public/steam/isteamappdisableupdate.h`). Проверено на живом клиенте Steam (`lsteamclient/tests/ifacecheck.sh`): оба интерфейса создаются в x86_64 и i386, `GetSTUNServer` (слот 8) вернул STUN-сервер Valve `162.254.197.38:3478` |
| 2026-10-06 | P3-3 | `lsteamclient/build.sh --install` ставит только в мост (раньше — ещё и в дерево CrossOver) | остаток Фазы 2; движок остаётся релизным, кроме `ntdll.dll` (P3-1) |
| 2026-10-06 | P3-4 | Доставка B1 пользователям — в Фазах 4–5: артефакт моста несёт пару `ntdll.dll` для тега движка, `EngineUpdater` кладёт её поверх релиза. Пока это делает `ntdll-patch/b1/install-b1.sh`: рядом остаются `.notproton-orig` (релиз) и `.notproton-b2` (спайк, только x86_64). `install-b1.sh --restore` возвращает релиз | CLAUDE.md §4.5–4.6 |
| 2026-10-06 | P3-5 | **Состояние патча в Steam — по содержимому, а не по номеру версии.** `PatchComparison` сравнивает dylib в Steam.app по LC_UUID (подпись меняет байты, LC_UUID — нет), `compatibilitytools.d/notproton/run` — по sha256 с `compat_run.sh` из payload, мост и вспомогательные файлы в `notproton/` — по sha256. Любое расхождение → `.outdated(stale:)` → «Update available» и кнопка Update. Reinstall (`force`) патчит Steam заново всегда. Установка закрывает Steam только после подтверждения и отказывает, пока запущена наша игра (и в приложении, и в установщике, и в `--install-into-steam`). Build id в Status — первые 8 знаков LC_UUID arm64-среза | Status писал «Installed (1.0.2)» над dylib старой сборки той же версии, и кнопки Install не было: `dylib.version` совпадал. Отсутствующий `run` не считается устаревшим: dylib пишет его при каждом запуске игры |

## Как выполняем S1

Проверено по исходникам Dormison `52c2a4b918`. В движке **ровно два** места, которые вызывают Sevoflurane. Третий его компонент, dock-шим, мы не подключаем.

1. **`loader/main.c:186–206`, `open_in_sevoflurane()`.** Копия загрузчика выполняет `/usr/bin/open sevoflurane://play/<id>`, если выполнены все условия:
   - запущена без программы (`argc ≤ 2`, или единственный аргумент — `-psn_…`);
   - не задан `SEVO_LOADER_TREE`;
   - лежит в `…/<только цифры>/<Имя>.app/Contents/MacOS/`.

   Раскладка NotProton `launchers/<appid>/<Имя>.app` под это подходит. В Фазе 1 ставим три защиты, каждой достаточно:
   - launcher всегда экспортирует `SEVO_LOADER_TREE`;
   - каталог бандла не состоит только из цифр (например, `launchers/app-<appid>/`);
   - launcher без аргументов не запускает загрузчик.
2. **`dlls/winemac.drv/cocoa_app.m:1160–1176`, `sevoStoreSetting:`.** Пять пунктов меню View вызывают `$SEVO_CLI app config <appid> <key> <value>`:

   | Пункт меню | `<key>` | Значения |
   |---|---|---|
   | Upscaler | `upscaler` | — |
   | Filter | `filter` | — |
   | FPS | `fps` | `on`/`off` |
   | FPS graph | `fps-graph` | `on`/`off` |
   | Windows | `windows` | `off`/`fixed`/`all`/`window` |

   Если `SEVO_CLI` не задан или пуст, вызывается `/usr/local/bin/sevo`. Если задан, запасной путь не используется вообще, а при неисполняемом пути вызов просто пропускается.
   - Фаза 1: `SEVO_CLI` всегда задан — в env launcher и в `.sevo/bottle.env` — и указывает на заглушку NotProton.
   - Фаза 2: заглушка начинает писать в `.sevo/apps/<exe>.env`, и выбор из меню View переживает перезапуск.
   - Скрыть пункты меню без пересборки `winemac.so` нельзя: это unix-часть движка, а B1 пересобирает только PE `ntdll.dll`.
3. **Dock-шим** `libsevodockshim.dylib` пишет логи и иконки в пути Sevoflurane. Не подключаем.

## Состояние окружения (с твоих слов и после проверки)

- Пуши: ты их включил. Сейчас проверять тестовой отправкой не стал: ты у терминала, и инструмент пропустил бы её как дубликат. Проверится на следующей контрольной точке.
- `pkgconf`: на 2026-10-06 ~01:25 CEST его не было; в 02:41 CEST `/opt/homebrew/bin/pkg-config` и `pkgconf` есть. Вопрос закрыт.

## Итоги Фазы 1 (ручная проверка, 2026-10-06)

Проверял ты, на M4 Pro, по `docs/SPIKE_TEST.md`. После каждой игры запускал `engine/spike-check.sh`.

| Игра | Параметры | spike-check | Итог |
|---|---|---|---|
| PEAK (3527290, Unity) | `-force-d3d11` | 9 ok / 1 FAIL | Работает: Dormison, бандл с иконкой, DXMT, msync. Окно тянется за угол, есть оконный и полноэкранный режимы, Retina. Оверлей Shift+Tab работает. Upscaler и Final Filter из меню View ушли в заглушку. ~78 fps при 3024×1890, неровно. FAIL — финал лога (BACKLOG 1) |
| Euro Truck Simulator 2 (227300) | `-rdevice dx11` | 10 ok / 0 FAIL | Работает, HDR, 78–120 fps. Уведомление Steam поверх игры. View → Show Frame Rate работает |
| Deadlock (1422450, Source 2) | `-steam -console` | 7 ok / 3 FAIL | Меню и матч с ботами, ~60 fps (в матче 32–58), без фризов. FAIL: два неизвестных интерфейса lsteamclient (BACKLOG 2); wineserver и Sevoflurane.app — твои (BACKLOG 3) |
| Resident Evil Requiem (сторонний ярлык 4022369388) | — | 9 ok / 1 FAIL | DirectX 12: «Unsupported graphics card (0x80004002)» в модальном окне (BACKLOG 5, 6). FAIL — финал лога (BACKLOG 1) |

| Критерий GO | PEAK | ETS2 | Deadlock |
|---|---|---|---|
| 1. Steam Play виден, игра стартует | ✅ | ✅ | ✅ |
| 2. lsteamclient и трамплины | ✅ | ✅ | ⚠ 2 неизвестных интерфейса, игра работает |
| 3. `WINEMSYNC=1`, выход без зависания | ✅ по факту, ⚠ финал лога | ✅ | ✅ (висящий wineserver — твой, от Sevoflurane) |
| 4. Окно: размер, полный экран | ✅ | ✅ | ✅ |
| 5. Оверлей Steam | ✅ | ✅ уведомления | отдельно не проверялся |
| Ачивки | отдельно не проверялись, время в игре считается | — | — |

Что я сверил по логам после твоего отчёта:
- **lsteamclient.** Детур сработал во всех трёх играх (`spike-check`, п. 2). Deadlock обращался к фабрике интерфейсов lsteamclient, и отказы были только по двум именам. В 03:55:45, посреди сессии, в `Steam/logs/stats_log.txt` есть `StoreUserStats` для 1422450 — скорее всего, вызов самой игры.
- **Выход из игры.** В ETS2, Deadlock и последней сессии PEAK финал записан: `wait_prefix_idle` занял 10 тиков. Финал теряется, когда игру останавливает Steam (BACKLOG 1).
- **Оверлей и презентер Dormison (R5).** Во время проверки презентер был выключен (`presenter=off`). MetalFX в PEAK включали из меню View на 14 секунд (03:11:34–03:11:48). Оверлей с включённым презентером отдельно не проверяли.
- **Рендерер Deadlock.** Скорее всего, DXMT. Vulkan, выбранный в настройках, включится со следующего запуска (BACKLOG 4).
- **Повторный `spike-check.sh` в 04:25** (Sevoflurane закрыт, логи те же):
  - Deadlock — 9 ok / 1 FAIL: остались только два интерфейса, оба FAIL из-за Sevoflurane ушли;
  - PEAK — 10 ok / 0 FAIL: финал последней сессии дописан в 03:13:16, через 11 секунд после того, как Steam вернул «Играть»;
  - ETS2 — 10 ok / 0 FAIL;
  - RE9 — 9 ok / 1 FAIL: финала нет, сессию остановил Steam.
- **Ложный ok в `spike-check.sh`.** П. 5 «a process drew through DXMT» RE9 проходит, хотя кадров не было (BACKLOG 4).
