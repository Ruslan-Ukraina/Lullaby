# SPIKE_TEST — ручная проверка Фазы 1 (go / no-go)

Ветка `spike/dormison`. Займёт 30–60 минут плюс время на скачивание игр.
Тебе нужно запустить три игры из Steam и посмотреть на них. Всё, что можно проверить без Steam, уже проверено, итоги — в разделе 0.
Если что-то не так, остановись. Пришли мне номер шага и вывод команды, ничего не чини сам.

Команды в блоках `sh` вставляй в Терминал целиком (Программы → Утилиты → Терминал).

---

## 0. Что уже сделано без тебя (2026-10-06)

| Что | Доказательство |
|---|---|
| Движок Dormison b1 скачан и проверен | подписи `engine.json` и `dormison-b1.tar.xz` валидны (ключ Dormison), sha256 и размер тарбола совпадают с манифестом, все 5004 файла сверены с `engine-manifest.json` |
| Движок установлен в `~/Library/Application Support/notproton/runners/dormison-b1`, `runners/current` указывает туда | `engine/fetch-dormison.sh --activate` |
| Мост (lsteamclient и steam.exe) собран из исходников Dormison `52c2a4b918d6` | все импорты `lsteamclient.so` из ntdll есть в `ntdll.so` движка |
| `ntdll.dll` x86_64 пропатчен (детур steamclient64 → lsteamclient) | статическая проверка `ntdll-patch/verify.py`; тестовая программа под Wine: с патчем `CreateInterface` перенаправлен в `lsteamclient`, без патча — нет |
| DXMT (DirectX 11 через Metal) подключается к игре | тест D3D11: уровень 11_0 на «Apple M4 Pro» через DXMT, и для 64-, и для 32-битной программы |
| Игра запускается из своего бандла (имя и иконка в Dock, Game Mode) | в логе `loader=bundle` для дочернего процесса |
| msync включён | `WINEMSYNC=1`, в логе движка `msync: up and running` |
| Sevoflurane не вызывается (S1) | заглушка `SEVO_CLI` вместо `/usr/local/bin/sevo`, лаунчер без программы сразу выходит, каталог бандла `launchers/app-<appid>` |
| Сигнатуры Steam подходят к установленному клиенту (билд 1788652215) | `make anchorcheck`: 17 из 17 якорей найдены, vptr совпадает |
| `make app` (код 0), все тесты зелёные | 11 C-наборов и 367 Swift-тестов |
| NotProton.app 1.0.2 установлен в `/Applications`, NotProton встроен в `/Applications/Steam.app` | `NotProtonApp --install-into-steam`: компоненты 17 из 17 |
| Автообновление NotProton выключено (В4) | фида апстрима в `Info.plist` больше нет |

Без Steam нельзя было проверить: запуск настоящей игры, ачивки, окно игры, оверлей Steam. Это и есть твоя часть.

---

## 1. Перед началом (5 минут)

### 1.1 На Mac две копии Steam — запускай правильную ⚠️

- `/Applications/Steam.app` — **в неё встроен NotProton**. Запускай её.
- `/Applications/Ігри/Steam.app` — копия **без** NotProton. **Иконка Steam в Dock открывает именно её.**

Как запускать на время проверки — только так:

```sh
open /Applications/Steam.app
```

Или через Finder: Программы → `Steam` (не из папки «Ігри»).
Можешь перетащить `/Applications/Steam.app` в Dock вместо старой иконки — это твоё решение, я Dock не трогал.

### 1.2 Закрой Steam, если он открыт

Steam → Quit Steam (⌘Q). Проверка:

```sh
pgrep -l steam_osx || echo "Steam закрыт"
```

Ожидаемо: `Steam закрыт`.

### 1.3 Обновления Steam (по желанию)

Сигнатуры проверены для текущего клиента, билд 1788652215. Если Steam обновится до билда, который сигнатуры не знают, пункт Steam Play может пропасть до Фазы 5.
Обновления можно запретить: открой **NotProton** (Программы → NotProton) → включи переключатель **Block Steam client updates**. Это твоё решение. Если Steam уже обновился, в шаге 2.2 будет видно, нашлись ли сигнатуры.

### 1.4 Чего не нажимать в NotProton во время проверки

- **Remove Everything → Remove** — удаляет всю папку `~/Library/Application Support/notproton`, то есть движок, мост и резервные копии.
- **Repair Steam → Repair** — убирает NotProton из Steam. Это способ отката, см. раздел 6.
- Всё, что касается CrossOver (**Set Up**, **Copy**, **Use**): в спайке CrossOver не используется.

Что должно быть в окне NotProton:
- «Compatibility Tool: Dormison b1.» (зелёный);
- «NotProton Components: Ready.».

---

## 2. Шаг 1 — Steam видит Dormison

### 2.1 Запусти Steam

```sh
open /Applications/Steam.app
```

Ожидаемо: Steam запускается как обычно, ты входишь в аккаунт.

### 2.2 Проверь, что NotProton встал в Steam

Подожди минуту после входа, затем:

```sh
grep -E "resolved|hooks installed|registered" "$HOME/Library/Application Support/notproton/notproton.log" | tail -6
grep -c "Dormison" "$HOME/Library/Application Support/Steam/compatibilitytools.d/notproton/run"
```

Ожидаемо:
- в первом выводе — строки с сегодняшним временем вида `install_thread: signatures N/N resolved` и `install_thread: ready, N/N hooks installed`, где числа слева и справа от `/` равны;
- во втором — число больше 0. Steam при запуске переписал скрипт запуска на версию для Dormison.

### 2.3 Пункт Steam Play в свойствах игры

Steam → Библиотека → любая игра → ⚙ → **Свойства → Совместимость** (Properties → Compatibility) → галочка «Принудительно использовать выбранный инструмент совместимости Steam Play» (Force the use of a specific Steam Play compatibility tool).

Ожидаемо: в списке есть **Dormison (NotProton)**.

> ❌ Нет пункта: проверь, что Steam запущен из `/Applications/Steam.app` (п. 1.1), и пришли мне вывод из п. 2.2.

---

## 3. Шаг 2 — выбери и поставь 3 игры

Сейчас в Steam установлена только Stardew Valley (нативная Mac-версия). Нужны три Windows-игры из твоей библиотеки.

| Игра | Что должно быть | Что проверяем |
|---|---|---|
| **A** | 64-битная, с достижениями Steam | lsteamclient и ачивки |
| **B** | DirectX 11 (в требованиях магазина: «DirectX: версии 11») | DXMT |
| **C** | проверяет Steam при старте: DRM Steam или «игра должна запускаться через Steam» | Steam API при запуске |

Одна игра может закрыть несколько строк.

**Не бери:**
- 32-битные игры: в этой фазе патч только для x86_64, Steamworks в 32-битных не заработает (это Фаза 3);
- игры с античитом ядра (Easy Anti-Cheat, BattlEye и т.п.);
- онлайн-игры с VAC — на всякий случай.

Для каждой игры:
1. ⚙ → Свойства → Совместимость → галочка → **Dormison (NotProton)**.
2. На той же странице, если есть пункт **Graphics**, оставь **Automatic** (это DXMT).
3. Установи игру. Steam скачает Windows-версию.

Как проверить, что игра 64-битная (после установки; папку с exe открывает ⚙ → Управление → Просмотреть локальные файлы, или Manage → Browse local files):

```sh
python3 ~/Projects/NotProton/bridge/pe-info.py "/путь/к/Игра.exe"
```

Ожидаемо: первое слово вывода `x86_64`. Если `i386` — игра 32-битная, возьми другую.

---

## 4. Шаг 3 — запусти каждую игру и проверь

Делай для каждой игры по очереди.

### 4.1 Запуск — критерий 1

Нажми **Играть** в библиотеке Steam.

Ожидаемо:
- через 10–60 с появляется окно игры (первый запуск дольше: создаётся префикс);
- в Dock — название и иконка игры, а не «wine»;
- Steam показывает, что ты в игре.

### 4.2 Ачивки и статистика — критерий 2

- В игре открой оверлей: **Shift+Tab** → «Достижения» (или страница игры в библиотеке Steam → «Достижения»).
- Если есть простое достижение, получи его. Если нет — посмотри, что Steam считает время в игре и показывает «в игре».

Ожидаемо: достижения видны, выданное засчитывается. Лог проверим в 4.6.

### 4.3 Окно игры — критерий 4

