// The words a setting shows wherever it is drawn: its title, the line under it and
// what its (i) says, in English, Ukrainian and Russian.
//
// Most help texts are shortened from Sevoflurane's Core/SettingCopy.swift
// (MIT License, Copyright (c) 2026 kageroumado) and translated; they promise
// nothing the engine does not do.

import Foundation

public struct HelpEntry: Sendable, Equatable {
    public let name: L10n
    public let text: L10n

    public init(_ name: L10n, _ text: L10n) {
        self.name = name
        self.text = text
    }
}

public struct SettingHelp: Sendable, Equatable {
    public let summary: L10n
    public var entries: [HelpEntry] = []
    public var footnote: L10n?

    public init(_ summary: L10n, entries: [HelpEntry] = [], footnote: L10n? = nil) {
        self.summary = summary
        self.entries = entries
        self.footnote = footnote
    }
}

public struct SettingCopy: Sendable, Equatable {
    public let title: L10n
    public var caption: L10n?
    public let help: SettingHelp

    public init(_ title: L10n, caption: L10n? = nil, help: SettingHelp) {
        self.title = title
        self.caption = caption
        self.help = help
    }

    /// Every text this copy holds, for the completeness test.
    public var texts: [L10n] {
        [title, help.summary] + [caption, help.footnote].compactMap(\.self)
            + help.entries.flatMap { [$0.name, $0.text] }
    }
}

// MARK: - Shared words

public enum Words {
    public static let on = L10n("On", uk: "Увімк.", ru: "Вкл.")
    public static let off = L10n("Off", uk: "Вимк.", ru: "Выкл.")
    public static let custom = L10n("Custom values", uk: "Власні значення", ru: "Свои значения")
}

public enum GroupTitles {
    public static func title(_ group: SettingGroup) -> L10n {
        switch group {
        case .picture: L10n("Graphics", uk: "Графіка", ru: "Графика")
        case .performance: L10n("Performance", uk: "Продуктивність", ru: "Производительность")
        case .diagnostics: L10n("Diagnostics", uk: "Діагностика", ru: "Диагностика")
        }
    }
}

/// The panel's own words, outside any one setting. The panel in Steam draws these
/// from the catalog too, so it carries no text of its own.
public enum PanelText {
    public static let all: [String: L10n] = [
        "section": .same("Lullaby"),
        "globalSection": L10n("Lullaby — for all games", uk: "Lullaby — для всіх ігор",
                              ru: "Lullaby — для всех игр"),
        "globalCaption": L10n("A game can have its own value in its Properties.",
                              uk: "Гра може мати власне значення у своїх властивостях.",
                              ru: "У игры может быть своё значение в её свойствах."),
        "inherited": L10n("For all games: %@", uk: "Для всіх ігор: %@", ru: "Для всех игр: %@"),
        "defaultValue": L10n("Default: %@", uk: "Типово: %@",
                             ru: "По умолчанию: %@"),
        "advanced": L10n("Advanced settings…", uk: "Додаткові налаштування…", ru: "Дополнительные настройки…"),
        "advancedTitle": L10n("Advanced settings — %@", uk: "Додаткові налаштування — %@",
                              ru: "Дополнительные настройки — %@"),
        "advancedGlobalTitle": L10n("Advanced settings for all games", uk: "Додаткові налаштування для всіх ігор",
                                    ru: "Дополнительные настройки для всех игр"),
        "resetGame": L10n("Reset game settings", uk: "Скинути налаштування гри", ru: "Сбросить настройки игры"),
        "resetGlobal": L10n("Reset to defaults", uk: "Скинути до типових",
                            ru: "Сбросить по умолчанию"),
        "done": L10n("Done", uk: "Готово", ru: "Готово"),
        "nextLaunch": L10n("Changes apply the next time the game starts.",
                           uk: "Зміни діють з наступного запуску гри.",
                           ru: "Изменения применятся при следующем запуске игры."),
        "restartGame": L10n("The game is running. Changes apply after you restart it.",
                            uk: "Гра запущена. Зміни діють після її перезапуску.",
                            ru: "Игра запущена. Изменения применятся после её перезапуска."),
        "firstLaunch": L10n("The game hasn't been run through Lullaby yet. Settings apply from its first launch.",
                            uk: "Гру ще не запускали через Lullaby. Налаштування діють з першого запуску.",
                            ru: "Игру ещё не запускали через Lullaby. Настройки применятся при первом запуске."),
        "globalApplies": L10n("Changes apply the next time each game starts.",
                              uk: "Зміни діють з наступного запуску кожної гри.",
                              ru: "Изменения применятся при следующем запуске каждой игры."),
        "executables": L10n("Game files: %@", uk: "Файли гри: %@", ru: "Файлы игры: %@"),
        "unavailable": L10n("Lullaby settings are unavailable: %@", uk: "Налаштування Lullaby недоступні: %@",
                            ru: "Настройки Lullaby недоступны: %@"),
        "saveFailed": L10n("Could not save: %@", uk: "Не вдалося зберегти: %@", ru: "Не удалось сохранить: %@"),
        "experimental": L10n("experimental", uk: "експеримент", ru: "эксперимент"),
        "waitSpin": L10n("Wait spin", uk: "Очікування (spin)", ru: "Ожидание (spin)"),
        "objectSpin": L10n("Object spin", uk: "Об’єкти (spin)", ru: "Объекты (spin)"),
        "backOff": L10n("Back off", uk: "Відступати", ru: "Отступать"),
        "close": L10n("Close", uk: "Закрити", ru: "Закрыть"),
        "toolkitInSettings": L10n("Add GPTK in the Lullaby app's settings", uk: "Додай GPTK у налаштуваннях додатку Lullaby",
                                  ru: "Добавь GPTK в настройках приложения Lullaby"),
    ]
}

