# BACKLOG — задачи по итогам Фазы 1

Источник — твой отчёт о ручной проверке игр (2026-10-06) и мой разбор логов после него (только чтение, без запуска игр).
Фазы пунктов 1–6 назначил ты. Пункт 7 я взял из того же отчёта, фаза у него — моё предложение.
Решения — `docs/DECISIONS.md`, риски — `docs/RISKS.md`.

| # | Задача | Фаза |
|---|---|---|
| 1 | Run-скрипт не пишет финал сессии (PEAK, RE9) | 2 — сделано, ждёт ручной проверки |
| 2 | Интерфейсы `SteamNetworkingSocketsSerialized005` и `SteamAppDisableUpdate001` в lsteamclient | 3 |
| 3 | Сосуществование с Sevoflurane: отличать наш wineserver от чужого, не пересекаться префиксами | 2 — сделано, ждёт ручной проверки |
| 4 | Производительность: PEAK ~78 fps при 3024×1890, Deadlock ~60 fps (цель — 120); какой API на самом деле рисует Deadlock | после 7 |
| 5 | DX12-игры (RE9): D3DMetal / Mullion | 7 |
| 6 | Модальные окна ошибок Wine и игр не должны блокировать автотесты | 2 — сделано (`NOTPROTON_WATCHDOG`) |
| 7 | Риски VAC от хука steamclient. Пока не выяснены — без онлайн-матчей с VAC | 3 (предложение) |

---

## 1. Run-скрипт не пишет финал сессии — Фаза 2

**Что видно.** В `notproton-run.log` после `=== bundle exited status=0 ===` нет строк `=== game exited … ===` и `=== wine prefix killed, session ending ===`. `spike-check.sh` пишет «the session has not ended», хотя процессов Wine уже нет.

**Причин две.** Обе в коде апстрима: `terminate()`, `wait_prefix_idle()` и цикл ожидания в `dylib/feats/compat_run.sh` (строки 824–858 и 895–924) такие же в `main` и `upstream/dev`.

1. **Игру останавливает Steam, и скрипт убивают до финала.** Так было в PEAK (сессии 02:58 и 03:00) и в RE9 (03:23).
   - Steam шлёт run-скрипту сигнал, в логе появляется `=== termination signal received, killing wine prefix ===`. `terminate()` гасит префикс и `open`, но сам скрипт не завершает.
   - Бандл к этому моменту уже вышел, и `open -W` вернул 0. Скрипт пишет `bundle exited status=0` и уходит в `wait_prefix_idle`, а это не меньше 10 секунд.
   - Steam повторяет сигнал ещё 2–3 раза, затем снимает процесс — скорее всего, `SIGKILL`. Его не перехватить, поэтому финал не пишется. В RE9 последняя запись в логе — 03:23:55, а в `Steam/logs/gameprocess_log.txt` Steam перестал отслеживать run-скрипт в 03:23:58. Для PEAK — `Game 3527290 going away; no longer tracking PID …` в 03:00:41 и 03:01:48.
   - Ветка «статус выше 128 — не ждать» в цикле написана как раз для этого случая, но не срабатывает: `kill "$open_pid"` из `terminate()` достаётся уже завершившемуся `open`.
2. **При обычном выходе Steam показывает «Играть» раньше, чем скрипт допишет лог.** PEAK, сессия 03:01:52: Steam перестал отслеживать игру в 03:13:05, а финал записан в 03:13:16 (`wait_prefix_idle done after tick=10 idle=10`). `spike-check.sh`, запущенный в эти ~11 секунд, видит незаконченную сессию. В отчёте по PEAK был именно этот случай: повторный `spike-check.sh` по тем же логам в 04:25 даёт 10 ok / 0 FAIL.

