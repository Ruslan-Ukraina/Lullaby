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
    public static let custom = L10n("Custom", uk: "Своє", ru: "Своё")
}

public enum GroupTitles {
    public static func title(_ group: SettingGroup) -> L10n {
        switch group {
        case .picture: L10n("Picture", uk: "Зображення", ru: "Картинка")
        case .mouse: L10n("Mouse", uk: "Миша", ru: "Мышь")
        case .performance: L10n("Performance", uk: "Продуктивність", ru: "Производительность")
        case .oldGames: L10n("Old games", uk: "Старі ігри", ru: "Старые игры")
        case .diagnostics: L10n("Diagnostics", uk: "Діагностика", ru: "Диагностика")
        }
    }
}

/// The panel's own words, outside any one setting. The panel in Steam draws these
/// from the catalog too, so it carries no text of its own.
public enum PanelText {
    public static let all: [String: L10n] = [
        "section": .same("NotProton"),
        "globalSection": L10n("NotProton — for all games", uk: "NotProton — для всіх ігор",
                              ru: "NotProton — для всех игр"),
        "globalCaption": L10n("A game can set its own value in its Properties.",
                              uk: "Гра може задати своє значення у своїх властивостях.",
                              ru: "Игра может задать своё значение в своих свойствах."),
        "inherited": L10n("For all games: %@", uk: "Для всіх ігор: %@", ru: "Для всех игр: %@"),
        "defaultValue": L10n("NotProton default: %@", uk: "Типово в NotProton: %@",
                             ru: "По умолчанию в NotProton: %@"),
        "advanced": L10n("Advanced settings…", uk: "Додаткові налаштування…", ru: "Дополнительные настройки…"),
        "advancedTitle": L10n("Advanced settings — %@", uk: "Додаткові налаштування — %@",
                              ru: "Дополнительные настройки — %@"),
        "advancedGlobalTitle": L10n("Advanced settings for all games", uk: "Додаткові налаштування для всіх ігор",
                                    ru: "Дополнительные настройки для всех игр"),
        "resetGame": L10n("Reset game settings", uk: "Скинути налаштування гри", ru: "Сбросить настройки игры"),
        "resetGlobal": L10n("Reset to NotProton defaults", uk: "Повернути типові NotProton",
                            ru: "Вернуть настройки NotProton по умолчанию"),
        "done": L10n("Done", uk: "Готово", ru: "Готово"),
        "nextLaunch": L10n("Changes apply the next time the game starts.",
                           uk: "Зміни діють з наступного запуску гри.",
                           ru: "Изменения применятся при следующем запуске игры."),
        "restartGame": L10n("The game is running: changes apply after you restart it.",
                            uk: "Гра запущена: зміни діють після її перезапуску.",
                            ru: "Игра запущена: изменения применятся после её перезапуска."),
        "firstLaunch": L10n("The game has not started under NotProton yet: settings apply at its first launch.",
                            uk: "Гру ще не запускали через NotProton: налаштування діють з першого запуску.",
                            ru: "Игру ещё не запускали через NotProton: настройки применятся при первом запуске."),
        "globalApplies": L10n("Changes apply the next time each game starts.",
                              uk: "Зміни діють з наступного запуску кожної гри.",
                              ru: "Изменения применятся при следующем запуске каждой игры."),
        "executables": L10n("Game files: %@", uk: "Файли гри: %@", ru: "Файлы игры: %@"),
        "unavailable": L10n("NotProton settings are unavailable: %@", uk: "Налаштування NotProton недоступні: %@",
                            ru: "Настройки NotProton недоступны: %@"),
        "saveFailed": L10n("Could not save: %@", uk: "Не вдалося зберегти: %@", ru: "Не удалось сохранить: %@"),
        "experimental": L10n("experimental", uk: "експеримент", ru: "эксперимент"),
        "waitSpin": L10n("Wait spin", uk: "Очікування (spin)", ru: "Ожидание (spin)"),
        "objectSpin": L10n("Object spin", uk: "Об’єкти (spin)", ru: "Объекты (spin)"),
        "backOff": L10n("Back off", uk: "Відступати", ru: "Отступать"),
        "close": L10n("Close", uk: "Закрити", ru: "Закрыть"),
    ]
}

