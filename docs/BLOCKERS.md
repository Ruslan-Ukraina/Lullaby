# BLOCKERS — что нужно от тебя

Обновлено: 2026-10-07, ~08:00 CEST.

## Сейчас ждём

1. **Решение: можно ли добавлять файлы в Steam Helper.app** — ради имени «Steam» в подсказке Dock и значка в Постановщике (DECISIONS W15, BACKLOG 19).
   - Что именно:
     - `Contents/Resources/en.lproj` и `uk.lproj/InfoPlist.strings` с «Steam»;
     - собственный значок бандла (Finder-style: файл `Icon\r` и атрибут каталога).
   - Info.plist и исполняемый файл не меняются, а добавленные файлы Steam при старте не проверяет.
   - Моя попытка была заблокирована системой разрешений Claude Code. Если согласен — разреши это действие (или скажи, и я сделаю это через NotProton.app, применяя при Install и убирая при Repair).
   - Не гарантировано, что Dock и Постановщик возьмут локализованное имя: это проверка.
2. **Короткая проверка** — SPIKE_TEST §11.13.

## Учти, пока играешь

- **Steam запускай из `/Applications/Steam.app`** (`open /Applications/Steam.app`). Иконка в Dock открывает `/Applications/Ігри/Steam.app` — копию **без** NotProton (R25).
- **Онлайн-матчи с VAC не запускаем** — твоё решение (BACKLOG 7).
- **Deadlock в следующий раз, скорее всего, пойдёт через Vulkan:** в `boot.vcfg` записан `-vulkan` (BACKLOG 4). Если станет хуже, верни DX11 в настройках игры.
- **Кнопка «Стоп» в Steam** теперь пишет финал лога (`=== termination signal, session ending ===`), подтверждено на PEAK.
- **Обновления Steam:** сигнатуры подходят к билду 1788652215. Запрещать ли обновления (NotProton → Block Steam client updates) — решаешь ты (R29).
- **Не нажимай в NotProton «Remove Everything»:** кнопка удаляет всю папку `notproton`, вместе с движком и резервными копиями. Откат — через «Repair Steam» (`SPIKE_TEST.md`, раздел 6).
- На Mac постоянно работает `SevofluraneDaemon` — фоновый агент Sevoflurane. Наши процессы он не трогает: останавливает только процессы своих бутылок (BACKLOG 3).

## Уведомления

2. **Пуши на телефон выключены.** `PushNotification` в 04:33 CEST снова ответил `Push not sent — mobile push is disabled in /config`, как и на контрольных точках Фазы 0 и Фазы 1 (02:44).
   Что сделать: в Claude Code открой `/config` и включи мобильные пуши (нужен подключённый Remote Control).
   Что дошло вместо пуша: `docs/BACKLOG.md` файлом в сессию и системное уведомление macOS.
