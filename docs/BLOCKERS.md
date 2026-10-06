# BLOCKERS — что нужно от тебя

Обновлено: 2026-10-06, ~02:45 CEST.

## Сейчас ждём

1. **Контрольная точка Фазы 1: ручная проверка игр и решение GO / NO-GO.** Пошаговая инструкция — `docs/SPIKE_TEST.md`.
   Всё, что можно проверить без Steam, проверено (`SPIKE_TEST.md`, раздел 0). Осталось то, что видно только в живой игре: Steam Play в свойствах, ачивки, окно (размер, полный экран), оверлей Steam, выход без зависания.
   После каждой игры запусти `~/Projects/NotProton/engine/spike-check.sh` — он соберёт доказательства из логов.

Без твоего «GO» Фазу 2 не начинаю.

## Учти при проверке

- **Steam запускай из `/Applications/Steam.app`** (`open /Applications/Steam.app`). Иконка в Dock открывает `/Applications/Ігри/Steam.app` — копию **без** NotProton (R25). Dock я не трогал.
- **Обновления Steam:** сигнатуры подходят к текущему билду 1788652215. Запрещать ли обновления (NotProton → Block Steam client updates) — решаешь ты (R29).
- **Не нажимай в NotProton «Remove Everything»** во время проверки: кнопка удаляет всю папку `notproton`, вместе с движком и резервными копиями. Откат делается через «Repair Steam» (`SPIKE_TEST.md`, раздел 6).
- На Mac постоянно работает `SevofluraneDaemon` — фоновый агент установленного Sevoflurane. Его запустил не я, и NotProton его не вызывает.

## Инструменты

Не блокирует ничего. `pkg-config` (pkgconf) теперь есть: `/opt/homebrew/bin/pkg-config`.

## Уведомления

2. **Пуши на телефон выключены.** `PushNotification` в 02:44 CEST ответил: `Push not sent — mobile push is disabled in /config` (как и в Фазе 0).
   Что сделать: в Claude Code открой `/config` и включи мобильные пуши (нужен подключённый Remote Control).
   Что дошло вместо пуша:
   - `docs/SPIKE_TEST.md` отправлен файлом в сессию — виден с другого устройства;
   - системное уведомление macOS (`osascript`, код 0).
