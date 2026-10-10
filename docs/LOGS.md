# Где журналы Lullaby

В окне Lullaby кнопки «Открыть журналы» нет (Фаза 8, правка владельца). Журналы пишутся как раньше. Чтобы приложить их к сообщению о проблеме, открой в Finder: **Переход → Переход к папке…** (⇧⌘G) и вставь путь.

| Журнал | Путь | Что в нём |
|---|---|---|
| Приложение | `~/Library/Application Support/lullaby/app.log` | окно: `main:` (кнопка, план обновлений), `flow:` (шаги Install / Update / Delete и ошибки), `badge:`, установка в Steam, движок, мост, сигнатуры, гейт Steam |
| Хуки в Steam | `~/Library/Application Support/lullaby/lullaby.log` | dylib внутри Steam: Steam Play, панель настроек, гейт обновлений |
| Настройки игр | `~/Library/Application Support/lullaby/lullaby-settings.log` | панель в Steam: что изменено, GPTK |
| Меню View в игре | `~/Library/Application Support/lullaby/lullaby-sevo.log` | команды из меню View Dormison |
| Запуск игры | `~/Library/Application Support/Steam/steamapps/compatdata/<appid>/lullaby-run.log` | run-скрипт: движок, рендерер, переменные, финал сессии |
| Wine | `~/Library/Application Support/lullaby/launchers/app-<appid>/lullaby-wine.log` | вывод Wine последнего запуска игры (перезаписывается) |

`app.log` ограничен 512 КБ (старое обрезается). Delete журналы не удаляет.
