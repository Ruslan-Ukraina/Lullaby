# Где журналы NotProton

В окне NotProton кнопки «Открыть журналы» нет (Фаза 8, правка владельца). Журналы пишутся как раньше. Чтобы приложить их к сообщению о проблеме, открой в Finder: **Переход → Переход к папке…** (⇧⌘G) и вставь путь.

| Журнал | Путь | Что в нём |
|---|---|---|
| Приложение | `~/Library/Application Support/notproton/app.log` | окно: `main:` (кнопка, план обновлений), `flow:` (шаги Install / Update / Delete и ошибки), `badge:`, установка в Steam, движок, мост, сигнатуры, гейт Steam |
| Хуки в Steam | `~/Library/Application Support/notproton/notproton.log` | dylib внутри Steam: Steam Play, панель настроек, гейт обновлений |
| Настройки игр | `~/Library/Application Support/notproton/notproton-settings.log` | панель в Steam: что изменено, GPTK, Mullion |
| Меню View в игре | `~/Library/Application Support/notproton/notproton-sevo.log` | команды из меню View Dormison |
| Запуск игры | `~/Library/Application Support/Steam/steamapps/compatdata/<appid>/notproton-run.log` | run-скрипт: движок, рендерер, переменные, финал сессии |
| Wine | `~/Library/Application Support/notproton/launchers/app-<appid>/notproton-wine.log` | вывод Wine последнего запуска игры (перезаписывается) |

`app.log` ограничен 512 КБ (старое обрезается). Delete журналы не удаляет.
