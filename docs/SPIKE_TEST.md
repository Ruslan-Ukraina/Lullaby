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