// MARK: - Setting copy

extension SettingCopy {
    static let renderer = SettingCopy(
        L10n("Renderer", uk: "Рендерер", ru: "Рендерер"),
        help: SettingHelp(
            L10n("Translates the game's Direct3D for macOS. Try another one if a game looks wrong or does not start.",
                 uk: "Перекладає Direct3D гри для macOS. Спробуйте інший, якщо гра виглядає неправильно або не запускається.",
                 ru: "Переводит Direct3D игры для macOS. Попробуйте другой, если игра выглядит неправильно или не запускается."),
            entries: [
                HelpEntry(.same("DXMT"), L10n(
                    "Direct3D 10 and 11 straight on Metal. The fastest for most games.",
                    uk: "Direct3D 10 і 11 напряму через Metal. Найшвидший для більшості ігор.",
                    ru: "Direct3D 10 и 11 напрямую через Metal. Самый быстрый для большинства игр.")),
                HelpEntry(.same("DXVK"), L10n(
                    "Direct3D 10 and 11 through Vulkan and MoltenVK. For games DXMT draws wrong.",
                    uk: "Direct3D 10 і 11 через Vulkan і MoltenVK. Для ігор, які DXMT малює неправильно.",
                    ru: "Direct3D 10 и 11 через Vulkan и MoltenVK. Для игр, которые DXMT рисует неправильно.")),
                HelpEntry(.same("WineD3D"), L10n(
                    "Wine's own, through OpenGL. Direct3D 9 games always use it; Direct3D 11 only at level 9_3.",
                    uk: "Власний рендерер Wine через OpenGL. Ігри на Direct3D 9 завжди йдуть через нього; Direct3D 11 — лише рівня 9_3.",
                    ru: "Собственный рендерер Wine через OpenGL. Игры на Direct3D 9 всегда идут через него; Direct3D 11 — только уровня 9_3.")),
            ],
            footnote: L10n("Direct3D 12 needs D3DMetal from Apple's Game Porting Toolkit, which you add yourself.",
                           uk: "Для Direct3D 12 потрібен D3DMetal з Game Porting Toolkit від Apple, який ви додаєте самі.",
                           ru: "Для Direct3D 12 нужен D3DMetal из Game Porting Toolkit от Apple, который вы добавляете сами.")))

    static let retina = SettingCopy(
        L10n("High resolution (Retina)", uk: "Висока роздільність (Retina)", ru: "Высокое разрешение (Retina)"),
        caption: L10n("The game sees every pixel of the display.", uk: "Гра бачить кожен піксель дисплея.",
                      ru: "Игра видит каждый пиксель дисплея."),
        help: SettingHelp(
            L10n("A Retina display has four pixels for every point macOS lays out. By default Windows games are told the point size and the picture is scaled up.",
                 uk: "Дисплей Retina має чотири пікселі на кожну точку, якою оперує macOS. Типово ігри Windows отримують розмір у точках, і картинка збільшується.",
                 ru: "У дисплея Retina четыре пикселя на каждую точку, которой оперирует macOS. По умолчанию игры Windows получают размер в точках, и картинка увеличивается."),
            entries: [
                HelpEntry(Words.on, L10n(
                    "Sharp picture at the display's real resolution, at a lower frame rate. Older games draw tiny text and menus.",
                    uk: "Чітка картинка в реальній роздільності дисплея, але менше кадрів. Старі ігри малюють дрібний текст і меню.",
                    ru: "Чёткая картинка в реальном разрешении дисплея, но меньше кадров. Старые игры рисуют мелкий текст и меню.")),
                HelpEntry(Words.off, L10n(
                    "Half the pixels in each direction: faster, softer, everything keeps a readable size.",
                    uk: "Удвічі менше пікселів по кожній осі: швидше, м’якше, усе читабельного розміру.",
                    ru: "Вдвое меньше пикселей по каждой оси: быстрее, мягче, всё читаемого размера.")),
            ],
            footnote: L10n("Written to the game's Wine registry when it starts.",
                           uk: "Записується в реєстр Wine гри під час запуску.",
                           ru: "Записывается в реестр Wine игры при запуске.")))

