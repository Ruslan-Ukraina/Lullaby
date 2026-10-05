# BLOCKERS — что нужно от тебя

Обновлено: 2026-10-06.

## Сейчас ждём

1. **Одобрение плана Фазы 0.** Прочитай `docs/MIGRATION_PLAN.md` и `docs/RISKS.md` и ответь «ок» или пришли правки. До этого код проекта не меняю.
2. **Ответы на вопросы В1–В4** (раздел 4 в `docs/MIGRATION_PLAN.md`): база ветки (`main` или `dev`), следы прошлого эксперимента в `~/Library/Application Support/notproton/engines/dormison/` и `bridge/engine/`, где редактировать настройки игры, отключение Sparkle до Фазы 6.

3. **Уведомления на телефон выключены.** Пуш о завершении Фазы 0 не ушёл: ответ `Push not sent — mobile push is disabled in /config`. Твоя команда `/config Push when Claude decides, Push when actions required` не сработала из-за формата. Правильно так:
   ```
   /config agentPushNotifEnabled=true inputNeededNotifEnabled=true
   ```
   Для пуша на телефон ещё нужен подключённый Remote Control (`/config remoteControl=true`). Пока что отчёт отправляю файлом в сессию: он виден и с другого устройства.

## Инструменты

Проверено 2026-10-06 (версии — в `docs/PROGRESS.md`). Для Фаз 0–1 **ничего не блокирует**: Xcode 27.0, mingw-w64 14.0 (gcc 16.2), bison 3.8.2 (brew), flex 2.6.4, autoconf 2.73, cmake 4.4.4, Python 3.14 + capstone 5.0.7, gh (вход выполнен), Rosetta 2.

Понадобится позже или не понадобится вовсе:

| Что | Когда нужно | Команда для тебя |
|---|---|---|
| `pkg-config` | только если придётся собирать движок Dormison целиком: `build-macos/configure.sh` вызывает `pkg-config` для флагов GStreamer | `brew install pkgconf` |
| `llvm`, `lld` | не нужны: используются только FEX-вариантом ntdll-патча, который удаляем | — |
| `automake` | не нужен: Wine использует только autoconf | — |