// MARK: - Setting copy

extension SettingCopy {
    static let renderer = SettingCopy(
        L10n("Renderer", uk: "Рендерер", ru: "Рендерер"),
        help: SettingHelp(
            L10n("In most cases leave it on \"Auto\"; if a game looks wrong or won't start, try another option.",
                 uk: "В більшості випадків залиште \"Авто\"; якщо гра виглядає неправильно або не запускається, спробуйте інший варіант.",
                 ru: "В большинстве случаев оставьте «Авто»; если игра выглядит неправильно или не запускается, попробуйте другой вариант."),
            entries: [
                HelpEntry(L10n("Auto", uk: "Авто", ru: "Авто"), L10n(
                    "In \"Auto\" Lullaby finds out which graphics API the game uses and picks the renderer itself.",
                    uk: "Lullaby в режимі \"Авто\" з'ясовує, яку графіку використовує гра і сам вибирає рендерер.",
                    ru: "В режиме «Авто» Lullaby выясняет, какую графику использует игра, и сама выбирает рендерер.")),
                HelpEntry(.same("D3DMetal (DX12)"), L10n(
                    "Direct3D 11 and 12 from the Game Porting Toolkit you add. Needed for Direct3D 12 games.",
                    uk: "Direct3D 11 і 12 з Game Porting Toolkit, який ви додаєте. Потрібен для ігор на Direct3D 12.",
                    ru: "Direct3D 11 и 12 из Game Porting Toolkit, который вы добавляете. Нужен для игр на Direct3D 12.")),
                HelpEntry(.same("DXMT (DX11)"), L10n(
                    "Direct3D 10 and 11. The fastest option for most games.",
                    uk: "Direct3D 10 і 11. Найшвидший варіант для більшості ігор.",
                    ru: "Direct3D 10 и 11. Самый быстрый вариант для большинства игр.")),
                HelpEntry(.same("mtld3d (DX9)"), L10n(
                    "Direct3D 9. A young project: a game may look wrong or not work at all. Lullaby downloads it from the author's repository the first time a game needs it.",
                    uk: "Direct3D 9. Молодий проєкт: гра може виглядати неправильно або зовсім не працювати. Lullaby завантажує його з репозиторію автора, коли він уперше знадобиться грі.",
                    ru: "Direct3D 9. Молодой проект: игра может выглядеть неправильно или вовсе не работать. Lullaby скачивает его из репозитория автора, когда он впервые понадобится игре.")),
                HelpEntry(.same("WineMetalGL (OpenGL)"), L10n(
                    "OpenGL (up to 4.6) straight through Metal, for games that draw with OpenGL. Lullaby downloads it from the author's repository the first time a game needs it.",
                    uk: "OpenGL (до 4.6) напряму через Metal, для ігор, що малюють через OpenGL. Lullaby завантажує його з репозиторію автора, коли він уперше знадобиться грі.",
                    ru: "OpenGL (до 4.6) напрямую через Metal для игр, которые рисуют через OpenGL. Lullaby скачивает его из репозитория автора, когда он впервые понадобится игре.")),
                HelpEntry(.same("MoltenVK (Vulkan)"), L10n(
                    "Vulkan. The Vulkan driver straight through Metal; in some games it performs better.",
                    uk: "Vulkan. Драйвер Vulkan напряму через Metal, в деяких іграх дає кращу продуктивність.",
                    ru: "Vulkan. Драйвер Vulkan напрямую через Metal, в некоторых играх даёт лучшую производительность.")),
            ],
            footnote: L10n("Direct3D 12 needs D3DMetal from Apple's Game Porting Toolkit. You add it yourself in the Lullaby app's settings.",
                           uk: "Для Direct3D 12 потрібен D3DMetal із Game Porting Toolkit від Apple. Ви додаєте його самі в налаштуваннях додатку Lullaby.",
                           ru: "Для Direct3D 12 нужен D3DMetal из Game Porting Toolkit от Apple. Вы добавляете его сами в настройках приложения Lullaby.")))