Переведи игру в оконный режим (в её настройках графики), затем:
1. Потяни окно за угол. Ожидаемо: окно меняет размер, картинка масштабируется, а разрешение в игре не меняется.
2. Зелёная кнопка окна (или **Ctrl+⌘+F**). Ожидаемо: нативный полноэкранный режим macOS (отдельный «стол»). Ещё раз — возврат в окно.
3. В строке меню вверху, пока активна игра, есть меню **View**: Upscaler, Final Filter, Resizable Windows (⌥⌘R), Show Frame Rate (⌥⌘F), Show Frame Time Graph (⌥⌘G), Show Picture Details (⌥⌘I).
   Включи **Show Frame Rate**. Ожидаемо: появляется счётчик FPS, а Sevoflurane **не** открывается.

### 4.4 Оверлей Steam — критерий 5

**Shift+Tab** в игре, затем закрой оверлей.

Ожидаемо: оверлей рисуется поверх игры; после закрытия игра идёт дальше.
Запиши, если увидишь: чёрный экран, мерцание, застывший кадр, оверлей не появляется, игра падает.

### 4.5 Выход из игры — критерий 3

Выйди из игры через её меню (Выход). Подожди 15 секунд.

Ожидаемо: Steam снова показывает кнопку «Играть», а не «Остановить», и ничего не висит.

### 4.6 Доказательства из логов — одной командой

После выхода из игры:

```sh
~/Projects/NotProton/engine/spike-check.sh
```

Скрипт сам берёт последнюю запущенную игру (или укажи её appid: `engine/spike-check.sh 123456`). Он показывает строки логов по каждому критерию и пишет `[ok]` или `[FAIL]`.

Ожидаемо для каждой игры:

| Раздел вывода | Что должно быть |
|---|---|
| 1 | `[ok] the run script ran on the Dormison engine` |
| 2 | `[ok] lsteamclient.dll came in ahead of steamclient64.dll…` и `[ok] no lsteamclient errors` |
| 3 | `[ok] WINEMSYNC=1`, `[ok] the engine reports msync running`, `[ok] the session ended…`, `[ok] no Wine processes left` |
| 4 | `[ok] Dormison re-executed the game through the bundle's loader` |
| 5 | для DX11-игры: `[ok] a process drew through DXMT` |
| S1 | `[ok] Sevoflurane.app is not running` |

Логи лежат здесь, если захочешь посмотреть сам (`<appid>` — номер игры, его печатает скрипт):
- лог запуска: `~/Library/Application Support/Steam/steamapps/compatdata/<appid>/notproton-run.log`;
- лог Wine: `~/Library/Application Support/notproton/launchers/app-<appid>/notproton-wine.log`;
- лог хуков Steam: `~/Library/Application Support/notproton/notproton.log`;
- вызовы меню View: `~/Library/Application Support/notproton/notproton-sevo.log`.

Скриншот: **⌘⇧4**, затем пробел и клик по окну. Файл появится на рабочем столе.

---

## 5. Если что-то не так

| Что видишь | Вероятная причина | Что прислать |
|---|---|---|
| Нет «Dormison (NotProton)» в списке | Steam запущен из копии в «Ігри»; или сигнатуры не подошли после обновления Steam | вывод п. 2.2 |
| Игра не запускается или сразу закрывается | — | вывод `spike-check.sh`, последние 60 строк обоих логов |
| Окно «This game needs its prefix rebuilt» | префикс от другой сборки | скриншот |
| `[FAIL] lsteamclient reported errors` | Steam API не поднялся | вывод `spike-check.sh` |
| В Dock «wine» вместо имени игры | игра запускается через свой лаунчер, второй exe не в бандле | имя exe из лога Wine |
| Открылся Sevoflurane | нарушен S1 | сразу напиши, это блокер |

Последние строки логов:

```sh
A=$(basename "$(dirname "$(find "$HOME/Library/Application Support/Steam/steamapps/compatdata" -name notproton-run.log -exec stat -f '%m %N' {} + | sort -rn | head -1 | cut -d' ' -f2-)")")
tail -60 "$HOME/Library/Application Support/Steam/steamapps/compatdata/$A/notproton-run.log"
tail -60 "$HOME/Library/Application Support/notproton/launchers/app-$A/notproton-wine.log"
```

---

## 6. Откат: вернуть всё как было

- **Steam:** NotProton → **Repair Steam → Repair**. Восстанавливает исходный `Info.plist` Steam (из `backups/Info.plist.before-notproton`) и убирает dylib.
- **Резервные копии перед установкой (2026-10-06):**
  - `~/Library/Application Support/notproton/backups/spike-20261006/` — `Info.plist` и `notproton.dylib` из Steam.app от 5 октября, старые `overlay-shim.dylib`, `iconmaker`, `appinfo`, сигнатуры;
  - копия той же папки — `~/Projects/NotProton/scratch/backups/spike-20261006/` (переживёт «Remove Everything»);
  - старый мост — `~/Library/Application Support/notproton/bridge.bak-20261006-spike/`.
- **Движок:** `~/Library/Application Support/notproton/runners/dormison-b1` (~1,1 ГБ). Исходный `ntdll.dll` лежит рядом с пропатченным: `wine/lib/wine/x86_64-windows/ntdll.dll.notproton-orig`.

---

## 7. Что прислать мне

Заполни таблицу (можно просто текстом в чат):

| Критерий GO | Игра A | Игра B | Игра C |
|---|---|---|---|
| 1. Steam Play виден, игра стартует | | | |
| 2. lsteamclient и трамплины в логе, ачивка/статистика работает | | | |
| 3. `WINEMSYNC=1`, выход без зависания | | | |
| 4. Окно: размер с сохранением разрешения, полный экран и обратно | | | |
| 5. Оверлей Steam не конфликтует с презентером | | | |

Плюс названия игр и вывод `engine/spike-check.sh` для каждой. Логи я могу прочитать сам: они остаются на диске, назови только игры.

Затем напиши **GO** или **NO-GO: <что не так>**. Без твоего решения Фазу 2 не начинаю.

---

## 8. Проверка Фазы 2

Собрано: `out/NotProton.app` (ветка `dormison`). Все автоматические проверки зелёные, но игры с новым `compat_run.sh` я не запускал. Заполни по пунктам, в конце напиши **OK** или что не так.

### 8.0 Подготовка

1. Закрой Steam (⌘Q).
2. Открой `~/Projects/NotProton/out/NotProton.app`. Если macOS ругается на подпись — правый клик → «Открыть».
3. Pane **Status** → **Install** (в Steam попадает новый dylib со скриптом запуска). Ожидаемо: «NotProton successfully installed», Steam остановлен или не был запущен.
4. Запусти Steam из `/Applications/Steam.app`.

Ожидаемо: Status не показывает ошибок; в разделе Steam — «Installed (…)».

### 8.1 Блок Engine в Status

Pane **Status**, раздел **Engine**.

Ожидаемо:
- строка «Dormison b1» с зелёной точкой;
- кнопок «Set Up», «Choose…», «Copy» и упоминаний CrossOver нет нигде в окне;
- если установлено больше одного движка, под строкой список версий с кнопками **Use** и **Remove** (у активной их нет). Сейчас установлен один, так что список не покажется — это нормально.

Проверка файла: `cat ~/Library/Application\ Support/notproton/runners/dormison-b1/notproton-engine.env` — 7 строк `NP_ENGINE_…='…'`, пути ведут в `dormison-b1`.

### 8.2 Окно «Настройки игры»

Pane **Prefixes** → выбери игру, в которой ты уже играл → кнопка **Game Settings…** на панели (или правый клик по игре).

Ожидаемо:
- открывается окно с разделами Graphics, Window, Picture, Input, Performance; у каждой строки есть значок (i), по клику — пояснение;
- у игры, ни разу не запускавшейся после этой сборки, вместо настроек — «Launch the game once». Это нормально: имя exe записывается при запуске. Запусти игру, закрой, открой окно снова;
- значения «From the prefix» — наследование от профиля префикса.

Сделай: Renderer → **DXVK**, Frame rate counter → **On**, Resizable window → **Every window**, **Save**.

Проверка файла: `cat "<Steam>/steamapps/compatdata/<appid>/pfx/.sevo/apps/<exe>.env"` (exe в нижнем регистре). Ожидаемо: строки `NOTPROTON_RENDERER=dxvk`, `SEVO_FPS=1`, `SEVO_RESIZABLE_WINDOWS=all`; прежняя строка `SEVO_LOADER=…` на месте.

### 8.3 Выбор рендерера в панели Steam

Steam → игра → ⚙ → Свойства → **Совместимость** → включи принудительное использование «Dormison (NotProton)».

Ожидаемо:
- под выбором инструмента один раздел **Graphics** с одним выпадающим списком: Automatic (DXMT), DXMT, DXVK, WineD3D. Переключателей Metal HUD, DLSS, MSync, MetalFX там больше нет;
- выбери **DXMT** → в «Параметры запуска» появилось `NOTPROTON_RENDERER=dxmt`; выбери **Automatic** → строка исчезла; твои прочие параметры (например `-novid`) остались.