    static let upscaler = SettingCopy(
        L10n("Upscaler", uk: "Апскейлер", ru: "Апскейлер"),
        caption: L10n("Enlarges a picture drawn below the window's size.", uk: "Збільшує картинку, намальовану меншою за вікно.",
                      ru: "Увеличивает картинку, нарисованную меньше окна."),
        help: SettingHelp(
            L10n("Two steps between the game's picture and the window: the upscaler, then the final filter.",
                 uk: "Два кроки між картинкою гри та вікном: апскейлер, потім фінальний фільтр.",
                 ru: "Два шага между картинкой игры и окном: апскейлер, затем финальный фильтр."),
            entries: [
                HelpEntry(Words.off, L10n(
                    "macOS stretches the picture softly; a smaller picture keeps black borders.",
                    uk: "macOS м’яко розтягує картинку; менша картинка лишається з чорними рамками.",
                    ru: "macOS мягко растягивает картинку; меньшая картинка остаётся с чёрными рамками.")),
                HelpEntry(L10n("Final filter only", uk: "Лише фінальний фільтр", ru: "Только финальный фильтр"), L10n(
                    "No shader: the final filter fits the picture to the window.",
                    uk: "Без шейдера: фінальний фільтр підганяє картинку під вікно.",
                    ru: "Без шейдера: финальный фильтр подгоняет картинку под окно.")),
                HelpEntry(.same("MetalFX Spatial"), L10n(
                    "For 3D games rendered below the display's resolution.",
                    uk: "Для 3D-ігор, що рендеряться нижче за роздільність дисплея.",
                    ru: "Для 3D-игр, которые рендерятся ниже разрешения дисплея.")),
            ],
            footnote: L10n("View › Upscaler in the game's menu bar switches it while the game runs, and NotProton keeps that choice.",
                           uk: "View › Upscaler у меню гри перемикає його під час гри, і NotProton запам’ятовує вибір.",
                           ru: "View › Upscaler в меню игры переключает его во время игры, и NotProton запоминает выбор.")))

    static let fps = SettingCopy(
        L10n("Frame rate counter", uk: "Лічильник FPS", ru: "Счётчик FPS"),
        caption: L10n("Apple's Metal HUD over the game's window.", uk: "Metal HUD від Apple поверх вікна гри.",
                      ru: "Metal HUD от Apple поверх окна игры."),
        help: SettingHelp(
            L10n("Metal's own performance overlay: frames per second, frame time and GPU memory, from the driver rather than from the game. It shows over games drawn through Metal: DXMT, DXVK and D3DMetal.",
                 uk: "Власна накладка продуктивності Metal: кадри за секунду, час кадру й пам’ять GPU — дані драйвера, а не гри. Видно в іграх, що малюють через Metal: DXMT, DXVK і D3DMetal.",
                 ru: "Собственная накладка производительности Metal: кадры в секунду, время кадра и память GPU — данные драйвера, а не игры. Видна в играх, которые рисуют через Metal: DXMT, DXVK и D3DMetal.")))

