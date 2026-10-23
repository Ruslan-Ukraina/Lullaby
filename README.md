# Lullaby

Грайте у Windows ігри зі своєї бібліотеки Steam просто на Mac — у звичному Steam для
macOS, так само як Steam Play (Proton) на Linux.

Ігри запускаються на [Dormison](https://github.com/kageroumado/dormison) — вільному
рушії Wine для macOS, а Lullaby сама стежить, щоб усе було свіже. Зараз рушій — Dormison r7;
r8 поки не підтримується: його архів містить файли Apple, які Lullaby не поширює.

## Що ви отримуєте

- **Steam Play у Steam для macOS.** У віндовської гри з'являється кнопка «Грати».
  Оверлей Steam, досягнення, друзі й хмарні збереження працюють через `lsteamclient`
  від Valve.
- **Налаштування гри просто в Steam.** У «Властивості → Сумісність» — рендерер, Retina,
  фінальний фільтр і лічильник FPS, а також «Додаткові налаштування…» з групами «Зображення»,
  «Продуктивність» і «Діагностика». Мови — українська, англійська й російська.
- **Гра у звичайному вікні macOS.** Розмір вікна змінюється, повноекранний режим рідний
  для macOS, а розмір вікна й повноекранний стан кожної гри запам'ятовуються.
  Значок і назва гри з'являються в Dock.
- **Миша.** Миша працює через GameController без прискорення; трекпад лишається системним.
  Швидкість можна підкрутити параметром запуску `LULLABY_GCMOUSE_SCALE`
  (`docs/LAUNCH_OPTIONS.md`).
- **NVIDIA Reflex і DLSS** для ігор на D3DMetal: Reflex відповідає Lullaby, DLSS іде
  через MetalFX.
- **Рендерери.** D3DMetal, DXMT (Direct3D 10/11 на Metal, він стоїть за замовчуванням),
  DXVK, WineD3D. D3DMetal потрібен для Direct3D 12 — він входить до Game Porting Toolkit
  від Apple: ви самі завантажуєте його в Apple й додаєте в Lullaby. Сама Lullaby його не
  поширює.
- **Оновлення.** Рушій (підписаний Dormison), міст Steam, сигнатури Steam і сам застосунок
  оновлюються з підписаних релізів. Якщо новий білд Steam Lullaby ще не підтримує, Steam
  на нього не оновиться, поки підтримка не з'явиться.

## Встановлення

1. Потрібен Mac на Apple silicon, macOS 26 або новіша, Rosetta і Steam у
   `/Applications`.
2. Відкрийте Lullaby й натисніть **Встановити**. Вона акуратно закриє Steam, пропатчить
   його й завантажить рушій.
3. Запускайте Steam з `/Applications/Steam.app`. У віндовсс гри відкрийте
   «Властивості → Сумісність», увімкніть інструмент сумісності — і тисніть «Грати».

Застосунок не завірений Apple (немає нотаризації), тому першого разу відкрийте його
через «Системні параметри → Приватність і безпека → Усе одно відкрити».

## Звідки що взялося

| Частина | Звідки | Ліцензія |
|---|---|---|
| Lullaby (цей репозиторій) | на основі [NotProton](https://github.com/NotProtonNot/NotProton) від NotProtonNot і співавторів | GPL-3.0 |
| Рушій | [Dormison](https://github.com/kageroumado/dormison) (Wine + wine-staging + власні напрацювання) від kageroumado | LGPL-2.1-or-later |
| Каталог налаштувань, тексти, ідентифікація відеокарти | [Sevoflurane](https://github.com/kageroumado/sevoflurane) від kageroumado | MIT |
| Два виправлення рушія (облік пам'яті, розмір екрана Retina) | [Highball](https://github.com/gauthierpiarrette/highball-engine) від gauthierpiarrette | LGPL-2.1-or-later |
| Сира миша через GameController | [WineForge](https://github.com/Alien4042x/WineForge), у ньому Wine MR !11799 від Elvin Hayatov | LGPL-2.1-or-later |
| `lsteamclient` | [Proton](https://github.com/ValveSoftware/Proton) від Valve | Steamworks SDK License |
| `steam-shim` | `steam_helper` з Proton від Valve | BSD-3-Clause |
| DXMT, DXVK, MoltenVK | усередині релізу Dormison, без змін | LGPL-2.1-or-later, zlib, Apache-2.0 |
| Назви й структури для відповіді NVIDIA Reflex | [nvapi](https://github.com/NVIDIA/nvapi) від NVIDIA | MIT |
| Перехоплення функцій усередині Steam | [Dobby](https://github.com/jmpews/Dobby) від Jmpews | Apache-2.0 |
| Оновлення застосунку | [Sparkle](https://sparkle-project.org) | MIT |
| D3DMetal (ваш) | Apple Game Porting Toolkit | ліцензія Apple, не поширюється |

Подробиці й те, які файли до якої частини належать, — у [NOTICE](NOTICE).

## Для розробників

Карта репозиторію — `docs/STRUCTURE.md`, назви компонентів — `docs/NAMING.md`, правила
проєкту — `docs/PROJECT_RULES.md`.

- `app/` — застосунок для macOS і консольна утиліта налаштувань (Swift).
- `steam/` — усе, що працює всередині Steam: `hook/` (бібліотека), `overlay/` (оверлей),
  `signatures/` (бази сигнатур).
- `bridge/` — міст Steam: `lsteamclient/` і `steam-shim/`.
- `patches/` — усе, що ми додаємо до чужого коду, з реєстром `patches/REGISTRY.md`:
  `engine/` (патчі Dormison і хук завантажувача `lby-discord-ntdllhook`; кожен
  перезібраний файл спершу перевіряється на збіг із релізом), `inject/` (без перезбирання рушія).
- `make app` збирає застосунок, `make app-tests` запускає тести Swift, `make patchcheck`
  звіряє патчі з реєстром, `tools/check-structure` — дерево з картою.