**Что делаем.**
- В `terminate()`: защита от повторного входа, затем `kill_wine_prefix`, строка `=== termination signal, session ending ===` и сразу `exit 143`, без `wait_prefix_idle`.
- В `spike-check.sh`: если run-скрипт этой игры ещё жив, ждать до 30 секунд. Финал по сигналу считать чистым завершением.
- Поведенческого теста у `compat_run.sh` сейчас нет: `runcheck` — это только `shellcheck` и `sh -n`. Добавить тест: имитация в `scratch/sim`, `kill -TERM` run-скрипту. Ожидаем финал в логе, код выхода 143, ни одного процесса Wine, а повторный сигнал не запускает `kill_wine_prefix` второй раз.

---

## 2. Интерфейсы lsteamclient — Фаза 3

**Что видно.** Deadlock, `launchers/app-1422450/notproton-wine.log`: `err:steamclient:create_win_interface Don't recognize interface name: SteamNetworkingSocketsSerialized005` (дважды) и `… SteamAppDisableUpdate001`. Игра при этом работала: меню, матч с ботами.

**Что известно.**
- На неизвестное имя `create_win_interface()` возвращает игре `NULL` (`build/lsteamclient/steamclient_main.c:285–332`, код Proton). Процесс не падает, а что игра делает без интерфейса, решает она сама.
- Наш lsteamclient собран из Proton `164e0ccd` (experimental-bleeding-edge-11.0, 2026-09-11). В нём есть `SteamNetworkingSocketsSerialized` 001–003, а `SteamAppDisableUpdate` нет совсем.
- В текущем Proton этих версий тоже нет: на 2026-10-06 в ветках `proton_11.0`, `experimental_11.0` и `bleeding-edge` только `Serialized002` и `003`. Значит, под Proton на Linux Deadlock получает те же `NULL`, и обновление `PROTON_COMMIT` проблему не закроет.
- Методы `SteamNetworkingSocketsSerialized003`: `SendP2PRendezvous`, `SendP2PConnectionFailure`, `GetCertAsync`, `GetNetworkConfigJSON`, `CacheRelayTicket`, `GetCachedRelayTicketCount`, `GetCachedRelayTicket`, `PostConnectionStateMsg`. Это сертификаты и relay-билеты сети Valve. Матч с ботами локальный, поэтому вопрос, работает ли онлайн-матчмейкинг без версии 005, открыт. Проверить его мешает п. 7.

**Варианты.**
- (а) Подтвердить, что `NULL` безопасен: отчёты о Deadlock на Proton (онлайн-матчи на Linux / Steam Deck) и проверка, не просит ли игра после отказа версию 003.
- (б) Написать обёртки 005 самим. Для этого нужна раскладка vtable клиента macOS — без заголовков Valve это рискованно.
- (в) Ждать, пока Valve добавит их в Proton.

**Проверка.** После решения по п. 7 — онлайн-матч в Valve-игре без этих двух строк в логе (или с подтверждённым безопасным `NULL`).

---

## 3. Сосуществование с Sevoflurane — Фаза 2

**Что видно.** Deadlock, `spike-check.sh`:
- «Wine processes are still running»: `76559 …/Library/Application Support/Sevoflurane/Engines/dormison-b1/wine/bin/wineserver` — это wineserver Sevoflurane, ты запускал его сам;
- «S1: Sevoflurane.app is running» — тоже ты.

**Почему ошибся spike-check.**
- Процессы Wine он ищет по всей системе: `pgrep -fl "wineserver|steam\.exe|x86_64-unix/wine|MacOS/wine"` (раздел 3 скрипта). Под шаблон попадает любой Wine.
- S1 он проверяет по факту «Sevoflurane.app запущен», а не по тому, запустили ли его мы.