### 8.4 Настройки применяются в игре

Игра из 8.2 (Renderer DXVK, FPS On, Every window). Запусти из Steam.

Ожидаемо:
- на экране счётчик FPS; окно тянется за угол;
- `engine/spike-check.sh <appid>`: в п. 5 строка `renderer: dxvk`, п. 5 без FAIL;
- в меню **View** переключи Show Frame Rate выключить, выйди из игры, запусти снова: счётчика нет (выбор из меню сохранился), в `.env` — `SEVO_FPS=0`;
- верни в окне Game Settings Renderer = **From the prefix**, Save: следующий запуск снова через DXMT (`renderer: dxmt` в логе).

Если игра с DXVK не стартует — это находка, а не твоя ошибка: напиши игру и что случилось.

### 8.5 Остановка из Steam

1. Запусти любую игру, дождись окна.
2. В Steam нажми **Остановить** (на странице игры вместо «Играть»).
3. Подожди 15 секунд.
4. Выполни: `engine/spike-check.sh` (без аргументов — последняя игра).

Ожидаемо: п. 3 «the session ended and the prefix was shut down» с `[ok]`, «no Wine processes of ours left» `[ok]`, в конце `0 failed`.

В журнале запуска (`<Steam>/steamapps/compatdata/<appid>/notproton-run.log`) последние строки сессии:
```
=== termination signal received, killing wine prefix ===
=== termination signal, session ending ===
```
Ни одного процесса Wine после этого (`pgrep -fl wineserver` пусто, если Sevoflurane не открыт).

Повтори один раз с обычным выходом из игры (меню игры → Выход) — финал `=== wine prefix killed, session ending ===` должен появиться не позже чем через ~15 с.

### 8.6 Что прислать

Таблица пунктов 8.1–8.5: ok / не ok и что видел. Логи я прочитаю сам, назови игры и время, когда нажимал «Остановить».

---

## 9. Проверка Фазы 3 (lsteamclient «по-взрослому») и эксперимент п. 8

Что изменилось:
- **B1.** `ntdll.dll` обеих архитектур собрана из исходников Dormison с хуком steamclient → lsteamclient (`DECISIONS.md` P3-1). Она уже стоит в `runners/dormison-b1` и в мосте. Рядом лежат `.notproton-orig` (релиз) и `.notproton-b2` (спайк).
- **lsteamclient** получил интерфейсы `SteamNetworkingSocketsSerialized005` и `SteamAppDisableUpdate001` (P3-2). Он уже в мосте.
- Без меня проверено: хук на тестовой программе (x86_64 и i386) и оба интерфейса на живом клиенте Steam. Игры я не запускал.

**Онлайн-игры с VAC не запускай** (`RISKS.md`, раздел «R33: VAC»). Deadlock — только до главного меню.

### 9.0 Подготовка

1. Закрой Steam (⌘Q).
2. Открой `~/Projects/NotProton/out/NotProton.app` → **Status** → **Install**. В Steam попадёт новый скрипт запуска, который пишет в лог, какая `ntdll` стоит (B1).
3. Открой Steam из `/Applications/Steam.app`.

### 9.1 64-битные игры не сломаны: PEAK, ETS2, Deadlock

Для каждой: запусти, дождись меню или игры, выйди из игры, подожди 15 с, затем `engine/spike-check.sh <appid>` (PEAK 3527290, ETS2 227300, Deadlock 1422450).

Ожидаемо:
- в п. 2 — `[ok] the B1 loader hook led steamclient to lsteamclient` и строка `steamclient64.dll: 40 exports and the entry point lead to lsteamclient.dll …`;
- в run-логе (`<Steam>/steamapps/compatdata/<appid>/notproton-run.log`) — `runner: x86_64 ntdll is the patched copy (B1)` и `runner: i386 ntdll is the patched copy (B1)`;
- достижения и статистика в оверлее (Shift+Tab) видны, как в Фазе 1;
- **Deadlock** (только меню): ошибок про 005 и AppDisableUpdate больше нет. Проверка:
  `grep -a "Don't recognize interface" "$HOME/Library/Application Support/notproton/launchers/app-1422450/notproton-wine.log"` — пусто (раньше было `SteamNetworkingSocketsSerialized005` и `SteamAppDisableUpdate001`). Итог `spike-check.sh` — без FAIL в п. 2.

### 9.2 32-битная игра: The Binding of Isaac: Rebirth (250900)

Нашёл по exe: `isaac-ng.exe` — i386, рядом 32-битный `steam_api.dll` (Steamworks, достижения). Игра есть у твоего аккаунта, но установлена только в `~/GameHub` — этой библиотеки Steam не знает. **Добавлять `~/GameHub` в Steam не надо**: там же лежит второй PEAK.

1. В Steam: The Binding of Isaac: Rebirth → ⚙ → **Свойства** → **Совместимость** → включи «Принудительно использовать» → **Dormison (NotProton)**. Делай это **до** установки: иначе Steam поставит версию для macOS.
2. **Установить** (около 1,6 ГБ).
3. **Играть.** Первый запуск дольше: создаётся префикс с 32-битной частью (`syswow64`).

Ожидаемо:
- игра запускается, в Dock — её имя и иконка;
- в оверлее (Shift+Tab) видны достижения Isaac, Steam показывает «в игре»; если получится — открой любое достижение и убедись, что оно засчиталось (страница игры → Достижения);
- `engine/spike-check.sh 250900`, п. 2: `steamclient.dll: 40 exports and the entry point lead to lsteamclient.dll …` и `[ok] the B1 loader hook …`. В п. 5 строки про DXMT может не быть: Isaac рисует через OpenGL, это нормально;
- в run-логе — `installed syswow64 lsteamclient trigger` при первом запуске.

Если Isaac не стартует или достижения не видны — пришли время запуска, остальное я прочитаю в логах сам.

### 9.3 Эксперимент п. 8: «Also borderless full screen» на PEAK

Цель — понять, лечит ли режим Dormison `ResizableWindows=window` поломку полноэкранного режима самой игры (0 fps, картинка смещена).

1. NotProton → **Prefixes** → PEAK → **Game Settings…** → Resizable window = **Also borderless full screen** → **Save**.
2. Запусти PEAK. В настройках графики игры по очереди:
   - **оконный режим без рамки / Fullscreen Window** (если есть): картинка? fps? окно можно двигать и тянуть? зелёная кнопка — нативный полноэкранный режим?
   - **эксклюзивный полноэкранный / Exclusive Fullscreen**: картинка на месте? fps?
3. Выйди, верни в Game Settings Resizable window = **From the prefix**, Save.

Запиши для каждого режима: картинка (нормальная / смещена / чёрная), fps, работает ли выход обратно в окно. По логу я проверю, что настройка дошла: в `.sevo/apps/peak.exe.env` должно быть `SEVO_RESIZABLE_WINDOWS=window`.

### 9.4a Кнопки Update и Reinstall в NotProton.app

Что изменилось: Status сравнивает то, что стоит в Steam, с тем, что внутри приложения, по содержимому (а не по номеру версии). Под «Installed (1.0.2)» теперь виден build и дата установки.

1. Открой `~/Projects/NotProton/out/NotProton.app` → **Status**. Ожидаемо: `NotProton — Installed (1.0.2)`, ниже `Build 47B89F80, installed 6 Oct 2026 at 15:32.` (это я поставил в 15:32), строка **Reinstall NotProton** с кнопкой **Reinstall**.
2. При открытом Steam нажми **Reinstall**. Ожидаемо: вопрос «Close Steam to install?». Нажми **Close Steam and Install**. Steam закроется, появится `Done — NotProton reinstalled (build 47B89F80). Steam was stopped, so start it again.` и кнопка **Open Steam**. Нажми её — Steam откроется.
   Steam закрывается сам, обычно за несколько секунд (`steam://exit`, затем штатный Quit). Если за 45 с он не закрылся — `Failed — Steam did not quit within 45 seconds. Quit Steam yourself (Steam → Quit Steam, or ⌘Q), then press Retry.` и кнопка **Retry**: закрой Steam сам и нажми её.
3. Запусти любую игру и, пока она идёт, нажми **Reinstall**. Ожидаемо: `Failed — A game is running under NotProton. Quit the game, then try again.` Steam не закрывается.
4. «Update available» сам увидишь, когда я в следующий раз соберу приложение с изменённым скриптом запуска: строка станет оранжевой, в подробностях — `Out of date: Steam patch, run script.` и кнопка **Update**.

Если что-то не так — пришли время, остальное я посмотрю в `~/Library/Application Support/notproton/app.log` (строки `install:` и `state patch`).

### 9.4 Что прислать