    static let retina = SettingCopy(
        L10n("High resolution (Retina)", uk: "Висока роздільність (Retina)", ru: "Высокое разрешение (Retina)"),
        caption: L10n("The game draws at the screen's full pixel resolution.", uk: "Гра малює в повній роздільності екрана.",
                      ru: "Игра рисует в полном разрешении экрана."),
        help: SettingHelp(
            L10n("Retina screens have four pixels for every point macOS counts in. By default a game gets the size in points, and the picture is stretched.",
                 uk: "Екран Retina має чотири пікселі на кожну точку, якими рахує macOS. Типово гра отримує розмір у точках, і картинка розтягується.",
                 ru: "У экрана Retina четыре пикселя на каждую точку, которыми считает macOS. По умолчанию игра получает размер в точках, и картинка растягивается."),
            entries: [
                HelpEntry(Words.on, L10n(
                    "Sharp picture at the screen's real resolution. Old games may show tiny text and menus.",
                    uk: "Чітка картинка в реальній роздільності екрана. У старих іграх текст і меню можуть бути дрібними.",
                    ru: "Чёткая картинка в реальном разрешении экрана. В старых играх текст и меню могут быть мелкими.")),
                HelpEntry(Words.off, L10n(
                    "Half the pixels in each direction: faster at the cost of looks, and everything stays readable.",
                    uk: "Удвічі менше пікселів по кожній осі: швидше за рахунок вигляду, усе лишається читабельним.",
                    ru: "Вдвое меньше пикселей по каждой оси: быстрее за счёт внешнего вида, всё остаётся читаемым.")),
            ],
            footnote: L10n("Saved to the game's Wine registry at launch.",
                           uk: "Зберігається в реєстрі Wine гри під час запуску.",
                           ru: "Сохраняется в реестре Wine игры при запуске.")))

    static let fps = SettingCopy(
        L10n("Frame rate counter", uk: "Лічильник FPS", ru: "Счётчик FPS"),
        caption: L10n("Apple's Metal HUD shown over the game.", uk: "Metal HUD від Apple поверх гри.",
                      ru: "Metal HUD от Apple поверх игры."),
        help: SettingHelp(
            L10n("Apple's own performance overlay: frames per second, frame time and GPU memory.",
                 uk: "Власна накладка Apple з показниками: кадри за секунду, час кадру й пам’ять GPU.",
                 ru: "Собственная панель Apple с показателями: кадры в секунду, время кадра и память GPU.")))

