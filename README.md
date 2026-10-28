# Lullaby

**Українська** · [English](README.en.md)

Грайте у Windows ігри зі своєї бібліотеки Steam просто на Mac - у звичному Steam для macOS, так само як Steam Play (Proton) на Linux. Ви отримуєте повноцінний досвід ігор у Steam з ухилом на нативність для Mac. Усе це завдяки рушію [Dormison](https://github.com/kageroumado/dormison) (Wine для macOS).

[![Lullaby: відео](https://img.youtube.com/vi/i7PQ9IO-7fU/maxresdefault.jpg)](https://youtu.be/i7PQ9IO-7fU)

## Встановлення

1. Потрібен Mac на Apple silicon, macOS 26 або новіша, Rosetta і Steam у `/Applications`.
2. Відкрийте Lullaby й натисніть **Встановити**. Вона акуратно закриє Steam, пропатчить його й завантажить рушій.
3. Запускайте Steam з `/Applications/Steam.app`. У віндовс-гри відкрийте "Властивості → Сумісність", увімкніть інструмент сумісності - і тисніть "Грати".


Застосунок не завірений Apple (немає нотаризації), тому першого разу відкрийте його через "Системні параметри → Приватність і безпека → Усе одно відкрити".

## Компоненти й патчі Lullaby

| Компонент | Що робить |
|---|---|
| `lby-twilight-app` | Застосунок Lullaby і консольна утиліта налаштувань: встановлення, оновлення, налаштування гри. |
| `lby-twilight-settings` | Каталог і панель налаштувань гри у Steam (Властивості - Сумісність). |
| `lby-celestia-engine` | Рушій Dormison (Wine для macOS): слот рушія, наш код його не змінює. |
| `lby-applejack-steambridge` | Міст Steam: `lsteamclient` (x86_64 і i386), через нього працюють оверлей, досягнення, друзі й хмарні збереження. |
| `lby-spike-overlay` | Оверлей Steam для ігор на Wine. |
| `lby-spitfire-apiscout` | Автовибір рендерера: за кілька секунд з'ясовує, яку графіку використовує гра. |
| `lby-pinkiepie-windowstate` | Пам'ятає розмір і повноекранний стан вікна гри; безрамкова гра на весь екран сама йде в нативний повний екран macOS. |
| `lby-trixie-fullscreen` | Нативний повний екран у рушії (ENG-12, ENG-15): грі повідомляють справжній розмір, а картинка менша за екран (наприклад 1920×1200) розтягується на весь екран без спотворень. |
| `lby-ponthree-pacer` | Direct: картинка йде напряму на дисплей (без композитора вікон) з вертикальною синхронізацією, тож ProMotion (VRR) слідує за грою. |
| `lby-rainbowdash-reflex` | NVIDIA Reflex для ігор на D3DMetal, а DLSS іде через MetalFX. |
| `lby-octavia-gcmouse` | Сира миша через GameController: без кривої курсора, трекпад лишається системним. |
| `lby-derpy-fixes` | Дрібні виправлення Wine і WineMetalGL: пам'ять, Retina, звук, що слідує за пристроєм виводу й мікрофоном. |
| `lby-rarity-icons` | Значки й назви ігор у Dock у формі macOS. |

## Подяки й ліцензії

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
| Direct3D 9 через Metal (завантажується в автора, коли знадобиться) | [mtld3d](https://github.com/athei/mtld3d) від athei | zlib |
| OpenGL через Metal (завантажується в автора, коли знадобиться) | [WineMetalGL](https://github.com/metalsharp/WineMetalGL) від MetalSharp | LGPL-3.0-or-later |
| D3DMetal (ваш) | Apple Game Porting Toolkit | ліцензія Apple, не поширюється |

Подробиці й те, які файли до якої частини належать, - у [NOTICE](NOTICE).

## Для розробників

Карта репозиторію - `docs/STRUCTURE.md`, назви компонентів - `docs/NAMING.md`, правила проєкту - `docs/PROJECT_RULES.md`. `make app` збирає застосунок, `make app-tests` запускає тести Swift, `make patchcheck` звіряє патчі з реєстром `patches/REGISTRY.md`.