| Пункт | PEAK | ETS2 | Deadlock (меню) | Isaac (32 бит) |
|---|---|---|---|---|
| Запуск | | | | |
| B1 в `spike-check.sh` (п. 2) | | | | |
| Достижения / оверлей | | | — | |
| Ошибки `Don't recognize interface` | | | | |

Плюс 9.4a: Reinstall → вопрос → Open Steam (да/нет); Reinstall во время игры → отказ (да/нет).

Плюс 9.3: режим → картинка, fps. Затем — **OK** или что не так.

---

## 10. Проверка Фазы 4: обновление движка из NotProton.app

Что изменилось: движок теперь ставит, переустанавливает и откатывает само приложение (Status → **Engine**), без Терминала. Порядок такой:
1. подписанный список Dormison;
2. загрузка с докачкой;
3. размер, sha256 и подпись;
4. каждый файл по `engine-manifest.json`;
5. наш B1-`ntdll`;
6. проверочный запуск Wine во временном префиксе;
7. переключение.

Предыдущая копия остаётся для отката (`DECISIONS.md` P4-1…P4-7).

Без тебя проверено на отдельной копии движка, не на твоей (PROGRESS, 6 октября, ~17:35):
- загрузка, оборванная на 16,6 МБ, продолжилась с того же байта (сервер ответил 206);
- проверка, B1 и проверочный запуск прошли;
- переустановка отложила старую копию, откат дважды поменял копии местами;
- файлы совпадают с твоим `runners/dormison-b1`.

Твой движок я не трогал. Игры не запускал.

**Онлайн-игры с VAC не запускай.**

### 10.0 Подготовка

1. Закрой NotProton, если открыт. Открой `~/Projects/NotProton/out/NotProton.app` (свежая сборка).
2. Steam можно не закрывать: приложение само спросит. Убедись, что ни одна игра не запущена.
3. Нужно ~1,5 ГБ свободного места и интернет: каждая переустановка заново скачивает 233 МБ.

### 10.1 Блок Engine

Status → раздел **Engine**. Ожидаемо:
- **Engine** — `Dormison b1`, ниже `Wine 11.16 + wine-staging 11.16, commit 52c2a4b918d6.`;
- **Updates** — `Up to date.`, ниже `Checked ЧЧ:ММ.`; кнопки **Check for Updates** и **Reinstall**. Приложение проверяет список Dormison само при открытии;
- **Update channel** — `Beta`. Stable не выбирай: у Dormison пока нет стабильного релиза. Если выберешь, увидишь `No stable Dormison release yet. Switch the channel to Beta to get one.`;
- строки **Previous engine** пока нет.

Нажми **Check for Updates**. Ожидаемо: снова `Up to date.`, время обновилось.

### 10.2 Переустановка той же версии (Reinstall)

1. В строке **Updates** нажми **Reinstall**.
2. Если Steam открыт, появится вопрос «Close Steam to change the engine?». Нажми **Close Steam and Continue**. Steam закроется не сразу, а после проверки, перед самым переключением.
3. Вверху меняются этапы. Займёт 2–5 минут:
   - `Downloading the engine (… of 233 MB)`;
   - `Verifying the download`;
   - `Unpacking the engine`;
   - `Checking the engine's files`;
   - `Adding the Steam loader patch`;
   - `Testing the engine`;
   - `Stopping Steam`;
   - `Switching engines`;
   - `Cleaning up`.

Ожидаемо:
- `Done — Dormison b1 reinstalled. The copy it replaced is kept: Roll Back returns to it. Steam was stopped, so start it again.` и кнопка **Open Steam**;
- новая строка **Previous engine** — `Dormison b1, the other copy from the last reinstall.` с кнопкой **Roll Back**.

Если Steam не закрылся за 45 с — `Failed — Steam did not quit within 45 seconds…` и кнопка **Retry**. Закрой Steam сам (⌘Q) и нажми **Retry**.

Проверка в Терминале (по желанию):
```sh
ls -a "$HOME/Library/Application Support/notproton/runners"
ls "$HOME/Library/Application Support/notproton/runners/dormison-b1/wine/lib/wine/x86_64-windows" | grep notproton
```
Ожидаемо:
- первая команда: `.previous-dormison-b1  current  dormison-b1  previous`;
- вторая: только `ntdll.dll.notproton-orig`. Спайкового `.notproton-b2` в новой копии нет — он остался в старой.

### 10.3 PEAK после переустановки

1. Нажми **Open Steam** (или открой `/Applications/Steam.app`).
2. PEAK → **Играть**. Дождись меню, выйди из игры. Подожди 15 с.
3. В Терминале:
   ```sh
   cd ~/Projects/NotProton && engine/spike-check.sh 3527290
   ```

Ожидаемо:
- PEAK запустился как раньше, в Dock — его имя и иконка;
- `spike-check.sh` — 10 ok, 0 failed, в п. 2 `[ok] the B1 loader hook led steamclient to lsteamclient`;
- в run-логе — `runner: x86_64 ntdll is the patched copy (B1)` и такая же строка для i386.

### 10.4 Откат (Roll Back)

1. Status → **Previous engine** → **Roll Back**.
2. Если Steam открыт — «Close Steam to change the engine?» → **Close Steam and Roll Back**.

Ожидаемо:
- за несколько секунд появляется `Done — Back on Dormison b1 (the other copy from the last reinstall).` и кнопка **Open Steam**. Ничего не скачивается;
- строка **Previous engine** осталась: второе нажатие вернёт копию из 10.2.

Проверка (по желанию): команда `ls … | grep notproton` из 10.2 снова показывает `ntdll.dll.notproton-b2` и `ntdll.dll.notproton-orig`. Значит, на месте копия, которая была до переустановки.

### 10.5 PEAK после отката

Повтори 10.3. Ожидаемо то же самое: PEAK в меню, `spike-check.sh 3527290` — 10 ok, 0 failed.

### 10.6 Отказ во время игры

1. Запусти PEAK и, пока он идёт, нажми **Reinstall** (или **Roll Back**).
2. Ожидаемо: `Failed — A game is running under NotProton. Quit the game, then try again.` Ничего не скачивается, Steam не закрывается.
3. Выйди из PEAK.

### 10.7 По желанию: нет сети и прерванная загрузка

- Выключи Wi-Fi → **Check for Updates**. Ожидаемо: `Failed — Check for engine updates: NotProton could not reach GitHub. Check your internet connection and try again.` Движок не меняется.
- Нажми **Reinstall**, на этапе `Downloading the engine` выключи Wi-Fi. Ожидаемо: `Failed — Update the engine: The download stopped. NotProton could not reach GitHub… What arrived is kept, and the next try continues from there.` Включи Wi-Fi, снова **Reinstall**. Загрузка продолжится с того же места, в `app.log` будет строка `engine: server resumed the download at byte … (206)`.

### 10.8 Что прислать

| Шаг | Результат |
|---|---|
| 10.1 Блок Engine, Check for Updates | |
| 10.2 Reinstall → Done, строка Previous engine | |
| 10.3 PEAK после переустановки (`spike-check`) | |
| 10.4 Roll Back → Done | |
| 10.5 PEAK после отката (`spike-check`) | |
| 10.6 Отказ во время игры | |

Если что-то пошло не так — пришли время. Строки `engine:` в `~/Library/Application Support/notproton/app.log` я прочитаю сам.

После проверки можно оставить любую из двух копий. Вторая (~1,1 ГБ) удалится сама при следующем обновлении движка.

---

## 11. Проверка пункта 15: нативные окна Steam

Что изменилось: окна Steam получили настоящую рамку macOS. Это светофоры над верхним рядом Steam, скруглённые углы и системная тень. Окна теперь работают с полноэкранным режимом, Постановщиком и тайлингом, двойной клик по верхней панели работает как по заголовку. Нарисованные кнопки Valve скрыты. Подробно — `DECISIONS.md` W2–W7.

**Сейчас переключатель включён** (ты просил так оставить). Steam уже перезапущен с ним.

**Как выключить:**
- NotProton.app → **Status** → раздел **Steam** → **Native Steam windows** → выключить → в строке **Done** нажать **Restart Steam**.
- Без приложения:
  ```sh
  echo off > "$HOME/Library/Application Support/notproton/steam-windows"
  ```
  затем закрыть Steam (⌘Q) и открыть снова.

Выключено — Steam такой же, как раньше: dylib окна не трогает, CSS не меняет (проверено, строк `steamwin:` в логе нет).

**Снимки** лежат у тебя на Mac, в `~/Projects/NotProton/scratch/steam-windows/report/` (в git их нет: там видны имя аккаунта, друзья и почта):
- `compare-main-friends.jpg` — главное окно и друзья, слева «до», справа «после»;
- `compare-settings-properties-about.jpg` — настройки, свойства PEAK и «Про Steam», «до» и «после»;
- `title-row-left.jpg`, `title-row-right.jpg` — светофоры на одной линии с кнопками Steam;
- `native-fullscreen.jpg` — нативный полноэкранный режим;
- `double-click-zoom.jpg` — окно после двойного клика по панели;
- `notproton-toggle.jpg` — переключатель в NotProton.app.