    static let nativeFullscreen = SettingCopy(
        L10n("Native full screen", uk: "Рідний повний екран", ru: "Нативный полный экран"),
        caption: L10n("Any \"Windowed fullscreen\" game goes to macOS native full screen by itself.",
                      uk: "Будь-яка гра Windowed fullscreen сама переходить у нативний повний екран macOS.",
                      ru: "Любая игра «Windowed fullscreen» сама переходит в нативный полный экран macOS."),
        help: SettingHelp(
            L10n("A game's borderless full-screen window (\"Windowed fullscreen\") is taken to macOS's own full screen: its own desktop, the picture under the notch, the game told its real size. Games are shown straight to the display (Direct) with VRR, so the refresh rate of a ProMotion screen follows the FPS. It usually helps the stability and performance of the game. Switched off, the window stays as the game made it and the picture goes through the compositor.",
                 uk: "Безрамкове вікно гри на весь екран \"Windowed fullscreen\" переходить у власний повний екран macOS: окремий робочий стіл, картинка під вирізом, грі повідомляють справжній розмір. Ігри показуються напряму на дисплей (Direct) з роботою VRR, тож частота оновлення екрана ProMotion слідує за ФПС. Зазвичай позитивно впливає на стабільність та продуктивність гри. Якщо вимкнути, вікно лишається таким, яким його зробила гра, а картинка йде через композитор.",
                 ru: "Безрамочное окно игры на весь экран «Windowed fullscreen» переходит в собственный полный экран macOS: отдельный рабочий стол, картинка под вырезом, игре сообщают настоящий размер. Игры показываются напрямую на дисплей (Direct) с работой VRR, поэтому частота обновления экрана ProMotion следует за FPS. Обычно это положительно влияет на стабильность и производительность игры. Если выключить, окно остаётся таким, каким его сделала игра, а картинка идёт через композитор."),
            entries: [
                HelpEntry(L10n("Games that start in a window", uk: "Ігри, що стартують у вікні", ru: "Игры, которые стартуют в окне"), L10n(
                    "A game that opens a launcher or a small window first is left alone until its full-screen window appears.",
                    uk: "Гра, що спершу відкриває лаунчер або маленьке вікно, не чіпається, доки не з’явиться вікно на весь екран.",
                    ru: "Игра, которая сначала открывает лаунчер или маленькое окно, не трогается, пока не появится окно на весь экран.")),
            ]))

    static let filter = SettingCopy(
        L10n("Scaling filter", uk: "Фільтр масштабування", ru: "Фильтр масштабирования"),
        caption: L10n("How the picture is scaled.",
                      uk: "Спосіб масштабування картинки.",
                      ru: "Способ масштабирования картинки."),
        help: SettingHelp(
            L10n("The last step between the game and the window. Off leaves it to macOS and is right for almost every game. The others run Dormison's own presenter: HDR then shows pale and the Steam overlay may not appear.",
                 uk: "Останній крок між грою та вікном. «Вимк.» залишає це macOS і підходить майже всім іграм. Решта запускають власний презентер Dormison: HDR тоді виглядає блідо, а оверлей Steam може не з’явитися.",
                 ru: "Последний шаг между игрой и окном. «Выкл.» оставляет это macOS и подходит почти всем играм. Остальные запускают собственный презентер Dormison: HDR тогда выглядит бледно, а оверлей Steam может не появиться."),
            entries: [
                HelpEntry(Words.off, L10n(
                    "macOS stretches the picture smoothly to the screen.",
                    uk: "macOS м’яко розтягує картинку під екран.",
                    ru: "macOS мягко растягивает картинку под экран.")),
                HelpEntry(.same("Bilinear"), L10n(
                    "Blends neighbouring pixels. The \"soapy\" option.", uk: "Змішує сусідні пікселі. \"Мильний\" варіант.",
                    ru: "Смешивает соседние пиксели. «Мыльный» вариант.")),
                HelpEntry(.same("Lanczos"), L10n(
                    "Sharp resampling that works well at fractional scales.", uk: "Чітке перемасштабування, добре для дробових масштабів.",
                    ru: "Чёткое масштабирование, хорошо подходит для дробных масштабов.")),
                HelpEntry(.same("MetalFX Spatial"), L10n(
                    "Apple's upscaler, for 3D games that render below the screen's resolution.",
                    uk: "Апскейлер Apple, для 3D-ігор, які рендеряться в роздільності нижчій за екранну.",
                    ru: "Апскейлер Apple, для 3D-игр, которые рендерятся в разрешении ниже экранного.")),
            ]))