    static let windows = SettingCopy(
        L10n("Resizable windows", uk: "Вікна змінного розміру", ru: "Изменяемые окна"),
        caption: L10n("A resizable window scales the game's picture to fit.", uk: "Вікно змінного розміру масштабує картинку гри.",
                      ru: "Изменяемое окно масштабирует картинку игры."),
        help: SettingHelp(
            L10n("A game draws at the size it chose. A resizable window scales that picture, and the game keeps believing in its own size.",
                 uk: "Гра малює в обраному нею розмірі. Вікно змінного розміру масштабує цю картинку, а гра вважає, що розмір не змінився.",
                 ru: "Игра рисует в выбранном ею размере. Изменяемое окно масштабирует эту картинку, а игра считает, что размер не менялся."),
            entries: [
                HelpEntry(L10n("Never", uk: "Ніколи", ru: "Никогда"), L10n(
                    "Windows stay as the game makes them; a full-screen game covers the screen.",
                    uk: "Вікна такі, як їх робить гра; повноекранна гра закриває екран.",
                    ru: "Окна такие, как их делает игра; полноэкранная игра закрывает экран.")),
                HelpEntry(L10n("Fixed-size windows", uk: "Вікна фіксованого розміру", ru: "Окна фиксированного размера"), L10n(
                    "A window the game locks to one size gets a resize handle, and its picture scales.",
                    uk: "Вікно, яке гра фіксує в одному розмірі, можна розтягувати, і картинка масштабується.",
                    ru: "Окно, которое игра фиксирует в одном размере, можно растягивать, и картинка масштабируется.")),
                HelpEntry(L10n("Fixed-size and full-screen games", uk: "Фіксовані й повноекранні ігри",
                               ru: "Фиксированные и полноэкранные игры"), L10n(
                    "Also, a full-screen game plays in a window you can move and resize.",
                    uk: "Також повноекранна гра йде у вікні, яке можна рухати й розтягувати.",
                    ru: "Также полноэкранная игра идёт в окне, которое можно двигать и растягивать.")),
                HelpEntry(L10n("Every window with a title bar", uk: "Кожне вікно із заголовком", ru: "Каждое окно с заголовком"), L10n(
                    "Windows the game already lets you resize are scaled too, instead of being redrawn.",
                    uk: "Вікна, які гра й так дає розтягувати, теж масштабуються замість перемальовування.",
                    ru: "Окна, которые игра и так даёт растягивать, тоже масштабируются вместо перерисовки.")),
            ],
            footnote: L10n("View › Resizable Windows in the game switches it; NotProton keeps the choice.",
                           uk: "View › Resizable Windows у грі перемикає це; NotProton запам’ятовує вибір.",
                           ru: "View › Resizable Windows в игре переключает это; NotProton запоминает выбор.")))

    static let filter = SettingCopy(
        L10n("Final filter", uk: "Фінальний фільтр", ru: "Финальный фильтр"),
        help: SettingHelp(
            L10n("Fits the upscaler's picture to the window's exact size. Works while an upscaler is on.",
                 uk: "Підганяє картинку апскейлера під точний розмір вікна. Діє, коли апскейлер увімкнено.",
                 ru: "Подгоняет картинку апскейлера под точный размер окна. Действует, когда апскейлер включён."),
            entries: [
                HelpEntry(L10n("Nearest", uk: "Найближчий", ru: "Ближайший"), L10n(
                    "Copies pixels: crisp at whole-number scales, uneven at the rest.",
                    uk: "Копіює пікселі: чітко при цілих масштабах, нерівно при інших.",
                    ru: "Копирует пиксели: чётко при целых масштабах, неровно при остальных.")),
                HelpEntry(L10n("Bilinear", uk: "Білінійний", ru: "Билинейный"), L10n(
                    "Blends neighbouring pixels: the softest.", uk: "Змішує сусідні пікселі: наймʼякший.",
                    ru: "Смешивает соседние пиксели: самый мягкий.")),
                HelpEntry(.same("Lanczos"), L10n(
                    "Sharp resampling for fractional scales.", uk: "Чітке перемасштабування для дробових масштабів.",
                    ru: "Чёткое перемасштабирование для дробных масштабов.")),
            ]))

    static let emulateModeset = SettingCopy(
        L10n("Fake display-mode changes", uk: "Імітація зміни роздільності", ru: "Имитация смены разрешения"),
        caption: L10n("A game that switches the screen's resolution gets a window instead.",
                      uk: "Гра, що змінює роздільність екрана, отримує натомість вікно.",
                      ru: "Игра, которая меняет разрешение экрана, получает вместо этого окно."),
        help: SettingHelp(
            L10n("Older games ask Windows to switch the display to 800 × 600 or 1024 × 768. A Mac display has no such modes. With this on the game is told the switch happened, and its picture goes into a window.",
                 uk: "Старі ігри просять Windows перемкнути дисплей на 800 × 600 чи 1024 × 768. У дисплея Mac таких режимів немає. З цим налаштуванням гра отримує відповідь, що режим змінено, а її картинка йде у вікно.",
                 ru: "Старые игры просят Windows переключить дисплей на 800 × 600 или 1024 × 768. У дисплея Mac таких режимов нет. С этой настройкой игре отвечают, что режим сменился, а её картинка идёт в окно."),
            footnote: L10n("Written to the game's Wine registry when it starts.",
                           uk: "Записується в реєстр Wine гри під час запуску.",
                           ru: "Записывается в реестр Wine игры при запуске.")))