Все снимки сделаны после перезапуска Steam со свежей сборкой. Полный набор — в `scratch/steam-windows/`: файлы `before-*`, `final-*`, `after-*`.

**Чем похоже на Sevoflurane:**
- светофоры поверх собственного ряда Steam;
- заголовок прозрачный и без текста;
- пустая панель unifiedCompact опускает светофоры на уровень кнопок Steam;
- кнопки Valve скрыты.

**Чем отличается:**
- Sevoflurane прячет полоску меню Steam и переносит меню в строку меню macOS. У нас Steam для macOS уже сам показывает меню в строке меню, поэтому её не трогаем;
- окна создаёт сам Steam (SDL + CEF), а не Sevoflurane, поэтому рамка добавляется к готовым окнам Steam.

Если сможешь открыть Sevoflurane рядом, сравни главное окно: высоту светофоров, отступ слева, углы и тень. Расхождения запиши словами.

### 11.1 Главное окно: вид и клики

1. Открой Steam (`/Applications/Steam.app`). Ожидаемо: слева вверху цветные светофоры macOS, плоских кнопок Valve нет, углы окна скруглены, тень как у других окон.
2. Нажми по очереди на всё в верхнем ряду и под ним:
   - **КРАМНИЦЯ / БІБЛІОТЕКА / СПІЛЬНОТА / имя**;
   - стрелки назад и вперёд;
   - справа: объявления, колокольчик, аватар, иконка Big Picture.

   Ожидаемо: всё нажимается, как раньше.
3. Наведи курсор на светофоры: появляются значки ×, −, ⤢.

### 11.2 Перетаскивание и двойной клик

1. Перетащи окно за пустое место верхней панели (между вкладками и кнопками справа). Ожидаемо: окно двигается.
2. Дважды кликни по тому же пустому месту. Ожидаемо: то, что выбрано в «Системные настройки → Рабочий стол и Dock → Двойной клик по заголовку окна». По умолчанию — окно разворачивается на весь экран. Ещё раз — возвращается.
3. Двойной клик по вкладке или кнопке не должен разворачивать окно.

### 11.3 Размер, сворачивание, полноэкранный режим

1. Потяни окно за край и за угол. Ожидаемо: размер меняется, содержимое Steam подстраивается.
2. **Жёлтая кнопка** — окно уходит в Dock. Клик по нему — возвращается. Это я не проверил: Постановщик держал Steam в боковой ленте.
3. **Зелёная кнопка** — нативный полноэкранный режим. Ожидаемо:
   - верхний ряд Steam виден целиком: аватар, колокольчик;
   - при наведении к верху экрана выезжает заголовок со светофорами.

   Выход — зелёной кнопкой или Ctrl+⌘F. После выхода светофоры снова на одной линии с кнопками Steam.
4. Наведи на зелёную кнопку и подержи — меню раскладки («Переместить влево/вправо», «Заполнить»). Выбери «влево». Ожидаемо: Steam занимает левую половину. Перетаскивание окна к краю экрана тоже раскладывает его.

### 11.4 Постановщик (Stage Manager)

1. С включённым Постановщиком переключись на Steam и обратно на другое приложение.
2. Ожидаемо: окна Steam собираются в свою группу, как у обычного приложения. В боковой ленте — миниатюра Steam, клик по ней возвращает Steam.
3. Открой друзей и настройки (шаг 11.5) — они должны быть в той же группе.

### 11.5 Все окна Steam

Открой и проверь в каждом: светофоры, скругления, тень, перетаскивание за верх, кнопки Steam нажимаются.

| Окно | Как открыть | Ожидаемо |
|---|---|---|
| Друзья | «Друзі й чат» справа внизу | три светофора поверх аватара — там же, где были кнопки Valve |
| Чат | двойной клик по другу | как у друзей. **Это я не проверял** |
| Настройки | Steam → Налаштування (или `open steam://settings/`) | три светофора над «НАЛАШТУВАННЯ STEAM» |
| Свойства игры | PEAK → ⚙ → Властивості (или `open steam://gameproperties/3527290`) | три светофора над «PEAK» |
| «Про Steam» | Steam → Про Steam (или `open steam://open/about`) | **только красная** кнопка — как у Valve. Кнопка «Закрити» работает |
| Серверы | меню Вигляд → сервери (или `open steam://open/servers`) | три светофора |
| Меню и выпадающие списки | наведи на «БІБЛІОТЕКА», открой «Огляд» | без рамки и без светофоров, как раньше |

### 11.6 Игра и оверлей

1. Запусти PEAK, нажми **Shift+Tab**. Ожидаемо: оверлей Steam такой же, как раньше (он рисуется в кадре игры, функция его не трогает). Я проверил только запуск: `spike-check.sh 3527290` — 10 ok.
2. Выйди из игры.

### 11.7 Выключение

1. NotProton.app → Status → **Native Steam windows** → выключить. Ожидаемо: `Done — Native Steam windows are off. Restart Steam to apply.` и кнопка **Restart Steam**.
2. Нажми **Restart Steam**. Ожидаемо: Steam закрывается сам (если нет — **Retry**) и открывается. Окна снова как у Valve: плоские кнопки, квадратные углы.
3. Включи обратно тем же переключателем и **Restart Steam** — если понравилось.

### 11.8 Что прислать

| Шаг | Результат |
|---|---|
| 11.1 Вид и клики в главном окне | |
| 11.2 Перетаскивание, двойной клик | |
| 11.3 Размер, жёлтая, зелёная, раскладка | |
| 11.4 Постановщик | |
| 11.5 Друзья / чат / настройки / свойства / «Про Steam» / меню | |
| 11.6 Оверлей в PEAK | |
| 11.7 Выключение и включение | |
| Сравнение с Sevoflurane | |

Если что-то не так — пришли время и название окна. Строки `steamwin:` в `~/Library/Application Support/notproton/notproton.log` я прочитаю сам.

### 10.9 Исправление после твоей проверки (P4-8)

Теперь **Reinstall** сначала скачивает и проверяет движок при открытом Steam: этапы идут вверху окна, Steam работает. Когда движок готов, появляется вопрос **«Close Steam to switch engines?»** с кнопкой **Close Steam and Switch**. По нажатию Steam закрывается сразу, за несколько секунд, и движок переключается. **Cancel** — подготовленный движок удаляется, текущий остаётся. Если вопрос закрыть, не ответив, в строке **Updates** будет «Dormison b1 is ready to switch to» и кнопка **Close Steam and Switch**.

Проверено мной через тот же путь, что у кнопок (приложение с окном, ключ `--ui-test-engine-reinstall`): вопрос появился при открытом Steam, после «нажатия» Steam закрылся за 2 с, `Done — Dormison b1 reinstalled…`. Повторять не обязательно. Если захочешь, нажми **Reinstall** при открытом Steam и дождись вопроса.

### 11.9 Повторная проверка после твоих замечаний

1. **Окно друзей:** аватар и имя теперь ниже светофоров (сдвиг 12 px), светофоры на прежнем месте.
2. **«Ігрові сервери» и «Гравці»:** заголовок ниже светофоров. Главное окно, настройки и свойства игры не изменились.
3. **Spaces и Постановщик.** Окнам Steam задано стандартное поведение: `managed`, `participatesInCycle`, `fullScreenPrimary`, ничего «на всех пространствах». Повтори своё воспроизведение: открыть Steam → свайпом перейти на полноэкранное приложение. Запиши, остаётся ли окно Steam поверх и можно ли его двигать.

   По диагностике корень, скорее всего, не в окнах, а в процессе: окнами владеет Steam Helper — фоновое приложение (`UIElement`, без значка в Dock), а значок в Dock у другого процесса, `steam_osx` (DECISIONS W9). Тогда п. 3 не изменится, и поможет эксперимент 11.10.

### 11.10 Эксперимент Б (по желанию, 1 минута, ничего не ломает)

Временно сделать Steam Helper обычным приложением, без пересборки и перезапуска (DECISIONS W10, вариант Б).

1. Steam открыт, переключатель Native Steam windows включён.
2. В Терминале:
   ```sh
   echo "policy regular" > "$HOME/Library/Application Support/notproton/steam-windows-debug"
   ```
3. Ожидаемо: в Dock появится второй значок — «Steam Helper».
4. Повтори воспроизведение из 11.9 п. 3. Проверь ещё:
   - Постановщик;
   - Cmd-Tab;
   - Mission Control;
   - что в строке меню, когда активно окно Steam.
