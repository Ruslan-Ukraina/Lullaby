# BLOCKERS — что нужно от тебя

Обновлено: 2026-10-06, ~18:35 CEST.

## Сейчас ждём

1. **Твой просмотр прогона SPIKE_TEST §10 и твою проверку Фазы 4.** Прогон я сделал сам, 18:18–18:32 CEST (`PROGRESS.md`, таблица шагов). Снимки и журнал — `scratch/phase4-check/`. Все шаги прошли, PEAK оба раза 10 ok. Не проверено мной:
   - нажатия в окне: диалог «Close Steam to change the engine?», Retry, Open Steam. Кнопки я не нажимаю — у Терминала нет доступа к управлению, поэтому запускал тот же код без окна;
   - 10.7 — без сети.
2. **Состояние движка сейчас:**
   - `current` — исходное дерево, как до проверки;
   - `previous` → `.previous-dormison-b1` — свежая переустановка;
   - Roll Back переключает между ними.

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
