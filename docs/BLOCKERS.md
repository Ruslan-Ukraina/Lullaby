# BLOCKERS — что нужно от тебя

Обновлено: 2026-10-06, ~17:40 CEST.

## Сейчас ждём

1. **Ручную проверку Фазы 4** — `docs/SPIKE_TEST.md`, раздел 10:
   - 10.1 — блок Engine и Check for Updates;
   - 10.2 — Reinstall той же версии;
   - 10.3 — PEAK;
   - 10.4 — Roll Back;
   - 10.5 — PEAK;
   - 10.6 — отказ во время игры;
   - 10.7 — по желанию, без сети.

   Всё остальное в Фазе 4 сделано и проверено без игр (`PROGRESS.md`, ~17:35).
2. **Если после Reinstall или Roll Back PEAK не запустится:**
   - нажми **Roll Back** ещё раз — вернётся другая копия;
   - старая копия (с `.notproton-b2`) лежит в `runners/.previous-dormison-b1`, пока не пройдёт следующее обновление движка.

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