5. Вернуть как было: `echo "policy accessory" > …/steam-windows-debug` (тот же путь) или просто перезапустить Steam.

Запиши: стало ли поведение обычным и насколько мешает второй значок. От этого зависит, делать ли вариант Б постоянным (отдельным словом переключателя).

### 11.11 Steam как обычное приложение (вариант Б, доведённый; DECISIONS W11)

**Сейчас включено** (`notproton/steam-windows` = `native-app`), Steam перезапущен с этим режимом. Выключить: NotProton.app → Status → **Steam as a regular app (experimental)** → выключить → **Restart Steam**. Рамка останется. Мигание из твоей проверки было петлёй фокуса между `steam_osx` и Steam Helper — она устранена.

1. **Мигание.** Открой Steam, кликни в его окно, переключись на другое приложение и обратно (кликом, через Cmd-Tab, через значок Steam в Dock). Ожидаемо: окно не мигает, фокус не прыгает.
2. **Spaces.** Твоё воспроизведение: Steam → свайп на полноэкранное приложение. Ожидаемо: окна Steam остаются в своём пространстве и не висят поверх. При переключении пространств тебя не возвращает к Steam.
3. **Постановщик.** Окна Steam (главное, друзья, настройки) — одна группа, как у обычного приложения.
4. **Dock.** Два значка Steam: прежний (`steam_osx`) и второй с тем же логотипом — это Steam Helper, имя при наведении «Steam Helper». Клик по любому выводит окно Steam. **Не выбирай «Завершить» на втором значке:** закроется интерфейс, а не Steam. Steam закрывай как обычно.
5. **Строка меню.** Когда активно окно Steam, наверху меню Steam («Steam, Акаунт, Вигляд, Друзі, Ігри, Вікно, Довідка»). Проверь, что пункты срабатывают: например, Вигляд → Бібліотека, Steam → Налаштування.
6. Запиши, что лучше для тебя: этот режим или просто Native Steam windows без него.

### 11.12 После последних правок (диалоги, оверлей, одна иконка)

Режим «Steam as a regular app» включён. Steam сейчас закрыт: в 00:20 он вышел по `steam://exit` — это не наш обработчик, похоже, его закрыл ты. Открой Steam сам.

1. **Одна иконка.** В Dock один значок Steam, при наведении — «Steam».
   - Клик по нему — библиотека.
   - Правый клик — «Крамниця / Бібліотека / Друзі» и системные пункты.
   - «Завершити» — Steam закрывается целиком (проверено мной).
   - Закрой все окна Steam крестиком: значок остаётся (это уже `steam_osx`). Клик по нему открывает Steam.
2. **Диалоги.** Открой «Вибрати параметр запуску» у ETS2 (Грати ▾ или «Завжди використовувати» снят). Кнопка закрытия — слева вверху, на стандартном месте, заголовок игры ниже неё. Так же — «Про Steam», «Ігрові сервери», «Гравці».
3. **Оверлей.** Запусти ETS2 или PEAK, Shift+Tab, открой друзей, обзор игры и браузер. Ожидаемо: у окон оверлея есть кнопки Valve (закрыть, свернуть), отступы как раньше. Проверить это сам я не успел: PEAK остановил выход Steam в 00:20:26.
4. **Строка меню.** Пока активно окно Steam, наверху меню Steam. Проверь, что пункты работают.

### 11.13 После доделок 7 октября

Режим «Steam as a regular app» включён, Steam открыт.

1. **Диалоги.** «Вибрати параметр запуску» у ETS2, «Про Steam», «Ігрові сервери», свойства игры: под кнопкой закрытия ни чёрной полосы, ни полосы другого оттенка.
2. **Dock.** Пока открыто окно Steam, в Dock два значка Steam:
   - `steam_osx` — он на месте всегда;
   - Helper — с тем же значком, что Steam.app. При наведении он пока называется «Steam Helper» (DECISIONS W15).

   Клик по значку Helper открывает библиотеку, «Завершити» закрывает весь Steam.
3. **Запуск игры.** Steam не закрывается, игра работает. Проверено мной на PEAK: запуск, оверлей Shift+Tab, выход, `spike-check` 10 ok.
4. **Оверлей.** В окнах оверлея кнопки Valve на месте: у «Огляд гри» видна красная кнопка Valve (снимок `scratch/steam-windows/ov2-overlay.png`).

### 11.14 Имя и значок Steam Helper, Постановщик

NotProton уже поставлен (сборка `83FBEDB0`), Steam перезапущен. Режим «Steam as a regular app» включён.

1. **Dock.** Открой библиотеку Steam. В Dock два значка Steam (так и задумано, W18).
   - Наведи на второй значок. Ожидаемо: подпись «Steam», а не «Steam Helper». Значок такой же, как у Steam.app, и чёткий.
2. **Постановщик.** Переключись на другое приложение, чтобы окно Steam ушло в боковую полосу.
   - Ожидаемо: в полосе миниатюра окна Steam со значком Steam.
   - Если окна в полосе нет или значок пустой, опиши, что видно: окна нет совсем, окно есть, но без значка, или окно пропадает через несколько секунд. Где смотреть: `~/Library/Application Support/notproton/notproton.log`, строки `focus[helper] Steam Helper is now …`.
3. **Откат.** NotProton → Repair Steam.
   - Ожидаемо: в `~/Library/Application Support/notproton/app.log` есть строка `steam helper: NotProton's name and icon files removed`, а во втором значке снова «Steam Helper».
   - После проверки поставь NotProton обратно (Install).

> **§11–§11.14 больше не актуальны:** нативные окна Steam отложены (DECISIONS W19, BACKLOG «Отложено»). Переключатели выключены, Steam выглядит как до задачи.

## 12. Проверка Фазы 5: мост, сигнатуры и обновления Steam

Всё — в окне NotProton, Терминал не нужен. Логи смотрю я, напиши мне «логи».

**Что уже сделано без тебя (7 октября, ~12:55):**
- `/Applications/NotProton.app` — новая сборка. Прежняя — в `scratch/backups/NotProton.app-20261007-before-phase5`.
- Сборка подключена к **тестовому фиду** — папке `scratch/testfeed/feed` с тестовым ключом. Боевой ключ ты создашь в Фазе 6 (DECISIONS P5-7). В фиде:
  - мост «revision 2» — те же файлы, что встроенный, под новым номером;
  - список сигнатур, serial 1.
- Тот же цикл я прогнал без окна на отдельном дереве: установка моста, откат туда и обратно, появление сигнатур, повтор старого списка (PROGRESS, 7 октября).

### 12.1 Обнови патч в Steam

1. Открой NotProton → **Status**.
   Ожидаемо: в строке «NotProton» — «Update available», «Out of date: Steam patch». Это новый `notproton.dylib`: базы сигнатур от новой к старой и возврат блока обновлений.
2. Нажми **Update** → «Close Steam and Install» → **Open Steam**.
   Ожидаемо: «NotProton successfully installed (build CB60C778)». Steam открывается, в нём есть Steam Play.

### 12.2 Обновления Steam

1. Строка **Steam updates**. Ожидаемо: «Steam stays on build 1788652215 because you blocked its updates.»
   Твой блок, поставленный до Фазы 5, сохранён как ручной.
2. Выключи **Block Steam client updates**.
   - Ожидаемо в «Done»: «NotProton manages Steam updates. Steam 1788652215 is current and supported.»
   - Строка «Steam updates» становится зелёной.
   - Блок в Steam при этом остаётся: так задумано (P5-4). NotProton снимает его, только когда Valve предложит билд с сигнатурами.
3. Включи переключатель снова и подтверди «Block Updates».
   Ожидаемо: «Steam client updates are blocked until you turn this off.»
   Оставь его в том положении, которое тебе нужно. Для п. 12.5 — выключенным.

### 12.3 Сигнатуры

Строка **Steam signatures**. Ожидаемо:
- «Supported Steam builds: 1790904859, 1789086785, 1788652215 and 1 more.»;
- ниже — «Newest database: 1790904859.json. New databases come from NotProton's signed releases…».

Нажми **Check Now** в «Steam updates». Ожидаемо: «Checked ЧЧ:ММ», ошибок нет.

### 12.4 Мост (Steam Bridge)

1. Прокрути до раздела **Steam Bridge**. Ожидаемо:
   - «Steam bridge — Revision 1 for Dormison b1 (built in).», commit `52c2a4b918d6`;
   - «Updates — Steam bridge revision 2 for Dormison b1 is available.» и кнопка **Update**.
2. Нажми **Update**. Steam закрывать не нужно.
   - Ожидаемо: «The Steam bridge is now revision 2 for Dormison b1. bridge-dormison-b1-1 is kept for Roll Back…»;
   - строка «Revision 2 … (downloaded)»;
   - появилась строка **Previous Steam bridge** с кнопкой **Roll Back**.
