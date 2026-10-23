# Lullaby

Грайте у Windows ігри зі своєї бібліотеки Steam просто на Mac — у звичному Steam для
macOS, так само як Steam Play (Proton) на Linux.

Ігри запускаються на [Dormison](https://github.com/kageroumado/dormison) — вільному
двигун Wine для macOS, а Lullaby сама стежить, щоб усе було свіже.

## Що ви отримуєте

- **Steam Play у Steam для macOS.** У віндовської гри з'являється кнопка «Грати».
  Оверлей Steam, досягнення, друзі й хмарні збереження працюють через мак версію
  `lsteamclient` від Valve.
- **Налаштування гри просто в Steam.** У «Властивості → Сумісність» — рендерер, Retina,
  апскейлер і лічильник FPS, а також «Додаткові налаштування…».
  Мови — українська, англійська й російська.
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
| `lsteamclient` | [Proton](https://github.com/ValveSoftware/Proton) від Valve | Steamworks SDK License |
| `steam-shim` | `steam_helper` з Proton від Valve | BSD-3-Clause |
| DXMT, DXVK, MoltenVK | усередині релізу Dormison, без змін | LGPL-2.1-or-later, zlib, Apache-2.0 |
| Перехоплення функцій усередині Steam | [Dobby](https://github.com/jmpews/Dobby) від Jmpews | Apache-2.0 |
| Оновлення застосунку | [Sparkle](https://sparkle-project.org) | MIT |
| D3DMetal (ваш) | Apple Game Porting Toolkit | ліцензія Apple, не поширюється |

Подробиці й те, які файли до якої частини належать, — у [NOTICE](NOTICE).

## Для розробників

- `app/` — застосунок для macOS і консольна утиліта налаштувань (Swift); `steam/hook/` —
  бібліотека, яка завантажується в Steam; `lsteamclient/`, `steam-shim/` — міст Steam;
  `patches/engine/lby-discord-ntdllhook/` — хук завантажувача, зібраний з вихідного коду Dormison;
  `patches/engine/` — окремі файли рушія, перезібрані з виправленнями (кожен спершу
  перевірено на збіг із релізом).
- `make app` збирає застосунок, `make app-tests` запускає тести Swift; перевірки C і
  скриптів — це інші цілі в `Makefile`.
- Плани, рішення й журнал роботи — у `docs/` (російською).
