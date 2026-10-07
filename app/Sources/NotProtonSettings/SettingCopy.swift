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
        case .performance:
            L10n("Performance and compatibility", uk: "Продуктивність і сумісність",
                 ru: "Производительность и совместимость")
        case .keyboard: L10n("Keyboard", uk: "Клавіатура", ru: "Клавиатура")
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
        "own": L10n("Set for this game", uk: "Своє для цієї гри", ru: "Своё для этой игры"),
        "ownGlobal": L10n("Changed from the NotProton default", uk: "Змінено щодо типового NotProton",
                          ru: "Изменено относительно NotProton по умолчанию"),
        "reset": L10n("Reset", uk: "Скинути", ru: "Сбросить"),
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
        "add": L10n("Add", uk: "Додати", ru: "Добавить"),
        "remove": L10n("Remove", uk: "Видалити", ru: "Удалить"),
        "customValue": L10n("Custom…", uk: "Своє…", ru: "Своё…"),
        "dllPlaceholder": L10n("library, e.g. d3dcompiler_47", uk: "бібліотека, напр. d3dcompiler_47",
                               ru: "библиотека, напр. d3dcompiler_47"),
        "envPlaceholder": L10n("VARIABLE=value or Steam launch options", uk: "ЗМІННА=значення або параметри запуску Steam",
                               ru: "ПЕРЕМЕННАЯ=значение или параметры запуска Steam"),
        "fpsPlaceholder": L10n("frames per second", uk: "кадрів за секунду", ru: "кадров в секунду"),
        "waitSpin": L10n("Wait spin", uk: "Очікування (spin)", ru: "Ожидание (spin)"),
        "objectSpin": L10n("Object spin", uk: "Об’єкти (spin)", ru: "Объекты (spin)"),
        "backOff": L10n("Back off", uk: "Відступати", ru: "Отступать"),
        "vendorID": L10n("Vendor ID (hex)", uk: "ID виробника (hex)", ru: "ID производителя (hex)"),
        "deviceID": L10n("Device ID (hex)", uk: "ID пристрою (hex)", ru: "ID устройства (hex)"),
        "gpuName": L10n("Name", uk: "Назва", ru: "Название"),
        "memory": L10n("Memory, MB", uk: "Пам’ять, МБ", ru: "Память, МБ"),
        "apply": L10n("Apply", uk: "Застосувати", ru: "Применить"),
        "invalid": L10n("This value is not accepted.", uk: "Це значення не підходить.", ru: "Это значение не подходит."),
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
        caption: L10n("One number at the top right of the game's window.", uk: "Одне число у правому верхньому куті вікна гри.",
                      ru: "Одно число в правом верхнем углу окна игры."),
        help: SettingHelp(
            L10n("Counts the frames the engine put on screen, whichever renderer drew them.",
                 uk: "Рахує кадри, які рушій вивів на екран, хоч би який рендерер їх намалював.",
                 ru: "Считает кадры, которые движок вывел на экран, каким бы рендерером они ни были нарисованы."),
            footnote: L10n("⌥⌘F in the game switches it; NotProton keeps the choice.",
                           uk: "⌥⌘F у грі перемикає його; NotProton запам’ятовує вибір.",
                           ru: "⌥⌘F в игре переключает его; NotProton запоминает выбор.")))

    static let fpsLimit = SettingCopy(
        L10n("Frame rate limit", uk: "Обмеження FPS", ru: "Ограничение FPS"),
        caption: L10n("Works with DXMT and DXVK.", uk: "Працює з DXMT і DXVK.", ru: "Работает с DXMT и DXVK."),
        help: SettingHelp(
            L10n("The renderer holds the game to this many frames per second: a cooler, quieter Mac and steadier frame times.",
                 uk: "Рендерер тримає гру на цій кількості кадрів за секунду: Mac холодніший і тихіший, кадри рівніші.",
                 ru: "Рендерер держит игру на этом числе кадров в секунду: Mac холоднее и тише, кадры ровнее."),
            entries: [
                HelpEntry(.same("DXMT"), L10n(
                    "Through its own setting d3d11.preferredMaxFrameRate.",
                    uk: "Через власне налаштування d3d11.preferredMaxFrameRate.",
                    ru: "Через собственную настройку d3d11.preferredMaxFrameRate.")),
                HelpEntry(.same("DXVK"), L10n("Through DXVK_FRAME_RATE.", uk: "Через DXVK_FRAME_RATE.", ru: "Через DXVK_FRAME_RATE.")),
                HelpEntry(.same("WineD3D"), L10n(
                    "Has no limit of its own; use the game's setting.",
                    uk: "Власного обмеження не має; скористайтеся налаштуванням гри.",
                    ru: "Собственного ограничения нет; используйте настройку игры.")),
            ]))

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

    static let fpsGraph = SettingCopy(
        L10n("Frame time graph", uk: "Графік кадрів", ru: "График кадров"),
        caption: L10n("The counter with the last seconds of frames and the 1 % low.",
                      uk: "Лічильник з останніми секундами кадрів і 1 % low.",
                      ru: "Счётчик с последними секундами кадров и 1 % low."),
        help: SettingHelp(
            L10n("Draws every recent frame at the time it took, so a hitch shows as a spike the average hides. The 1 % low is the frame rate of the slowest frame in a hundred.",
                 uk: "Малює кожен недавній кадр за часом, який він зайняв, тож ривок видно як пік, що його приховує середнє. 1 % low — частота найповільнішого кадру зі ста.",
                 ru: "Рисует каждый недавний кадр по времени, которое он занял, поэтому рывок виден как пик, скрытый средним. 1 % low — частота самого медленного кадра из ста."),
            footnote: L10n("⌥⌘G in the game switches it; NotProton keeps the choice.",
                           uk: "⌥⌘G у грі перемикає його; NotProton запам’ятовує вибір.",
                           ru: "⌥⌘G в игре переключает его; NotProton запоминает выбор.")))

    static let hud = SettingCopy(
        .same("Metal HUD"),
        caption: L10n("Apple's overlay: frame time, GPU time and memory.", uk: "Накладка Apple: час кадру, час GPU і пам’ять.",
                      ru: "Накладка Apple: время кадра, время GPU и память."),
        help: SettingHelp(
            L10n("Metal's own performance overlay, from the driver rather than from the game.",
                 uk: "Власна накладка продуктивності Metal — дані драйвера, а не гри.",
                 ru: "Собственная накладка производительности Metal — данные драйвера, а не игры.")))

    static let dlss = SettingCopy(
        L10n("DLSS → MetalFX", uk: "DLSS → MetalFX", ru: "DLSS → MetalFX"),
        caption: L10n("Games that offer DLSS get MetalFX behind it.", uk: "Ігри з DLSS отримують MetalFX замість нього.",
                      ru: "Игры с DLSS получают MetalFX вместо него."),
        help: SettingHelp(
            L10n("DXMT answers the game's NVIDIA extension (NVAPI) and DLSS calls and upscales with MetalFX. DXMT only.",
                 uk: "DXMT відповідає на виклики розширень NVIDIA (NVAPI) і DLSS гри та масштабує через MetalFX. Лише з DXMT.",
                 ru: "DXMT отвечает на вызовы расширений NVIDIA (NVAPI) и DLSS игры и масштабирует через MetalFX. Только с DXMT."),
            entries: [
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

    static let cursorConfine = SettingCopy(
        L10n("Keep the pointer in the window", uk: "Вказівник не виходить з вікна", ru: "Курсор не уходит из окна"),
        caption: L10n("During mouse-look the pointer stays off your other displays.",
                      uk: "Під час огляду мишею вказівник не переходить на інші дисплеї.",
                      ru: "Во время обзора мышью указатель не уходит на другие дисплеи."),
        help: SettingHelp(
            L10n("While the game holds the pointer, macOS keeps it inside the game's window.",
                 uk: "Поки гра тримає вказівник, macOS утримує його всередині вікна гри.",
                 ru: "Пока игра держит указатель, macOS удерживает его внутри окна игры.")))

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

    static let processors = SettingCopy(
        L10n("Processors", uk: "Процесори", ru: "Процессоры"),
        caption: L10n("Fewer processors calm older games that keep every one busy.",
                      uk: "Менше процесорів заспокоює старі ігри, що завантажують кожен.",
                      ru: "Меньше процессоров успокаивает старые игры, которые загружают каждый."),
        help: SettingHelp(
            L10n("How many processors a game is told the Mac has. Games on Unity 5 start a worker per processor, and under Rosetta every worker keeps looking for work.",
                 uk: "Скільки процесорів, на думку гри, має Mac. Ігри на Unity 5 запускають робочий потік на кожен процесор, і під Rosetta кожен постійно шукає роботу.",
                 ru: "Сколько процессоров, по мнению игры, у Mac. Игры на Unity 5 запускают рабочий поток на каждый процессор, и под Rosetta каждый постоянно ищет работу."),
            entries: [
                HelpEntry(L10n("All", uk: "Усі", ru: "Все"), L10n(
                    "The game sees every processor, as on Windows.", uk: "Гра бачить усі процесори, як у Windows.",
                    ru: "Игра видит все процессоры, как в Windows.")),
                HelpEntry(.same("8 · 6 · 4"), L10n(
                    "The game sees that many and starts that many workers.",
                    uk: "Гра бачить стільки й запускає стільки робочих потоків.",
                    ru: "Игра видит столько и запускает столько рабочих потоков.")),
            ]))

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

    static let gpu = SettingCopy(
        L10n("Graphics card for the game", uk: "Відеокарта для гри", ru: "Видеокарта для игры"),
        caption: L10n("Which card the game is told it runs on.", uk: "Яку відеокарту бачить гра.",
                      ru: "Какую видеокарту видит игра."),
        help: SettingHelp(
            L10n("Some games refuse an unknown card or pick their settings by vendor. The engine and DXMT then name the card chosen here.",
                 uk: "Деякі ігри відмовляються працювати з невідомою картою або обирають налаштування за виробником. Тоді рушій і DXMT називають обрану тут карту.",
                 ru: "Некоторые игры отказываются работать с неизвестной картой или выбирают настройки по производителю. Тогда движок и DXMT называют выбранную здесь карту."),
            entries: [
                HelpEntry(L10n("As is", uk: "Як є", ru: "Как есть"), L10n(
                    "The engine's own answer.", uk: "Власна відповідь рушія.", ru: "Собственный ответ движка.")),
                HelpEntry(.same("AMD · NVIDIA · Intel Arc A750"), L10n(
                    "A Radeon RX 7900 XT, a GeForce RTX 5080 or an Arc A750 with a current driver version.",
                    uk: "Radeon RX 7900 XT, GeForce RTX 5080 чи Arc A750 з актуальною версією драйвера.",
                    ru: "Radeon RX 7900 XT, GeForce RTX 5080 или Arc A750 с актуальной версией драйвера.")),
            ]))

    static let dllOverrides = SettingCopy(
        L10n("DLL overrides", uk: "Заміни DLL", ru: "Замены DLL"),
        caption: L10n("Which copy of a Windows library Wine loads.", uk: "Яку копію бібліотеки Windows завантажує Wine.",
                      ru: "Какую копию библиотеки Windows загружает Wine."),
        help: SettingHelp(
            L10n("Wine ships its own version of most Windows libraries and prefers it. An override changes that for one library.",
                 uk: "Wine має власні версії більшості бібліотек Windows і віддає їм перевагу. Заміна змінює це для однієї бібліотеки.",
                 ru: "У Wine есть собственные версии большинства библиотек Windows, и он предпочитает их. Замена меняет это для одной библиотеки."),
            entries: [
                HelpEntry(L10n("Native, then built-in", uk: "Рідна, потім вбудована", ru: "Родная, затем встроенная"), L10n(
                    "The copy the game brought, Wine's where there is none. What mod loaders and ReShade need.",
                    uk: "Копія, яку принесла гра, а якщо її немає — від Wine. Потрібно для завантажувачів модів і ReShade.",
                    ru: "Копия, которую принесла игра, а если её нет — от Wine. Нужно для загрузчиков модов и ReShade.")),
                HelpEntry(L10n("Built-in, then native", uk: "Вбудована, потім рідна", ru: "Встроенная, затем родная"), L10n(
                    "Wine's copy first: Wine's usual order.", uk: "Спершу копія Wine: звичний порядок Wine.",
                    ru: "Сначала копия Wine: обычный порядок Wine.")),
                HelpEntry(L10n("Disabled", uk: "Вимкнено", ru: "Отключено"), L10n(
                    "The library is not loaded at all.", uk: "Бібліотека не завантажується зовсім.",
                    ru: "Библиотека не загружается вовсе.")),
            ],
            footnote: L10n("The renderer's and Steam's own libraries follow NotProton and cannot be overridden here.",
                           uk: "Бібліотеки рендерера та Steam керуються NotProton, тут їх не замінити.",
                           ru: "Библиотеки рендерера и Steam управляются NotProton, здесь их не заменить.")))

    static let environment = SettingCopy(
        L10n("Environment variables", uk: "Змінні середовища", ru: "Переменные окружения"),
        caption: L10n("For advice that names a variable.", uk: "Для порад, що називають змінну.",
                      ru: "Для советов, которые называют переменную."),
        help: SettingHelp(
            L10n("One VARIABLE=value per line, given to every program of the game. Steam launch options such as VAR=1 %command% are accepted too.",
                 uk: "Одна ЗМІННА=значення в рядку, для кожної програми гри. Приймаються й параметри запуску Steam на кшталт VAR=1 %command%.",
                 ru: "Одна ПЕРЕМЕННАЯ=значение в строке, для каждой программы игры. Принимаются и параметры запуска Steam вроде VAR=1 %command%."),
            footnote: L10n("Variables NotProton sets itself (WINEDLLOVERRIDES, WINEPREFIX, WINEMSYNC and the ones settings above own) are refused.",
                           uk: "Змінні, які NotProton задає сам (WINEDLLOVERRIDES, WINEPREFIX, WINEMSYNC і ті, що належать налаштуванням вище), не приймаються.",
                           ru: "Переменные, которые NotProton задаёт сам (WINEDLLOVERRIDES, WINEPREFIX, WINEMSYNC и те, что принадлежат настройкам выше), не принимаются.")))

    static let commandIsControl = SettingCopy(
        L10n("Command as Control", uk: "Command як Control", ru: "Command как Control"),
        caption: L10n("⌘C, ⌘V and the like reach the game as Ctrl+C, Ctrl+V.",
                      uk: "⌘C, ⌘V тощо надходять у гру як Ctrl+C, Ctrl+V.",
                      ru: "⌘C, ⌘V и подобные приходят в игру как Ctrl+C, Ctrl+V."),
        help: SettingHelp(
            L10n("Both Command keys act as Control in the game. macOS shortcuts with Command stop working in it.",
                 uk: "Обидві клавіші Command діють у грі як Control. Скорочення macOS з Command у ній перестають працювати.",
                 ru: "Обе клавиши Command работают в игре как Control. Сочетания macOS с Command в ней перестают работать."),
            footnote: L10n("Written to the game's Wine registry when it starts.",
                           uk: "Записується в реєстр Wine гри під час запуску.",
                           ru: "Записывается в реестр Wine игры при запуске.")))

    static let optionIsAlt = SettingCopy(
        L10n("Option as Alt", uk: "Option як Alt", ru: "Option как Alt"),
        caption: L10n("Option reaches the game as Alt instead of typing special characters.",
                      uk: "Option надходить у гру як Alt замість введення спецсимволів.",
                      ru: "Option приходит в игру как Alt вместо ввода спецсимволов."),
        help: SettingHelp(
            L10n("Both Option keys act as Alt, which games bind to actions.",
                 uk: "Обидві клавіші Option діють як Alt, на який ігри призначають дії.",
                 ru: "Обе клавиши Option работают как Alt, на который игры назначают действия."),
            footnote: L10n("Written to the game's Wine registry when it starts.",
                           uk: "Записується в реєстр Wine гри під час запуску.",
                           ru: "Записывается в реестр Wine игры при запуске.")))

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