**Что уже разведено** (проверено по коду 2026-10-06).
- **Префиксы разные.** Наши лежат в `steamapps/compatdata/<appid>/pfx`, у Sevoflurane свои бутылки. Каталог wineserver — `/tmp/.wine-<uid>/server-<dev>-<inode префикса>`, у каждого префикса свой.
- **Мы не трогаем чужое.** `kill_wine_prefix` бьёт только по своему префиксу: `wineserver -k` с нашим `WINEPREFIX`, добивание — по `lsof` нашего каталога сервера.
- **Sevoflurane не трогает наше.** Его демон останавливает только процессы своих бутылок. Фильтр — рабочий каталог, каталог wineserver и открытые файлы внутри бутылки (`Core/ClientLifecycle.swift`, `inBottle`: «other prefixes' wine processes are untouched»).
  По имени exe по всей системе он ищет только в `ProgramLaunch.isRunning` для FPS-анлокера. Там он ждёт, пока где-то работает игра с таким именем, и потом останавливает **свой** анлокер.
- **Слабое место.** Имя Mach-сервиса msync — `wine-<inode>-msync`: в нём только inode каталога префикса, без тома (Dormison `dlls/ntdll/unix/msync.c:1192–1202`, `server/msync.c:1188–1198`). Два префикса с одинаковым inode на разных томах получат одно имя. Сейчас наши префиксы и бутылки Sevoflurane на одном томе и не пересекаются. Это наследие msync из CrossOver, см. `RISKS.md` R34.

**Что делаем.**
- `spike-check.sh`:
  - «Наши» процессы — те, что держат каталог wineserver этого префикса (`lsof +D`, как `prefix_game_running` в `compat_run.sh`), и процессы из `notproton/runners/` и `notproton/launchers/`. Чужие процессы Wine показывать отдельной строкой, без FAIL.
  - S1: Sevoflurane.app, запущенный до начала сессии, — «открыт не нами», без FAIL. Запущенный во время сессии — «проверь», с временем старта (`ps -o lstart`). Отдельной строкой — вызовы заглушки `SEVO_CLI`.
- Приложение: любая проверка «идёт ли игра» (в Фазе 4 — «не обновлять во время игры») — только по нашим префиксам и путям движка, не по имени `wineserver`. Сейчас приложение проверяет только `steam_osx` по точному имени (`Model/SteamBundle.swift:28`).
- Проверка: одна игра при открытом Sevoflurane с запущенной в нём бутылкой. Ожидаем, что `spike-check.sh` чист, а процессы Sevoflurane целы после выхода из нашей игры.

---

## 4. Производительность и API Deadlock — после Фазы 7

**Что видно.**
- PEAK: около 78 fps при 3024×1890, неровно; Wine ~500 % CPU, 5,3 ГБ памяти.
- Deadlock: ~60 fps, в матче 32–58. Цель — 120.
- ETS2: 78–120 fps.

**Чем рисовал Deadlock** (сессия 03:49–03:58, `notproton-wine.log`). Скорее всего, D3D11 через DXMT:
- игра загрузила `rendersystemvulkan.dll`, а потом `rendersystemdx11.dll`;
- DXMT дважды создал устройство D3D11: `info: Using feature level D3D_FEATURE_LEVEL_11_1`, затем `…_11_0`. Рядом его предупреждения `D3D11Device: Unknown interface query`;
- `vulkan-1.dll` и `winevulkan.dll` загрузились уже после устройства D3D11, следов инициализации драйвера Vulkan нет. Так же их грузит PEAK с `-force-d3d11`.

**Почему это не доказательство.**
- `renderer=dxmt` в строке `sevo:gfx` ничего не доказывает. Dormison пишет туда настроенный рендерер: из `<engine>/renderer-hashes`, а если файла нет — из `WINEDLLOVERRIDES` (`sevo_provenance.c`, `renderer_from_overrides`). Игру на собственном Vulkan он от DXMT не отличает.
- `WineMetalLayer` в логе overlay-shim тоже ничего не доказывает: это слой Metal-окна в `winemac.drv`, общий для DXMT и Vulkan.
- На эту же строку опирается п. 5 `spike-check.sh` («a process drew through DXMT»). RE9 его проходит, хотя не показал ни одного кадра: `renderer=dxmt` есть, `first present` нет. Исправить в Фазе 2 вместе с п. 1 и 3: требовать `first present` у процесса с `renderer=dxmt` и строку DXMT `Using feature level`.

**Важно для следующего запуска.** В `game/citadel/cfg/boot.vcfg` записано `"DefaultRenderSystemOption" "-vulkan"`, и файл изменён в 03:58, то есть при выходе из игры. Похоже, Vulkan выбран в этой сессии и включится только со следующего запуска. Тогда Deadlock пойдёт через `winevulkan` и MoltenVK движка, а в процесс может попасть чужой ICD из `/usr/local/share/vulkan/icd.d` (KosmicKrisp, MoltenVK) — это R26.

**Как проверить и сравнить.**
- Если в логе нет строк DXMT `Using feature level`, а `rendersystemvulkan.dll` загружен, — рисует Vulkan.
- FPS сравнить в одной сцене с `-dx11` и с `-vulkan` в параметрах запуска.
- Для PEAK: одна и та же сцена при 3024×1890 и при половинном разрешении, плюс MetalFX из меню View.

---

## 5. DX12-игры (RE9) — Фаза 7

**Что видно.** Resident Evil Requiem (`re9.exe`, сторонний ярлык 4022369388): окно создаётся, затем «Unsupported graphics card (0x80004002)» и Aborted.

**Причина по логу.**
- Игра грузит встроенный `d3d12.dll` Wine (vkd3d поверх Vulkan), выгружает его и грузит снова. При этом `dxgi.dll` — от DXMT (`warn: DXGIAdapter: Unknown interface query …`).
- Устройство D3D12 не создаётся; `0x80004002` — это `E_NOINTERFACE`.
- DXMT умеет только D3D10/11 (R31, R18).

**Что делаем.**
- D3DMetal из GPTK — после импорта пользователем.
- Mullion — как эксперимент: только M3+ и macOS 15+, твой M4 Pro подходит.
- RE9 — тестовая игра для обоих. Steamworks на ней не проверить: это сторонний ярлык.

---

## 6. Модальные окна ошибок не должны блокировать автотесты — Фаза 2

**Что видно.** У RE9 сообщение об ошибке — модальное окно, игра ждёт OK. Без человека сессия висит, пока Steam её не остановит. Текста окна нет ни в `notproton-run.log`, ни в `notproton-wine.log`.

**Что делаем** — только для тестового режима. Обычный пользователь окно ошибки должен видеть.
- Сторож: если за N секунд нет первого кадра (`sevo:gfx … first present`), сделать снимок экрана (`screencapture`), записать это в лог и выполнить `wineserver -k` для префикса.
- В тестовых префиксах отключить диалог падения winedbg (`AeDebug`).
- Выяснить, каким каналом `WINEDEBUG` достать текст окна в лог. В `user32/msgbox.c` канал по умолчанию — `dialog`; пишет ли он текст, надо проверить.

**Проверка.** Игра с ошибкой при старте (RE9) в автотесте завершается за N секунд, в логе есть причина и путь к снимку.

---

## 7. Риски VAC от хука steamclient — Фаза 3 (предложение)

**Что видно.** Deadlock — игра Valve с VAC. Ты решил: онлайн-матчи не запускать, пока не выяснены риски хука steamclient (`DECISIONS.md`, VAC).

**Что известно.**
- Хук B2 меняет код `ntdll.dll` в памяти процесса игры: детур в code cave перенаправляет экспорты `steamclient64.dll` на `lsteamclient.dll`.
- Схема та же, что у Proton-Wine (`steamclient_setup_trampolines`), но код трамплинов наш.
- Как это видит VAC, нам неизвестно.

**Что делаем.**
- В Фазе 3 предпочесть B1 и перенести код Proton почти дословно, а не собственный детур.
- Собрать, что известно о VAC под Proton (Linux и Steam Deck) и о модифицированных ntdll.
- Решение, когда возвращаться к онлайн-матчам, — твоё.