    static let rawMouse = SettingCopy(
        L10n("Raw mouse (GameController)", uk: "Сира миша (GameController)", ru: "Сырая мышь (GameController)"),
        caption: L10n("The game reads the mouse as on Windows, up to 500 times a second.",
                      uk: "Гра читає мишу, як у Windows, до 500 разів на секунду.",
                      ru: "Игра читает мышь, как в Windows, до 500 раз в секунду."),
        help: SettingHelp(
            L10n("Reads the mouse through GameController and hands the game raw movement, without the pointer curve and without waiting for the screen: the engine's own path gives about 120 reports a second, this one about 500. The mouse sensitivity may become too high.",
                 uk: "Читає мишу через GameController і дає грі сирий рух, без кривої курсора й без очікування екрана: власний шлях рушія дає близько 120 звітів на секунду, цей - близько 500. Чутливість миші може стати завеликою.",
                 ru: "Читает мышь через GameController и отдаёт игре сырое движение, без кривой курсора и без ожидания экрана: собственный путь движка даёт около 120 отчётов в секунду, этот — около 500. Чувствительность мыши может стать слишком большой."),
            entries: [
                HelpEntry(L10n("Trackpad and speed", uk: "Тачпад і швидкість", ru: "Тачпад и скорость"), L10n(
                    "A trackpad is left as it is. A mouse's speed follows its own resolution (counts per inch) when it reports one.",
                    uk: "Тачпад лишається як є. Швидкість миші залежить від її роздільності (відліки на дюйм), якщо вона її повідомляє.",
                    ru: "Тачпад остаётся как есть. Скорость мыши зависит от её разрешения (отсчёты на дюйм), если она его сообщает.")),
                HelpEntry(L10n("If a game misbehaves", uk: "Якщо гра поводиться дивно", ru: "Если игра ведёт себя странно"), L10n(
                    "On for every game. If a game stutters, freezes or the mouse feels wrong, turn it off for that game: the engine's own mouse path takes over.",
                    uk: "Увімкнено для всіх ігор. Якщо гра смикається, зависає або миша поводиться дивно, вимкніть для цієї гри: працюватиме власний шлях рушія.",
                    ru: "Включено для всех игр. Если игра дёргается, зависает или мышь ведёт себя странно, выключите для этой игры: заработает собственный путь движка.")),
            ]))

    static let tuning = SettingCopy(
        L10n("Thread waiting", uk: "Очікування потоків", ru: "Ожидание потоков"),
        caption: L10n("How long a game's threads look for work before they sleep.",
                      uk: "Як довго потоки гри шукають роботу, перш ніж заснути.",
                      ru: "Как долго потоки игры ищут работу, прежде чем уснуть."),
        help: SettingHelp(
            L10n("Putting a thread to sleep and waking it costs much more on macOS than on Windows, so a thread can briefly spin and wait for its wake-up.",
                 uk: "Приспати потік і розбудити його на macOS значно дорожче, ніж у Windows, тому потік може ненадовго «покрутитися» в очікуванні.",
                 ru: "Усыпить поток и разбудить его на macOS заметно дороже, чем в Windows, поэтому поток может ненадолго «покрутиться» в ожидании."),
            entries: [
                HelpEntry(L10n("Standard", uk: "Стандарт", ru: "Стандарт"), L10n(
                    "A waiting thread goes to sleep at once, as in Wine.",
                    uk: "Потік, що чекає, одразу засинає, як у Wine.", ru: "Ждущий поток сразу засыпает, как в Wine.")),
                HelpEntry(L10n("Experimental", uk: "Експериментально", ru: "Экспериментально"), L10n(
                    "Spins for about two microseconds first (5200, 1, 5200). Hand-offs get faster; a game with more busy threads than cores pays with extra processor time.",
                    uk: "Спершу крутиться близько двох мікросекунд (5200, 1, 5200). Передача роботи між потоками швидша, але гра, у якої зайнятих потоків більше, ніж ядер, витрачає більше часу процесора.",
                    ru: "Сначала крутится около двух микросекунд (5200, 1, 5200). Передача работы между потоками быстрее, но игра, у которой занятых потоков больше, чем ядер, тратит больше времени процессора.")),
                HelpEntry(Words.custom, L10n(
                    "Wait spin and Object spin count loop iterations of about 0.4 ns each, from 0 to 1 000 000. Back off stops spinning when waits keep coming up empty.",
                    uk: "«Очікування» й «Об’єкти» — кількість ітерацій циклу по ~0,4 нс, від 0 до 1 000 000. «Відступати» зупиняє крутіння, якщо очікування раз у раз марне.",
                    ru: "«Ожидание» и «Объекты» — число итераций цикла по ~0,4 нс, от 0 до 1 000 000. «Отступать» останавливает кручение, если ожидание раз за разом оказывается напрасным.")),
            ],
            footnote: L10n("Measure with the frame rate counter. Most games show no difference.",
                           uk: "Вимірюйте лічильником FPS. У більшості ігор різниці немає.",
                           ru: "Измеряйте счётчиком FPS. В большинстве игр разницы нет.")))

