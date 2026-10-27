# Naming of components


Формат: `lby-<персонаж>-<роль>`. Имя персонажа выбрано по смыслу роли. Это **имена компонентов в документации, реестре, каталогах и заголовках патчей**. Имена файлов, которые читает движок или Steam (`lullaby-engine.env`, `lsteamclient.dll`, `steam.exe`, `.sevo/*.env`), и идентификаторы пакета **не переименовываются**.

| Компонент (где он сейчас) | Имя | Почему этот персонаж |
|---|---|---|
| Lullaby.app + `lullaby-settings` | `lby-twilight-app` | глава всего, организатор, «библиотекарь» |
| Каталог и панель настроек игры | `lby-twilight-settings` | её каталог знаний и рецептов |
| Мост Steam: `lsteamclient` (dll x86_64/i386, so) | `lby-applejack-steambridge` | пример из задания; надёжно носит груз через границу |
| `steam.exe` (шим) | `lby-bigmack-steamexe` | молча тащит тяжёлое |
| Библиотека внутри Steam (`dylib`) | `lby-luna-steamhook` | «Lullaby» → Луна, работает в «ночи» чужого процесса |
| Оверлей Steam (`overlay-shim`) | `lby-spike-overlay` | помощник при главной героине |
| База сигнатур Steam | `lby-starswirl-signatures` | архив знаний |
| Блокировка обновлений Steam | `lby-shiningarmor-updategate` | страж |
| Движок (слот Dormison r8, не наш код) | `lby-celestia-engine` | поднимает солнце: основа, не меняется |
| Хук lsteamclient в `ntdll.dll` (B1, если остаётся) | `lby-discord-ntdllhook` | вмешивается в чужой порядок вещей |
| Reflex поверх D3DMetal | `lby-rainbowdash-reflex` | скорость отклика |
| V-Sync пейсер (S8) | `lby-ponthree-pacer` | диджей, ритм кадров |
| GCMouse | `lby-octavia-gcmouse` | точные руки |
| Состояние окна игры (S4) | `lby-pinkiepie-windowstate` | помнит всех и вся (последнее состояние) |
| Мелкие исправления чужого кода: в Wine (commit charge, HAGS, retina, вид окна для WineMetalGL, звук следует за устройством: серия патчей движка) и в WineMetalGL (32 бита цвета, чёрная первая текстура окна: внедряемая библиотека, исчезает, когда исправят у автора) | `lby-derpy-fixes` | мелкие поправки, доставка |
| Значки игр (`iconmaker`, S5) | `lby-rarity-icons` | форма и стиль |
| Тесты и стенд замеров (`perf/`) | `lby-scootaloo-perf` | скорость, измерения |
| Выпуск, подписи, ленты | `lby-zecora-release` | зелья (рецепты) и ритуалы |
| Каталог исправлений игр | `lby-fluttershy-gamefixes` | заботится о каждом «зверьке» отдельно |
| Структура и гигиена (`tools/check-structure`) | `lby-cadance-structure` | порядок, форма |
| Разведчик API игры: за 3–5 с определяет, каким API рисует игра, и выбирает бэкенд (S10) | `lby-spitfire-apiscout` | капитан Вондерболтов: быстрая разведка перед полётом |

Если для новой вещи нет подходящего героя: второстепенные (Cozy Glow, Discord, Octavia, DJ Pon-3, Derpy) использовать по смыслу, имя фиксируется здесь **до** создания каталога.
