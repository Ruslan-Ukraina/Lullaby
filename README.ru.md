# Lullaby

[Українська](README.md) · **Русский** · [English](README.en.md)

Играйте в Windows-игры из своей библиотеки Steam прямо на Mac — в привычном Steam для macOS, так же как Steam Play (Proton) на Linux. Вы получаете полноценный опыт игр в Steam с упором на нативность для Mac. Всё это благодаря движку [Dormison](https://github.com/kageroumado/dormison) (Wine для macOS).

[![Lullaby: відео](https://img.youtube.com/vi/i7PQ9IO-7fU/maxresdefault.jpg)](https://youtu.be/i7PQ9IO-7fU)

## Установка

1. Нужен Mac на Apple silicon, macOS 26 или новее, Rosetta и Steam в `/Applications`.
2. Откройте Lullaby и нажмите **Установить**. Она аккуратно закроет Steam, пропатчит его и скачает движок.
3. Запускайте Steam из `/Applications/Steam.app`. У Windows-игры откройте «Свойства → Совместимость», включите инструмент совместимости — и жмите «Играть».


Приложение не заверено Apple (нет нотаризации), поэтому в первый раз откройте его через «Системные настройки → Конфиденциальность и безопасность → Всё равно открыть».

## Патчи и компоненты Lullaby

| Компонент | Что делает |
|---|---|
| `lby-pinkiepie-windowstate` | Помнит размер и полноэкранное состояние окна игры; безрамочная игра на весь экран сама уходит в нативный полный экран macOS. |
| `lby-ponthree-pacer` | Direct: картинка идёт напрямую на дисплей (без композитора окон) с вертикальной синхронизацией, поэтому ProMotion (VRR) следует за игрой. |
| `lby-rainbowdash-reflex` | NVIDIA Reflex для игр на D3DMetal, а DLSS идёт через MetalFX. |
| `lby-spitfire-apiscout` | Автовыбор рендерера: за несколько секунд выясняет, какую графику использует игра. |
| `lby-octavia-gcmouse` | Сырая мышь через GameController: без кривой курсора, трекпад остаётся системным. |
| `lby-derpy-fixes` | Мелкие исправления Wine и WineMetalGL: память, Retina, звук, который следует за устройством вывода и микрофоном. |
| `lby-rarity-icons` | Значки и названия игр в Dock в форме macOS. |
| `ENG-12, ENG-15 (winemac)` | Нативный полный экран: картинка меньше экрана (например 1920×1200) растягивается на весь экран без искажений. |

## Благодарности и лицензии

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

Подробности и то, какие файлы к какой части относятся, — в [NOTICE](NOTICE).

## Для разработчиков

Карта репозитория — `docs/STRUCTURE.md`, названия компонентов — `docs/NAMING.md`, правила проекта — `docs/PROJECT_RULES.md`. `make app` собирает приложение, `make app-tests` запускает тесты Swift, `make patchcheck` сверяет патчи с реестром `patches/REGISTRY.md`.