    static let dlss = SettingCopy(
        L10n("DLSS MetalFX", uk: "DLSS MetalFX", ru: "DLSS MetalFX"),
        caption: L10n("Games with DLSS get MetalFX behind it and see an NVIDIA GeForce RTX 5060 Ti.",
                      uk: "Ігри з DLSS отримують MetalFX замість нього й бачать NVIDIA GeForce RTX 5060 Ti.",
                      ru: "Игры с DLSS получают MetalFX вместо него и видят NVIDIA GeForce RTX 5060 Ti."),
        help: SettingHelp(
            L10n("DXMT answers the game's NVIDIA extension (NVAPI) and DLSS calls and upscales with MetalFX. DXMT only.",
                 uk: "DXMT відповідає на виклики розширень NVIDIA (NVAPI) і DLSS гри та масштабує через MetalFX. Лише з DXMT.",
                 ru: "DXMT отвечает на вызовы расширений NVIDIA (NVAPI) и DLSS игры и масштабирует через MetalFX. Только с DXMT."),
            entries: [
                HelpEntry(L10n("Graphics card", uk: "Відеокарта", ru: "Видеокарта"), L10n(
                    "NotProton picks the card a game sees: an AMD Radeon RX 9060 XT, and with this on an NVIDIA GeForce RTX 5060 Ti, since games offer DLSS only on NVIDIA.",
                    uk: "NotProton сам обирає карту, яку бачить гра: AMD Radeon RX 9060 XT, а з цим налаштуванням — NVIDIA GeForce RTX 5060 Ti, бо DLSS ігри пропонують лише на NVIDIA.",
                    ru: "NotProton сам выбирает карту, которую видит игра: AMD Radeon RX 9060 XT, а с этой настройкой — NVIDIA GeForce RTX 5060 Ti, потому что DLSS игры предлагают только на NVIDIA.")),
                HelpEntry(L10n("If a game misbehaves", uk: "Якщо гра поводиться дивно", ru: "Если игра ведёт себя странно"), L10n(
                    "Turn it off for that game. Few games are tested on this path.",
                    uk: "Вимкніть для цієї гри. На цьому шляху перевірено мало ігор.",
                    ru: "Выключите для этой игры. На этом пути проверено мало игр.")),
            ]))

    static let mouse = SettingCopy(
        L10n("Mouse movement", uk: "Рух миші", ru: "Движение мыши"),
        caption: L10n("What a game gets while it holds the pointer for mouse-look.",
                      uk: "Що отримує гра, коли тримає вказівник для огляду мишею.",
                      ru: "Что получает игра, когда держит указатель для обзора мышью."),
        help: SettingHelp(
            L10n("Applies while a game has taken the pointer, as a first-person camera does. Menus and the desktop keep the Mac's pointer.",
                 uk: "Діє, коли гра захопила вказівник, як камера від першої особи. Меню й робочий стіл зберігають вказівник Mac.",
                 ru: "Действует, когда игра захватила указатель, как камера от первого лица. Меню и рабочий стол сохраняют указатель Mac."),
            entries: [
                HelpEntry(L10n("macOS acceleration", uk: "Прискорення macOS", ru: "Ускорение macOS"), L10n(
                    "The pointer's usual curve: a fast flick travels farther than a slow sweep of the same length.",
                    uk: "Звична крива вказівника: швидкий рух переміщує далі, ніж повільний такої ж довжини.",
                    ru: "Обычная кривая указателя: быстрый рывок уводит дальше, чем медленное движение той же длины.")),
                HelpEntry(L10n("Linear (no acceleration)", uk: "Лінійний (без прискорення)", ru: "Линейное (без ускорения)"), L10n(
                    "The same sweep of the hand turns the camera the same amount at any speed. What shooters expect.",
                    uk: "Однаковий рух руки повертає камеру однаково за будь-якої швидкості. Те, чого чекають шутери.",
                    ru: "Одинаковое движение руки поворачивает камеру одинаково при любой скорости. То, чего ждут шутеры.")),
            ]))