3. Нажми **Roll Back**. Ожидаемо: «The Steam bridge is back on bridge-dormison-b1-1.» и снова «(built in)».
4. Нажми **Update** ещё раз: для игры оставим ревизию 2.
5. Во время игры (п. 12.5) нажми **Update** или **Roll Back**.
   Ожидаемо — отказ: «A game is running under NotProton. Quit the game, then try again.»

### 12.5 Игра с новым мостом

Запусти PEAK, дойди до главного меню, выйди. Ожидаемо: всё как раньше, оверлей Shift+Tab работает. Напиши «PEAK ок» — я прогоню `engine/spike-check.sh 3527290` и посмотрю логи.

### 12.6 По желанию: «Steam N вышел, ждём поддержку» на бете Steam

⚠️ Steam перейдёт на бету 1791249696 — только если ты на это согласен. Вернуться на обычную версию можно в конце.

1. В NotProton выключи «Block Steam client updates» (как в 12.2).
2. Steam → Настройки → Интерфейс → «Участие в бета-тестировании клиента» → бета Steam. Steam попросит перезапуск — согласись.
   Ожидаемо: Steam **не обновляется**, NotProton держит блок.
3. NotProton → **Check Now**. Ожидаемо: «Steam 1791249696 is out. Waiting for NotProton support.» (оранжевым).
   - Если NotProton пишет другое, значит Steam хранит выбор беты не в `package/beta`, как я предполагаю. Напиши мне.
4. Напиши мне «публикуй сигнатуры». Я выложу в тестовый фид список serial 2, где 1791249696 отнесён к базе 1790904859. Основание — проверка anchorcheck по пакетам этой беты (DECISIONS P5-8).
5. **Check Now**. Ожидаемо: «Steam 1791249696 is supported. Steam updates to it the next time it starts.» Блок снят.
6. Перезапусти Steam. Ожидаемо:
   - Steam обновится до 1791249696, Steam Play на месте;
   - **Check Now** в NotProton → «Steam 1791249696 is current and supported.»;
   - блок вернул сам dylib — в `notproton/notproton.log` строка `update gate: Steam's update block is back` (проверю я).
7. Возврат на обычную версию: в Steam выбери «Без бета-версии» и перезапусти. Обычная 1788652215 есть в списке, поэтому NotProton её пропустит.

### 12.7 Очистка устаревших параметров запуска (ETS2), по желанию


Сейчас у ETS2 (227300) параметры запуска `WINEMSYNC=1 CX_GRAPHICS_BACKEND=dxmt`, остались со времён CrossOver (BACKLOG 21).

1. В Steam: ETS2 → «Властивості» → «Сумісність». Ожидаемо: в списке «Graphics» выбран **DXMT**.
2. Там же → «Загальні» → «Параметри запуску». Ожидаемо: `NOTPROTON_RENDERER=dxmt`, без `WINEMSYNC=1` и `CX_GRAPHICS_BACKEND`.
3. Запусти ETS2 и выйди из неё. В `~/Library/Application Support/Steam/steamapps/compatdata/227300/notproton-run.log` ожидаемо:
   - `renderer: dxmt…`;
   - `sync: WINEMSYNC=1 from carried-over`. Раньше было `from launch-options`: теперь msync+ задаёт маркер, а не параметр запуска.

### 12.8 Что прислать

- По каждому пункту 12.1–12.5 (и 12.6, если делал): «ок» или что увидел вместо ожидаемого. Снимок окна — если текст отличается.
- После 12.5 — «PEAK ок» (или что не так): логи я посмотрю сам.
- После проверки скажи, оставить ли сборку с тестовым фидом или вернуть обычную (`make app`, фид выключен; BACKLOG 25).

## 13. Проверка Фазы 6: обновление NotProton через Sparkle (после «ключи готовы»)

Сначала — твои ключи (RELEASING §1). Дальше я публикую мост, сигнатуры и пре-релиз `v1.1.0-pre.1` и ставлю его в `/Applications` (прежнее приложение — в резервную копию). Терминал тебе не нужен.

### 13.1 Новое приложение

1. Открой NotProton → **Status** → в самом низу раздел **NotProton**.
   Ожидаемо: «NotProton 1.1.0-pre.1 (<номер сборки>)», «Updates itself from NotProton's releases on GitHub.», кнопка **Check for Updates…**, переключатель **Pre-release versions**.
2. Раздел **Steam Bridge** и строка **Steam signatures**: Ожидаемо — без ошибок подписи; мост «bridge-dormison-b1-3» (или «available», если ещё не поставлен).
3. Если macOS при первом запуске скажет, что не может проверить разработчика: **Системные настройки → Конфиденциальность и безопасность → «Всё равно открыть»** (R52). Это один раз.

### 13.2 Обновление

1. Включи **Pre-release versions**.
2. Напиши мне «жду pre.2» — я выпущу `v1.1.0-pre.2`. Через ~30 минут (сборка в CI) нажми **Check for Updates…**.
   Ожидаемо: окно Sparkle «A new version of NotProton is available! 1.1.0-pre.2 … You have 1.1.0-pre.1» с текстом изменений.
3. Нажми **Install Update** → после загрузки **Install and Relaunch**.
   - Если macOS спросит, разрешить ли NotProton изменять приложения, — разреши.
   - Ожидаемо: NotProton перезапускается, в разделе NotProton — «1.1.0-pre.2».
4. Steam при этом не закрывается. Строка «NotProton» в разделе Steam может показать «Update available» — новый патч для Steam; нажми **Update** как в 12.1 (требование §8).

### 13.3 Отказ от тестового ключа (смотреть не нужно)

Релизная сборка с тестовым ключом не собирается (шаг «Release checks» в `release.yml`), а собранная — не принимает его (`BuildKindTests`). В Status такой сборки было бы «This release build carries a TEST key…».

### 13.4 Что прислать

- Снимок раздела NotProton до и после обновления.
- Если что-то пошло не так — «логи»: я смотрю `notproton/app.log` (строки `app updates: …`) и журнал Sparkle.

## 14. Проверка Фазы 7A: настройки игры в Steam

Что нового:
- в Steam, в **Свойства игры → Совместимость**, под выбором инструмента Steam Play — блок **NotProton**: 5 быстрых настроек и кнопка **«Дополнительные настройки…»**;
- в **Настройках Steam → Совместимость**, под разделом Steam Play — **«NotProton — для всех игр»**.

Окна «Настройки игры» в NotProton.app больше нет. Твои прежние значения (PEAK, Deadlock, ETS2) переносятся сами при первом открытии страницы игры. Старые файлы сохраняются рядом: `.sevo/pre-catalog-backup/` в префиксе игры.

Терминал не нужен. Игры с VAC онлайн не запускаем.

### 14.0 Установка

Сборку с правками 8 октября я поставил в Steam сам (00:25), Steam открыт. **Update в `/Applications/NotProton.app` не нажимай** — это старая сборка, она откатит Steam.

### 14.1 Вид, язык, списки (уже пройдено 7 октября, кроме списков)

1. Свойства **PEAK → Совместимость**: внизу блока NotProton — **«Додаткові налаштування…»** и **«Скинути налаштування гри»**. Под строками серым только «Для всіх ігор: …», «Типово в NotProton: …» или «Своє», без отдельных «Скинути».
2. Открой «Додаткові налаштування…» и нажми на список **«Відеокарта для гри»**. Ожидаемо: меню открывается **поверх** диалога. Выбери NVIDIA, затем верни «Як є».
3. То же в **Настройках Steam → Совместимость → «Додаткові налаштування…»**: любой список открывается поверх.

### 14.2 PEAK: рендерер, апскейлер, HUD, клавиатура

Каждый пункт — отдельный запуск PEAK до главного меню, потом выход из игры.
1. **Рендерер → DXVK.** Ожидаемо: игра запускается, без окна «Unhandled exception». Потом верни DXMT.
2. **Апскейлер → MetalFX Spatial.** Ожидаемо: в меню игры View → Upscaler отмечен MetalFX (у тебя уже работало).
3. **«Додаткові налаштування…» → Metal HUD** — включи. Ожидаемо: игра запускается, слева сверху — панель Apple с кадрами и памятью. Если не запускается — сразу напиши мне время запуска, логи посмотрю я. Потом выключи HUD.
4. **Клавиатура** (переключателей больше нет, всегда включено): в игре ⌘ работает как Ctrl, ⌥ — как Alt. Например, в чате PEAK ⌘V вставляет текст.

### 14.3 PEAK: ограничение FPS