    static let unifiedMemory = SettingCopy(
        L10n("Unified memory", uk: "Єдина пам’ять", ru: "Единая память"),
        caption: L10n("Tells games the GPU shares memory with the Mac.", uk: "Повідомляє іграм, що GPU ділить пам’ять із Mac.",
                      ru: "Сообщает играм, что GPU делит память с Mac."),
        help: SettingHelp(
            L10n("A Mac has one memory pool for the processor and graphics. Windows games copy every texture twice. With this on, the game is told the truth (UMA) and writes each texture once.",
                 uk: "У Mac одна пам’ять і для процесора, і для графіки. Ігри Windows копіюють кожну текстуру двічі. З цією опцією гра знає правду (UMA) і записує текстуру один раз.",
                 ru: "У Mac одна память и для процессора, и для графики. Игры Windows копируют каждую текстуру дважды. С этой опцией игра знает правду (UMA) и записывает текстуру один раз."),
            entries: [
                HelpEntry(L10n("If a game misbehaves", uk: "Якщо гра поводиться дивно", ru: "Если игра ведёт себя странно"), L10n(
                    "Wrong textures, or a game that stops at launch: turn it off for that game.",
                    uk: "Неправильні текстури або гра зупиняється під час запуску: вимкніть для цієї гри.",
                    ru: "Неправильные текстуры или игра останавливается при запуске: выключите для этой игры.")),
            ]))

    static let gameMode = SettingCopy(
        L10n("macOS Game Mode", uk: "Ігровий режим macOS", ru: "Игровой режим macOS"),
        caption: L10n("Gives a full-screen game priority for resources.",
                      uk: "Дає грі на весь екран пріоритет ресурсів.",
                      ru: "Даёт игре на весь экран приоритет ресурсов."),
        help: SettingHelp(
            L10n("macOS gives the game Game Mode: the CPU and GPU go to it first and apps in the background are held back. While you stream or record, that slows OBS, a VTuber model and the like.",
                 uk: "MacOS вмикає для гри ігровий режим: процесор і відеокарта дістаються їй першою, а програми у фоні притримуються. Під час стріму чи запису це гальмує OBS, VTuber-модель тощо.",
                 ru: "macOS включает для игры игровой режим: процессор и видеокарта достаются ей первой, а программы в фоне придерживаются. Во время стрима или записи это тормозит OBS, VTuber-модель и т. п."),
            footnote: L10n("Off — the game's bundle opts out of Game Mode.",
                           uk: "Вимкнено — пакет гри відмовляється від ігрового режиму.",
                           ru: "Выключено — пакет игры отказывается от игрового режима.")))

    static let forceVsync = SettingCopy(
        L10n("No frame tearing", uk: "Без розривів кадру", ru: "Без разрывов кадра"),
        caption: L10n("Keeps D3DMetal's picture in step with the display, even with frame generation on (usually not needed).",
                      uk: "Тримає картинку D3DMetal у такт з екраном, навіть з генерацією кадрів (зазвичай непотрібно)",
                      ru: "Держит картинку D3DMetal в такт с экраном, даже с генерацией кадров (обычно не нужно)."),
        help: SettingHelp(
            L10n("Games with frame generation turn V-Sync off, and the picture then tears. On, every frame waits for the display's refresh. D3DMetal only.",
                 uk: "Ігри з генерацією кадрів вимикають V-Sync, і картинка тоді рветься. Увімкнено — кожен кадр чекає оновлення екрана. Лише D3DMetal.",
                 ru: "Игры с генерацией кадров выключают V-Sync, и картинка тогда рвётся. Включено — каждый кадр ждёт обновления экрана. Только D3DMetal.")))
}