    static let tuning = SettingCopy(
        L10n("Thread waiting", uk: "Очікування потоків", ru: "Ожидание потоков"),
        caption: L10n("How long a game's threads look for work before they sleep.",
                      uk: "Як довго потоки гри шукають роботу, перш ніж заснути.",
                      ru: "Как долго потоки игры ищут работу, прежде чем уснуть."),
        help: SettingHelp(
            L10n("Putting a thread to sleep and waking it costs far more on macOS than on Windows, so a thread can spin briefly in case its wake-up is about to arrive.",
                 uk: "Приспати потік і розбудити його на macOS значно дорожче, ніж у Windows, тож потік може коротко покрутитися, чекаючи на пробудження.",
                 ru: "Усыпить поток и разбудить его на macOS гораздо дороже, чем в Windows, поэтому поток может коротко покрутиться в ожидании пробуждения."),
            entries: [
                HelpEntry(L10n("Standard", uk: "Стандарт", ru: "Стандарт"), L10n(
                    "A waiting thread sleeps at once, as Wine does it.",
                    uk: "Потік одразу засинає, як у Wine.", ru: "Поток сразу засыпает, как в Wine.")),
                HelpEntry(L10n("Experimental", uk: "Експериментально", ru: "Экспериментально"), L10n(
                    "Spins about two microseconds first (5200, 1, 5200). Hand-offs get quicker; a game with more busy threads than cores pays in processor time.",
                    uk: "Спершу крутиться близько двох мікросекунд (5200, 1, 5200). Передача роботи швидша; гра з більшою кількістю зайнятих потоків, ніж ядер, платить часом процесора.",
                    ru: "Сначала крутится около двух микросекунд (5200, 1, 5200). Передача работы быстрее; игра с большим числом занятых потоков, чем ядер, платит временем процессора.")),
                HelpEntry(Words.custom, L10n(
                    "Wait spin and Object spin count loop iterations of about 0.4 ns, from 0 to 1 000 000. Back off stops spinning on waits that keep missing.",
                    uk: "Очікування й Об’єкти рахують ітерації циклу по ~0,4 нс, від 0 до 1 000 000. «Відступати» припиняє крутіння, якщо очікування постійно марне.",
                    ru: "Ожидание и Объекты считают итерации цикла по ~0,4 нс, от 0 до 1 000 000. «Отступать» прекращает кручение, если ожидание постоянно впустую.")),
            ],
            footnote: L10n("Measure with the frame rate counter. Most games show no difference.",
                           uk: "Вимірюйте лічильником FPS. Більшість ігор різниці не показує.",
                           ru: "Измеряйте счётчиком FPS. Большинство игр разницы не показывает.")))

    static let unifiedMemory = SettingCopy(
        L10n("Unified memory", uk: "Єдина пам’ять", ru: "Единая память"),
        caption: L10n("Tells games the GPU shares the Mac's memory.", uk: "Повідомляє іграм, що GPU ділить пам’ять Mac.",
                      ru: "Сообщает играм, что GPU делит память Mac."),
        help: SettingHelp(
            L10n("A Mac has one pool of memory for the processor and the graphics chip. Windows games expect a separate card and copy every texture twice. With this on the game is told the truth (UMA) and writes each texture once.",
                 uk: "У Mac одна пам’ять для процесора й графіки. Ігри Windows чекають окрему відеокарту й копіюють кожну текстуру двічі. З цим налаштуванням гра знає правду (UMA) і пише текстуру один раз.",
                 ru: "У Mac одна память для процессора и графики. Игры Windows ждут отдельную видеокарту и копируют каждую текстуру дважды. С этой настройкой игра знает правду (UMA) и пишет текстуру один раз."),
            entries: [
                HelpEntry(L10n("If a game misbehaves", uk: "Якщо гра поводиться дивно", ru: "Если игра ведёт себя странно"), L10n(
                    "Wrong textures or a game that stops at launch: turn it off for that game.",
                    uk: "Неправильні текстури чи гра зупиняється на запуску: вимкніть для цієї гри.",
                    ru: "Неправильные текстуры или игра останавливается при запуске: выключите для этой игры.")),
            ]))