1. **Лічильник FPS** — вкл. Запусти PEAK, запомни число в главном меню (обычно 75–95). Выйди.
2. **Обмеження FPS → 30.** Запусти: ожидаемо 30–40 кадров (DXMT держит шагами частоты экрана: 30/40/60/120 и чуть выше). Выйди.
3. **Обмеження FPS → 60**: ожидаемо ~60–68. Потом поставь «Вимк.».

### 14.4 Меню View сохраняет выбор (бывший шаг 3, проще)

1. Включи **Лічильник FPS** и запусти PEAK — счётчик в углу.
2. В игре нажми **⌥⌘F** — счётчик пропал. Выйди из игры.
3. Открой Свойства PEAK → Совместимость. Ожидаемо: «Лічильник FPS» **выключен** и под ним «Своє». То есть выбор, сделанный в игре, NotProton запомнил.

### 14.5 Сброс

1. В «Додаткові налаштування…» PEAK включи «Графік кадрів», нажми «Готово».
2. Нажми **«Скинути налаштування гри»** под блоком. Ожидаемо: под всеми строками снова «Для всіх ігор: …» или «Типово в NotProton: …», «Своє» нигде нет.

### 14.6 Deadlock: два exe (бывший шаг 5, проще)

> **Статус 10.10: ждёт пользователя** — код и тест есть (P7A-15), ручная проверка не отмечена (`docs/PHASE7_AUDIT.md`).

Игру запускать не нужно.
1. Открой Свойства Deadlock → Совместимость.
2. Посмотри самую нижнюю серую строку блока NotProton. Ожидаемо: **«Файли гри: deadlock.exe, vconsole2.exe»** — значит, настройки Deadlock попадут в оба файла игры.
3. Больше ничего делать не нужно: файлы обоих exe проверю я.

### 14.7a Для всех игр (уже работало на ETS2)

Повторять не нужно, если не менялось: «Лічильник FPS» в Настройках Steam → ETS2 показывает «Для всіх ігор: Увімк.».

### 14.7 Что прислать

- По каждому пункту 14.1–14.6: «ок» или что не так.
- Снимки только окна Steam со свойствами и диалогом, не всего экрана. Если на снимке видны аккаунт или ники, в git я их не кладу.
- Логи я смотрю сам: `notproton/notproton-settings.log`, `notproton/notproton.log` (строка `settings: the Steam panel reached notproton-settings`), run-логи игр и файлы `.sevo` префиксов.

## 15. Проверка «Поправки 09.10», шаг 2 (что изменилось по твоим пометкам)

Терминал не нужен. Онлайн-игры с VAC не запускаем.

### 15.0 Установка

Сборку `3C98864C` я поставил в Steam сам (09.10, 18:00), Steam открыт обычным образом. **Update в `/Applications/NotProton.app` не нажимай** — там старая сборка.

При первом открытии твои настройки перенесены: копия старых — `~/Library/Application Support/notproton/settings/backup-before-schema-2/`.

### 15.1 Свойства игры → Совместимость (PEAK)

1. Ожидаемо: галочка «Примусово використовувати…» есть, **выпадающего списка «Dormison (NotProton)» нет**.
2. У заголовка NOTPROTON **нет «Dormison b1»**.
3. Быстрых строк четыре: Рендерер, Висока роздільність (Retina), Апскейлер, Лічильник FPS. «Обмеження FPS» нет.
4. Под строками **нет «Своє»**. Серая строка «Для всіх ігор: …» появляется, только если у игры значение отличается от общего.

### 15.2 «Додаткові налаштування…»

1. Разделы: **Зображення** (Вікна змінного розміру, Фінальний фільтр, DLSS MetalFX), **Миша** (Рух миші), **Продуктивність** (Очікування потоків, Єдина пам'ять, Повідомляти іграм про AVX), **Старі ігри** (Імітація зміни роздільності, 4 ГБ для 32-бітних ігор), **Діагностика** (msync+).
2. Нет: Графік кадрів, Metal HUD, Вказівник не виходить з вікна, Процесори, Відеокарта для гри, Заміни DLL, Змінні середовища.
3. Списки **того же размера, что на странице** (не крупнее), меню списка открывается поверх диалога.
4. Название — **«DLSS MetalFX»** без стрелки, под ним: «…бачать NVIDIA GeForce RTX 5060 Ti».

### 15.3 Настройки Steam → Совместимость

То же, что 15.1–15.2, в блоке «NotProton — для всіх ігор»: три быстрые строки, «Повернути типові NotProton».

### 15.4 Лічильник FPS = Metal HUD (PEAK)

1. Включи **Лічильник FPS** у PEAK и запусти игру до главного меню.
2. Ожидаемо: справа сверху панель Apple (M4 Pro, FPS, GPU, Frame Interval). У меня 09.10 так и было, 90 FPS.
3. Если игра не запустится — напиши время запуска, лог я сохраню. Потом выключи счётчик.

### 15.5 Параметры запуска Steam (теперь как в Linux)

Параметры запуска остаются в Steam (Свойства → Общие → Параметры запуска). NotProton их больше не переписывает.
1. Игра с `-dx11` в параметрах запускается как раньше.
2. Можно проверить переменную: у PEAK впиши `MTL_HUD_ENABLED=1 %command%` (счётчик в NotProton выключен), запусти. Ожидаемо: HUD Apple есть. Потом сотри строку.
3. Важно: переменная — это `ИМЯ=значение` **перед** `%command%`. Без `%command%` Steam дописывает текст после игры, и это аргумент игры (как в Linux).

Видеокарту (AMD по умолчанию, NVIDIA с DLSS MetalFX) смотреть не нужно: проверяю по файлам `.sevo` и `dxvk.conf` сам.

### 15.6 Что прислать

- По 15.1–15.5: «ок» или что не так.
- Снимки — только окна Steam или игры.

## 16. Проверка 09.10 вечер: быстрый запуск, геймпад, RE9

Терминал не нужен. Онлайн-игры с VAC не запускаем. Новая сборка (`A01322DA`) уже стоит в Steam, Steam я перезапустил в 22:04.

### 16.1 Быстрый запуск (просто заметить)

1. Запусти PEAK или RE9 как обычно.
2. Ожидаемо: игра появляется заметно быстрее — от нажатия «Играть» до картинки около 20 секунд (подготовка к запуску была ~12–15 с, стала 3–4 с).
3. Если что-то из настроек перестало действовать (Retina, Command как Control) — напиши, какая игра и что именно.

### 16.2 Геймпад Xbox

1. **Игра без Steam Input** (PEAK, как сейчас): геймпад работает как раньше.
2. **Игра со Steam Input** (Deadlock, либо любая игра: Свойства → Контроллер → «Включить Steam Input»):
   - ожидаемо: каждое нажатие срабатывает **один раз** (без двойных нажатий), игра реагирует на геймпад;
   - если игра геймпад не видит или нажатия двойные — впиши в параметры запуска этой игры `NOTPROTON_RAW_CONTROLLERS=1 %command%`, проверь ещё раз и напиши мне оба результата.
3. Управление **мышью и клавиатурой с геймпада** (раскладки Steam «как мышь») — см. вопрос в BLOCKERS: сейчас macOS этого Steam не разрешает.

### 16.3 RE9: что попробовать для скорости (по желанию)

Сейчас у меня в сцене отеля: 58 FPS, видеокарта занята 18,5 мс на кадр — упор в видеокарту, поэтому главный рычаг — разрешение, в котором игра рисует.

1. **Полный экран macOS.** Поставь в RE9 полноэкранный режим, затем зелёная кнопка окна (или меню «Вид → Полноэкранный режим»). Смотри третью строку панели Apple справа сверху: было **«Composited»** (оранжевым). Если станет **«Direct»** — кадр идёт на экран напрямую, обычно это +несколько FPS и меньше задержка. Напиши, что там и сколько FPS.
2. **Масштабирование внутри игры.** Вариант А: в Steam → Свойства RE9 → Совместимость → «Додаткові налаштування…» включи **DLSS MetalFX**, запусти RE9 (первый запуск снова «компилирует шейдеры» несколько минут — это из‑за смены видеокарты для игры), в графике RE9 выбери DLSS «Качество». Вариант Б (без NotProton): в графике RE9 FSR «Качество». Сравни FPS в той же сцене.
3. **Параметры запуска ярлыка RE9.** Там записано `ROSETTA_ADVERTISE_AVX=0 WINEMSYNC=1` без `%command%` — после правки 09.10 (как в Linux) это уходит игре как аргументы и ничего не меняет. Если хотел выключить AVX именно для RE9 — напиши `ROSETTA_ADVERTISE_AVX=0 %command%`; если нет — сотри строку.

### 16.4 Что прислать

- 16.1–16.3: «ок» или что не так, по 16.3 — числа FPS и слово «Direct»/«Composited».
- Снимки — только окна игры.