    static let largeAddressAware = SettingCopy(
        L10n("4 GB for 32-bit games", uk: "4 ГБ для 32-бітних ігор", ru: "4 ГБ для 32-битных игр"),
        caption: L10n("A 32-bit game may use 4 GB where Windows would give it 2.",
                      uk: "32-бітна гра може використати 4 ГБ замість 2 у Windows.",
                      ru: "32-битная игра может использовать 4 ГБ вместо 2 в Windows."),
        help: SettingHelp(
            L10n("Modded and texture-heavy 32-bit games run out of 2 GB and crash. With this on every 32-bit game gets all 4.",
                 uk: "32-бітні ігри з модами й важкими текстурами вичерпують 2 ГБ і падають. З цим налаштуванням кожна 32-бітна гра отримує всі 4.",
                 ru: "32-битные игры с модами и тяжёлыми текстурами исчерпывают 2 ГБ и падают. С этой настройкой каждая 32-битная игра получает все 4."),
            entries: [
                HelpEntry(L10n("If a game misbehaves", uk: "Якщо гра поводиться дивно", ru: "Если игра ведёт себя странно"), L10n(
                    "A few old games crash above 2 GB: turn it off for that game.",
                    uk: "Кілька старих ігор падають вище 2 ГБ: вимкніть для цієї гри.",
                    ru: "Несколько старых игр падают выше 2 ГБ: выключите для этой игры.")),
            ]))

    static let avx = SettingCopy(
        L10n("Report AVX to games", uk: "Повідомляти іграм про AVX", ru: "Сообщать играм об AVX"),
        caption: L10n("Games that check for AVX at launch find it.", uk: "Ігри, що перевіряють AVX на старті, знаходять його.",
                      ru: "Игры, проверяющие AVX при запуске, находят его."),
        help: SettingHelp(
            L10n("Many games since 2020 require AVX and AVX2. Rosetta translates them either way; this makes it say so.",
                 uk: "Багато ігор після 2020 року вимагають AVX і AVX2. Rosetta перекладає їх у будь-якому разі; це налаштування змушує її про це повідомляти.",
                 ru: "Многие игры после 2020 года требуют AVX и AVX2. Rosetta переводит их в любом случае; эта настройка заставляет её об этом сообщать."),
            entries: [
                HelpEntry(L10n("If a game misbehaves", uk: "Якщо гра поводиться дивно", ru: "Если игра ведёт себя странно"), L10n(
                    "A game that picks a slower AVX path can run better with this off.",
                    uk: "Гра, що обирає повільніший шлях з AVX, може працювати краще без цього.",
                    ru: "Игра, которая выбирает более медленный путь с AVX, может работать лучше без этого.")),
            ]))

    static let msync = SettingCopy(
        .same("msync+"),
        caption: L10n("Always on. Turn it off only to test a problem in this game.",
                      uk: "Завжди увімкнено. Вимикайте лише для перевірки проблеми в цій грі.",
                      ru: "Всегда включён. Выключайте только для проверки проблемы в этой игре."),
        help: SettingHelp(
            L10n("Dormison's fast synchronisation of a game's threads through Mach semaphores. Off, the game falls back to Wine's slower server sync.",
                 uk: "Швидка синхронізація потоків гри в Dormison через семафори Mach. Без неї гра повертається до повільнішої синхронізації через сервер Wine.",
                 ru: "Быстрая синхронизация потоков игры в Dormison через семафоры Mach. Без неё игра возвращается к более медленной синхронизации через сервер Wine.")))
}
