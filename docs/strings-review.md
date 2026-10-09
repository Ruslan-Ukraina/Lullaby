# Тексты каталога настроек — на проверку

Выгрузка 09.10.2026 (шаг 4 «Поправки 09.10», `docs/ROADMAP.md` §13) из `notproton-settings catalog` сборки, которая сейчас стоит в Steam (коммит `2be870b`). Переводы и описания правит пользователь; агент их не меняет.

- **Где в коде:** тексты настроек — `app/Sources/NotProtonSettings/SettingCopy.swift` (по одному `SettingCopy` на настройку), общие слова панели (`text.*`) — там же, `PanelText.words`; варианты выбора — `SettingCatalog.swift`.
- **Ключ:** `group.<id>.title` — раздел; `setting.<id>.title` — название, `.caption` — серая строка под ним, `.help.summary` / `.help.entry[…]` / `.help.footnote` — подсказка (i), `.choice[…]` — пункт списка; `text.<ключ>` — общие слова панели (`%@` — подставляемое значение).
- **Не включены** 29 строк, одинаковых во всех языках (DXMT, MetalFX, Lanczos, названия видеокарт и т. п.).
- **«удаляется (шаг 1)»** — настройки, которые по плану шага 1 уходят из каталога; их можно не править. После шага 2 (и D3DMetal, шаг 3) таблица будет выгружена заново.
- Тексты незаконченного D3DMetal (Фаза 7B, не закоммичено) сюда не попали.

| ключ | en | uk | ru | заметка |
|---|---|---|---|---|
| `group.picture.title` | Picture | Зображення | Картинка |  |
| `group.mouse.title` | Mouse | Миша | Мышь |  |
| `group.performance.title` | Performance and compatibility | Продуктивність і сумісність | Производительность и совместимость |  |
| `group.diagnostics.title` | Diagnostics | Діагностика | Диагностика |  |
| `setting.renderer.title` | Renderer | Рендерер | Рендерер |  |
| `setting.renderer.help.summary` | Translates the game's Direct3D for macOS. Try another one if a game looks wrong or does not start. | Перекладає Direct3D гри для macOS. Спробуйте інший, якщо гра виглядає неправильно або не запускається. | Переводит Direct3D игры для macOS. Попробуйте другой, если игра выглядит неправильно или не запускается. |  |
| `setting.renderer.help.entry[DXMT]` | Direct3D 10 and 11 straight on Metal. The fastest for most games. | Direct3D 10 і 11 напряму через Metal. Найшвидший для більшості ігор. | Direct3D 10 и 11 напрямую через Metal. Самый быстрый для большинства игр. |  |
| `setting.renderer.help.entry[DXVK]` | Direct3D 10 and 11 through Vulkan and MoltenVK. For games DXMT draws wrong. | Direct3D 10 і 11 через Vulkan і MoltenVK. Для ігор, які DXMT малює неправильно. | Direct3D 10 и 11 через Vulkan и MoltenVK. Для игр, которые DXMT рисует неправильно. |  |
| `setting.renderer.help.entry[WineD3D]` | Wine's own, through OpenGL. Direct3D 9 games always use it; Direct3D 11 only at level 9_3. | Власний рендерер Wine через OpenGL. Ігри на Direct3D 9 завжди йдуть через нього; Direct3D 11 — лише рівня 9_3. | Собственный рендерер Wine через OpenGL. Игры на Direct3D 9 всегда идут через него; Direct3D 11 — только уровня 9_3. |  |
| `setting.renderer.help.footnote` | Direct3D 12 needs D3DMetal from Apple's Game Porting Toolkit, which you add yourself. | Для Direct3D 12 потрібен D3DMetal з Game Porting Toolkit від Apple, який ви додаєте самі. | Для Direct3D 12 нужен D3DMetal из Game Porting Toolkit от Apple, который вы добавляете сами. |  |
| `setting.retina.title` | High resolution (Retina) | Висока роздільність (Retina) | Высокое разрешение (Retina) |  |
| `setting.retina.caption` | The game sees every pixel of the display. | Гра бачить кожен піксель дисплея. | Игра видит каждый пиксель дисплея. |  |
| `setting.retina.help.summary` | A Retina display has four pixels for every point macOS lays out. By default Windows games are told the point size and the picture is scaled up. | Дисплей Retina має чотири пікселі на кожну точку, якою оперує macOS. Типово ігри Windows отримують розмір у точках, і картинка збільшується. | У дисплея Retina четыре пикселя на каждую точку, которой оперирует macOS. По умолчанию игры Windows получают размер в точках, и картинка увеличивается. |  |
| `setting.retina.help.entry[On].name` | On | Увімк. | Вкл. |  |
| `setting.retina.help.entry[On]` | Sharp picture at the display's real resolution, at a lower frame rate. Older games draw tiny text and menus. | Чітка картинка в реальній роздільності дисплея, але менше кадрів. Старі ігри малюють дрібний текст і меню. | Чёткая картинка в реальном разрешении дисплея, но меньше кадров. Старые игры рисуют мелкий текст и меню. |  |
| `setting.retina.help.entry[Off].name` | Off | Вимк. | Выкл. |  |
| `setting.retina.help.entry[Off]` | Half the pixels in each direction: faster, softer, everything keeps a readable size. | Удвічі менше пікселів по кожній осі: швидше, м’якше, усе читабельного розміру. | Вдвое меньше пикселей по каждой оси: быстрее, мягче, всё читаемого размера. |  |
| `setting.retina.help.footnote` | Written to the game's Wine registry when it starts. | Записується в реєстр Wine гри під час запуску. | Записывается в реестр Wine игры при запуске. |  |
| `setting.upscaler.title` | Upscaler | Апскейлер | Апскейлер |  |
| `setting.upscaler.caption` | Enlarges a picture drawn below the window's size. | Збільшує картинку, намальовану меншою за вікно. | Увеличивает картинку, нарисованную меньше окна. |  |
| `setting.upscaler.help.summary` | Two steps between the game's picture and the window: the upscaler, then the final filter. | Два кроки між картинкою гри та вікном: апскейлер, потім фінальний фільтр. | Два шага между картинкой игры и окном: апскейлер, затем финальный фильтр. |  |
| `setting.upscaler.help.entry[Off].name` | Off | Вимк. | Выкл. |  |
| `setting.upscaler.help.entry[Off]` | macOS stretches the picture softly; a smaller picture keeps black borders. | macOS м’яко розтягує картинку; менша картинка лишається з чорними рамками. | macOS мягко растягивает картинку; меньшая картинка остаётся с чёрными рамками. |  |
| `setting.upscaler.help.entry[Final filter only].name` | Final filter only | Лише фінальний фільтр | Только финальный фильтр |  |
| `setting.upscaler.help.entry[Final filter only]` | No shader: the final filter fits the picture to the window. | Без шейдера: фінальний фільтр підганяє картинку під вікно. | Без шейдера: финальный фильтр подгоняет картинку под окно. |  |
| `setting.upscaler.help.entry[MetalFX Spatial]` | For 3D games rendered below the display's resolution. | Для 3D-ігор, що рендеряться нижче за роздільність дисплея. | Для 3D-игр, которые рендерятся ниже разрешения дисплея. |  |
| `setting.upscaler.help.footnote` | View › Upscaler in the game's menu bar switches it while the game runs, and NotProton keeps that choice. | View › Upscaler у меню гри перемикає його під час гри, і NotProton запам’ятовує вибір. | View › Upscaler в меню игры переключает его во время игры, и NotProton запоминает выбор. |  |
| `setting.upscaler.choice[off]` | Off | Вимк. | Выкл. |  |
| `setting.upscaler.choice[lanczos]` | Final filter only | Лише фінальний фільтр | Только финальный фильтр |  |
| `setting.fps.title` | Frame rate counter | Лічильник FPS | Счётчик FPS |  |
| `setting.fps.caption` | One number at the top right of the game's window. | Одне число у правому верхньому куті вікна гри. | Одно число в правом верхнем углу окна игры. |  |
| `setting.fps.help.summary` | Counts the frames the engine put on screen, whichever renderer drew them. | Рахує кадри, які рушій вивів на екран, хоч би який рендерер їх намалював. | Считает кадры, которые движок вывел на экран, каким бы рендерером они ни были нарисованы. |  |
| `setting.fps.help.footnote` | ⌥⌘F in the game switches it; NotProton keeps the choice. | ⌥⌘F у грі перемикає його; NotProton запам’ятовує вибір. | ⌥⌘F в игре переключает его; NotProton запоминает выбор. |  |
| `setting.fpsLimit.title` | Frame rate limit | Обмеження FPS | Ограничение FPS | удаляется (шаг 1) |
| `setting.fpsLimit.caption` | DXMT: in steps of the display's rate. DXVK: exact. | DXMT: кроками частоти екрана. DXVK: точно. | DXMT: шагами частоты экрана. DXVK: точно. | удаляется (шаг 1) |
| `setting.fpsLimit.help.summary` | The renderer holds the game to about this many frames per second: a cooler, quieter Mac and steadier frame times. | Рендерер тримає гру приблизно на цій кількості кадрів за секунду: Mac холодніший і тихіший, кадри рівніші. | Рендерер держит игру примерно на этом числе кадров в секунду: Mac холоднее и тише, кадры ровнее. | удаляется (шаг 1) |
| `setting.fpsLimit.help.entry[DXMT]` | Paces frames to the display: on a 120 Hz screen 120, 60, 40 or 30, a few frames above the limit. A value in between takes the step above it. | Підлаштовує кадри під екран: на екрані 120 Гц — 120, 60, 40 або 30, на кілька кадрів більше за обмеження. Проміжне значення бере крок вище. | Подстраивает кадры под экран: на экране 120 Гц — 120, 60, 40 или 30, на несколько кадров больше ограничения. Промежуточное значение берёт шаг выше. | удаляется (шаг 1) |
| `setting.fpsLimit.help.entry[DXVK]` | Holds the exact number. | Тримає точне число. | Держит точное число. | удаляется (шаг 1) |
| `setting.fpsLimit.help.entry[WineD3D]` | Has no limit of its own; use the game's setting. | Власного обмеження не має; скористайтеся налаштуванням гри. | Собственного ограничения нет; используйте настройку игры. | удаляется (шаг 1) |
| `setting.fpsLimit.choice[0]` | Off | Вимк. | Выкл. | удаляется (шаг 1) |
| `setting.windows.title` | Resizable windows | Вікна змінного розміру | Изменяемые окна |  |
| `setting.windows.caption` | A resizable window scales the game's picture to fit. | Вікно змінного розміру масштабує картинку гри. | Изменяемое окно масштабирует картинку игры. |  |
| `setting.windows.help.summary` | A game draws at the size it chose. A resizable window scales that picture, and the game keeps believing in its own size. | Гра малює в обраному нею розмірі. Вікно змінного розміру масштабує цю картинку, а гра вважає, що розмір не змінився. | Игра рисует в выбранном ею размере. Изменяемое окно масштабирует эту картинку, а игра считает, что размер не менялся. |  |
| `setting.windows.help.entry[Never].name` | Never | Ніколи | Никогда |  |
| `setting.windows.help.entry[Never]` | Windows stay as the game makes them; a full-screen game covers the screen. | Вікна такі, як їх робить гра; повноекранна гра закриває екран. | Окна такие, как их делает игра; полноэкранная игра закрывает экран. |  |
| `setting.windows.help.entry[Fixed-size windows].name` | Fixed-size windows | Вікна фіксованого розміру | Окна фиксированного размера |  |
| `setting.windows.help.entry[Fixed-size windows]` | A window the game locks to one size gets a resize handle, and its picture scales. | Вікно, яке гра фіксує в одному розмірі, можна розтягувати, і картинка масштабується. | Окно, которое игра фиксирует в одном размере, можно растягивать, и картинка масштабируется. |  |
| `setting.windows.help.entry[Fixed-size and full-screen games].name` | Fixed-size and full-screen games | Фіксовані й повноекранні ігри | Фиксированные и полноэкранные игры |  |
| `setting.windows.help.entry[Fixed-size and full-screen games]` | Also, a full-screen game plays in a window you can move and resize. | Також повноекранна гра йде у вікні, яке можна рухати й розтягувати. | Также полноэкранная игра идёт в окне, которое можно двигать и растягивать. |  |
| `setting.windows.help.entry[Every window with a title bar].name` | Every window with a title bar | Кожне вікно із заголовком | Каждое окно с заголовком |  |
| `setting.windows.help.entry[Every window with a title bar]` | Windows the game already lets you resize are scaled too, instead of being redrawn. | Вікна, які гра й так дає розтягувати, теж масштабуються замість перемальовування. | Окна, которые игра и так даёт растягивать, тоже масштабируются вместо перерисовки. |  |
| `setting.windows.help.footnote` | View › Resizable Windows in the game switches it; NotProton keeps the choice. | View › Resizable Windows у грі перемикає це; NotProton запам’ятовує вибір. | View › Resizable Windows в игре переключает это; NotProton запоминает выбор. |  |
| `setting.windows.choice[off]` | Never | Ніколи | Никогда |  |
| `setting.windows.choice[fixed]` | Fixed-size windows | Вікна фіксованого розміру | Окна фиксированного размера |  |
| `setting.windows.choice[window]` | Fixed-size and full-screen games | Фіксовані й повноекранні ігри | Фиксированные и полноэкранные игры |  |
| `setting.windows.choice[all]` | Every window with a title bar | Кожне вікно із заголовком | Каждое окно с заголовком |  |
| `setting.filter.title` | Final filter | Фінальний фільтр | Финальный фильтр |  |
| `setting.filter.help.summary` | Fits the upscaler's picture to the window's exact size. Works while an upscaler is on. | Підганяє картинку апскейлера під точний розмір вікна. Діє, коли апскейлер увімкнено. | Подгоняет картинку апскейлера под точный размер окна. Действует, когда апскейлер включён. |  |
| `setting.filter.help.entry[Nearest].name` | Nearest | Найближчий | Ближайший |  |
| `setting.filter.help.entry[Nearest]` | Copies pixels: crisp at whole-number scales, uneven at the rest. | Копіює пікселі: чітко при цілих масштабах, нерівно при інших. | Копирует пиксели: чётко при целых масштабах, неровно при остальных. |  |
| `setting.filter.help.entry[Bilinear].name` | Bilinear | Білінійний | Билинейный |  |
| `setting.filter.help.entry[Bilinear]` | Blends neighbouring pixels: the softest. | Змішує сусідні пікселі: наймʼякший. | Смешивает соседние пиксели: самый мягкий. |  |
| `setting.filter.help.entry[Lanczos]` | Sharp resampling for fractional scales. | Чітке перемасштабування для дробових масштабів. | Чёткое перемасштабирование для дробных масштабов. |  |
| `setting.filter.choice[nearest]` | Nearest | Найближчий | Ближайший |  |
| `setting.filter.choice[bilinear]` | Bilinear | Білінійний | Билинейный |  |
| `setting.emulateModeset.title` | Fake display-mode changes | Імітація зміни роздільності | Имитация смены разрешения |  |
| `setting.emulateModeset.caption` | A game that switches the screen's resolution gets a window instead. | Гра, що змінює роздільність екрана, отримує натомість вікно. | Игра, которая меняет разрешение экрана, получает вместо этого окно. |  |
| `setting.emulateModeset.help.summary` | Older games ask Windows to switch the display to 800 × 600 or 1024 × 768. A Mac display has no such modes. With this on the game is told the switch happened, and its picture goes into a window. | Старі ігри просять Windows перемкнути дисплей на 800 × 600 чи 1024 × 768. У дисплея Mac таких режимів немає. З цим налаштуванням гра отримує відповідь, що режим змінено, а її картинка йде у вікно. | Старые игры просят Windows переключить дисплей на 800 × 600 или 1024 × 768. У дисплея Mac таких режимов нет. С этой настройкой игре отвечают, что режим сменился, а её картинка идёт в окно. |  |
| `setting.emulateModeset.help.footnote` | Written to the game's Wine registry when it starts. | Записується в реєстр Wine гри під час запуску. | Записывается в реестр Wine игры при запуске. |  |
| `setting.fpsGraph.title` | Frame time graph | Графік кадрів | График кадров | удаляется (шаг 1) |
| `setting.fpsGraph.caption` | The counter with the last seconds of frames and the 1 % low. | Лічильник з останніми секундами кадрів і 1 % low. | Счётчик с последними секундами кадров и 1 % low. | удаляется (шаг 1) |
| `setting.fpsGraph.help.summary` | Draws every recent frame at the time it took, so a hitch shows as a spike the average hides. The 1 % low is the frame rate of the slowest frame in a hundred. | Малює кожен недавній кадр за часом, який він зайняв, тож ривок видно як пік, що його приховує середнє. 1 % low — частота найповільнішого кадру зі ста. | Рисует каждый недавний кадр по времени, которое он занял, поэтому рывок виден как пик, скрытый средним. 1 % low — частота самого медленного кадра из ста. | удаляется (шаг 1) |
| `setting.fpsGraph.help.footnote` | ⌥⌘G in the game switches it; NotProton keeps the choice. | ⌥⌘G у грі перемикає його; NotProton запам’ятовує вибір. | ⌥⌘G в игре переключает его; NotProton запоминает выбор. | удаляется (шаг 1) |
| `setting.hud.caption` | Apple's overlay: frame time, GPU time and memory. | Накладка Apple: час кадру, час GPU і пам’ять. | Накладка Apple: время кадра, время GPU и память. | удаляется (шаг 1) |
| `setting.hud.help.summary` | Metal's own performance overlay, from the driver rather than from the game. | Власна накладка продуктивності Metal — дані драйвера, а не гри. | Собственная накладка производительности Metal — данные драйвера, а не игры. | удаляется (шаг 1) |
| `setting.dlss.caption` | Games that offer DLSS get MetalFX behind it. | Ігри з DLSS отримують MetalFX замість нього. | Игры с DLSS получают MetalFX вместо него. |  |
| `setting.dlss.help.summary` | DXMT answers the game's NVIDIA extension (NVAPI) and DLSS calls and upscales with MetalFX. DXMT only. | DXMT відповідає на виклики розширень NVIDIA (NVAPI) і DLSS гри та масштабує через MetalFX. Лише з DXMT. | DXMT отвечает на вызовы расширений NVIDIA (NVAPI) и DLSS игры и масштабирует через MetalFX. Только с DXMT. |  |
| `setting.dlss.help.entry[If a game misbehaves].name` | If a game misbehaves | Якщо гра поводиться дивно | Если игра ведёт себя странно |  |
| `setting.dlss.help.entry[If a game misbehaves]` | Turn it off for that game. Few games are tested on this path. | Вимкніть для цієї гри. На цьому шляху перевірено мало ігор. | Выключите для этой игры. На этом пути проверено мало игр. |  |
| `setting.mouse.title` | Mouse movement | Рух миші | Движение мыши |  |
| `setting.mouse.caption` | What a game gets while it holds the pointer for mouse-look. | Що отримує гра, коли тримає вказівник для огляду мишею. | Что получает игра, когда держит указатель для обзора мышью. |  |
| `setting.mouse.help.summary` | Applies while a game has taken the pointer, as a first-person camera does. Menus and the desktop keep the Mac's pointer. | Діє, коли гра захопила вказівник, як камера від першої особи. Меню й робочий стіл зберігають вказівник Mac. | Действует, когда игра захватила указатель, как камера от первого лица. Меню и рабочий стол сохраняют указатель Mac. |  |
| `setting.mouse.help.entry[macOS acceleration].name` | macOS acceleration | Прискорення macOS | Ускорение macOS |  |
| `setting.mouse.help.entry[macOS acceleration]` | The pointer's usual curve: a fast flick travels farther than a slow sweep of the same length. | Звична крива вказівника: швидкий рух переміщує далі, ніж повільний такої ж довжини. | Обычная кривая указателя: быстрый рывок уводит дальше, чем медленное движение той же длины. |  |
| `setting.mouse.help.entry[Linear (no acceleration)].name` | Linear (no acceleration) | Лінійний (без прискорення) | Линейное (без ускорения) |  |
| `setting.mouse.help.entry[Linear (no acceleration)]` | The same sweep of the hand turns the camera the same amount at any speed. What shooters expect. | Однаковий рух руки повертає камеру однаково за будь-якої швидкості. Те, чого чекають шутери. | Одинаковое движение руки поворачивает камеру одинаково при любой скорости. То, чего ждут шутеры. |  |
| `setting.mouse.choice[system]` | macOS acceleration | Прискорення macOS | Ускорение macOS |  |
| `setting.mouse.choice[linear]` | Linear (no acceleration) | Лінійний (без прискорення) | Линейное (без ускорения) |  |
| `setting.cursorConfine.title` | Keep the pointer in the window | Вказівник не виходить з вікна | Курсор не уходит из окна | удаляется (шаг 1) |
| `setting.cursorConfine.caption` | During mouse-look the pointer stays off your other displays. | Під час огляду мишею вказівник не переходить на інші дисплеї. | Во время обзора мышью указатель не уходит на другие дисплеи. | удаляется (шаг 1) |
| `setting.cursorConfine.help.summary` | While the game holds the pointer, macOS keeps it inside the game's window. | Поки гра тримає вказівник, macOS утримує його всередині вікна гри. | Пока игра держит указатель, macOS удерживает его внутри окна игры. | удаляется (шаг 1) |
| `setting.tuning.title` | Thread waiting | Очікування потоків | Ожидание потоков |  |
| `setting.tuning.caption` | How long a game's threads look for work before they sleep. | Як довго потоки гри шукають роботу, перш ніж заснути. | Как долго потоки игры ищут работу, прежде чем уснуть. |  |
| `setting.tuning.help.summary` | Putting a thread to sleep and waking it costs far more on macOS than on Windows, so a thread can spin briefly in case its wake-up is about to arrive. | Приспати потік і розбудити його на macOS значно дорожче, ніж у Windows, тож потік може коротко покрутитися, чекаючи на пробудження. | Усыпить поток и разбудить его на macOS гораздо дороже, чем в Windows, поэтому поток может коротко покрутиться в ожидании пробуждения. |  |
| `setting.tuning.help.entry[Standard].name` | Standard | Стандарт | Стандарт |  |
| `setting.tuning.help.entry[Standard]` | A waiting thread sleeps at once, as Wine does it. | Потік одразу засинає, як у Wine. | Поток сразу засыпает, как в Wine. |  |
| `setting.tuning.help.entry[Experimental].name` | Experimental | Експериментально | Экспериментально |  |
| `setting.tuning.help.entry[Experimental]` | Spins about two microseconds first (5200, 1, 5200). Hand-offs get quicker; a game with more busy threads than cores pays in processor time. | Спершу крутиться близько двох мікросекунд (5200, 1, 5200). Передача роботи швидша; гра з більшою кількістю зайнятих потоків, ніж ядер, платить часом процесора. | Сначала крутится около двух микросекунд (5200, 1, 5200). Передача работы быстрее; игра с большим числом занятых потоков, чем ядер, платит временем процессора. |  |
| `setting.tuning.help.entry[Custom].name` | Custom | Своє | Своё |  |
| `setting.tuning.help.entry[Custom]` | Wait spin and Object spin count loop iterations of about 0.4 ns, from 0 to 1 000 000. Back off stops spinning on waits that keep missing. | Очікування й Об’єкти рахують ітерації циклу по ~0,4 нс, від 0 до 1 000 000. «Відступати» припиняє крутіння, якщо очікування постійно марне. | Ожидание и Объекты считают итерации цикла по ~0,4 нс, от 0 до 1 000 000. «Отступать» прекращает кручение, если ожидание постоянно впустую. |  |
| `setting.tuning.help.footnote` | Measure with the frame rate counter. Most games show no difference. | Вимірюйте лічильником FPS. Більшість ігор різниці не показує. | Измеряйте счётчиком FPS. Большинство игр разницы не показывает. |  |
| `setting.tuning.choice[standard]` | Standard | Стандарт | Стандарт |  |
| `setting.tuning.choice[experimental]` | Experimental | Експериментально | Экспериментально |  |
| `setting.tuning.choice[custom]` | Custom | Своє | Своё |  |
| `setting.processors.title` | Processors | Процесори | Процессоры | удаляется (шаг 1) |
| `setting.processors.caption` | Fewer processors calm older games that keep every one busy. | Менше процесорів заспокоює старі ігри, що завантажують кожен. | Меньше процессоров успокаивает старые игры, которые загружают каждый. | удаляется (шаг 1) |
| `setting.processors.help.summary` | How many processors a game is told the Mac has. Games on Unity 5 start a worker per processor, and under Rosetta every worker keeps looking for work. | Скільки процесорів, на думку гри, має Mac. Ігри на Unity 5 запускають робочий потік на кожен процесор, і під Rosetta кожен постійно шукає роботу. | Сколько процессоров, по мнению игры, у Mac. Игры на Unity 5 запускают рабочий поток на каждый процессор, и под Rosetta каждый постоянно ищет работу. | удаляется (шаг 1) |
| `setting.processors.help.entry[All].name` | All | Усі | Все | удаляется (шаг 1) |
| `setting.processors.help.entry[All]` | The game sees every processor, as on Windows. | Гра бачить усі процесори, як у Windows. | Игра видит все процессоры, как в Windows. | удаляется (шаг 1) |
| `setting.processors.help.entry[8 · 6 · 4]` | The game sees that many and starts that many workers. | Гра бачить стільки й запускає стільки робочих потоків. | Игра видит столько и запускает столько рабочих потоков. | удаляется (шаг 1) |
| `setting.processors.choice[0]` | All | Усі | Все | удаляется (шаг 1) |
| `setting.unifiedMemory.title` | Unified memory | Єдина пам’ять | Единая память |  |
| `setting.unifiedMemory.caption` | Tells games the GPU shares the Mac's memory. | Повідомляє іграм, що GPU ділить пам’ять Mac. | Сообщает играм, что GPU делит память Mac. |  |
| `setting.unifiedMemory.help.summary` | A Mac has one pool of memory for the processor and the graphics chip. Windows games expect a separate card and copy every texture twice. With this on the game is told the truth (UMA) and writes each texture once. | У Mac одна пам’ять для процесора й графіки. Ігри Windows чекають окрему відеокарту й копіюють кожну текстуру двічі. З цим налаштуванням гра знає правду (UMA) і пише текстуру один раз. | У Mac одна память для процессора и графики. Игры Windows ждут отдельную видеокарту и копируют каждую текстуру дважды. С этой настройкой игра знает правду (UMA) и пишет текстуру один раз. |  |
| `setting.unifiedMemory.help.entry[If a game misbehaves].name` | If a game misbehaves | Якщо гра поводиться дивно | Если игра ведёт себя странно |  |
| `setting.unifiedMemory.help.entry[If a game misbehaves]` | Wrong textures or a game that stops at launch: turn it off for that game. | Неправильні текстури чи гра зупиняється на запуску: вимкніть для цієї гри. | Неправильные текстуры или игра останавливается при запуске: выключите для этой игры. |  |
| `setting.largeAddressAware.title` | 4 GB for 32-bit games | 4 ГБ для 32-бітних ігор | 4 ГБ для 32-битных игр |  |
| `setting.largeAddressAware.caption` | A 32-bit game may use 4 GB where Windows would give it 2. | 32-бітна гра може використати 4 ГБ замість 2 у Windows. | 32-битная игра может использовать 4 ГБ вместо 2 в Windows. |  |
| `setting.largeAddressAware.help.summary` | Modded and texture-heavy 32-bit games run out of 2 GB and crash. With this on every 32-bit game gets all 4. | 32-бітні ігри з модами й важкими текстурами вичерпують 2 ГБ і падають. З цим налаштуванням кожна 32-бітна гра отримує всі 4. | 32-битные игры с модами и тяжёлыми текстурами исчерпывают 2 ГБ и падают. С этой настройкой каждая 32-битная игра получает все 4. |  |
| `setting.largeAddressAware.help.entry[If a game misbehaves].name` | If a game misbehaves | Якщо гра поводиться дивно | Если игра ведёт себя странно |  |
| `setting.largeAddressAware.help.entry[If a game misbehaves]` | A few old games crash above 2 GB: turn it off for that game. | Кілька старих ігор падають вище 2 ГБ: вимкніть для цієї гри. | Несколько старых игр падают выше 2 ГБ: выключите для этой игры. |  |
| `setting.avx.title` | Report AVX to games | Повідомляти іграм про AVX | Сообщать играм об AVX |  |
| `setting.avx.caption` | Games that check for AVX at launch find it. | Ігри, що перевіряють AVX на старті, знаходять його. | Игры, проверяющие AVX при запуске, находят его. |  |
| `setting.avx.help.summary` | Many games since 2020 require AVX and AVX2. Rosetta translates them either way; this makes it say so. | Багато ігор після 2020 року вимагають AVX і AVX2. Rosetta перекладає їх у будь-якому разі; це налаштування змушує її про це повідомляти. | Многие игры после 2020 года требуют AVX и AVX2. Rosetta переводит их в любом случае; эта настройка заставляет её об этом сообщать. |  |
| `setting.avx.help.entry[If a game misbehaves].name` | If a game misbehaves | Якщо гра поводиться дивно | Если игра ведёт себя странно |  |
| `setting.avx.help.entry[If a game misbehaves]` | A game that picks a slower AVX path can run better with this off. | Гра, що обирає повільніший шлях з AVX, може працювати краще без цього. | Игра, которая выбирает более медленный путь с AVX, может работать лучше без этого. |  |
| `setting.gpu.title` | Graphics card for the game | Відеокарта для гри | Видеокарта для игры | удаляется (шаг 1) |
| `setting.gpu.caption` | Which card the game is told it runs on. | Яку відеокарту бачить гра. | Какую видеокарту видит игра. | удаляется (шаг 1) |
| `setting.gpu.help.summary` | Some games refuse an unknown card or pick their settings by vendor. The engine and DXMT then name the card chosen here. | Деякі ігри відмовляються працювати з невідомою картою або обирають налаштування за виробником. Тоді рушій і DXMT називають обрану тут карту. | Некоторые игры отказываются работать с неизвестной картой или выбирают настройки по производителю. Тогда движок и DXMT называют выбранную здесь карту. | удаляется (шаг 1) |
| `setting.gpu.help.entry[As is].name` | As is | Як є | Как есть | удаляется (шаг 1) |
| `setting.gpu.help.entry[As is]` | The engine's own answer. | Власна відповідь рушія. | Собственный ответ движка. | удаляется (шаг 1) |
| `setting.gpu.help.entry[AMD · NVIDIA · Intel Arc A750]` | A Radeon RX 7900 XT, a GeForce RTX 5080 or an Arc A750 with a current driver version. | Radeon RX 7900 XT, GeForce RTX 5080 чи Arc A750 з актуальною версією драйвера. | Radeon RX 7900 XT, GeForce RTX 5080 или Arc A750 с актуальной версией драйвера. | удаляется (шаг 1) |
| `setting.gpu.choice[as-is]` | As is | Як є | Как есть | удаляется (шаг 1) |
| `setting.gpu.choice[custom]` | Custom | Своє | Своё | удаляется (шаг 1) |
| `setting.dllOverrides.title` | DLL overrides | Заміни DLL | Замены DLL | удаляется (шаг 1) |
| `setting.dllOverrides.caption` | Which copy of a Windows library Wine loads. | Яку копію бібліотеки Windows завантажує Wine. | Какую копию библиотеки Windows загружает Wine. | удаляется (шаг 1) |
| `setting.dllOverrides.help.summary` | Wine ships its own version of most Windows libraries and prefers it. An override changes that for one library. | Wine має власні версії більшості бібліотек Windows і віддає їм перевагу. Заміна змінює це для однієї бібліотеки. | У Wine есть собственные версии большинства библиотек Windows, и он предпочитает их. Замена меняет это для одной библиотеки. | удаляется (шаг 1) |
| `setting.dllOverrides.help.entry[Native, then built-in].name` | Native, then built-in | Рідна, потім вбудована | Родная, затем встроенная | удаляется (шаг 1) |
| `setting.dllOverrides.help.entry[Native, then built-in]` | The copy the game brought, Wine's where there is none. What mod loaders and ReShade need. | Копія, яку принесла гра, а якщо її немає — від Wine. Потрібно для завантажувачів модів і ReShade. | Копия, которую принесла игра, а если её нет — от Wine. Нужно для загрузчиков модов и ReShade. | удаляется (шаг 1) |
| `setting.dllOverrides.help.entry[Built-in, then native].name` | Built-in, then native | Вбудована, потім рідна | Встроенная, затем родная | удаляется (шаг 1) |
| `setting.dllOverrides.help.entry[Built-in, then native]` | Wine's copy first: Wine's usual order. | Спершу копія Wine: звичний порядок Wine. | Сначала копия Wine: обычный порядок Wine. | удаляется (шаг 1) |
| `setting.dllOverrides.help.entry[Disabled].name` | Disabled | Вимкнено | Отключено | удаляется (шаг 1) |
| `setting.dllOverrides.help.entry[Disabled]` | The library is not loaded at all. | Бібліотека не завантажується зовсім. | Библиотека не загружается вовсе. | удаляется (шаг 1) |
| `setting.dllOverrides.help.footnote` | The renderer's and Steam's own libraries follow NotProton and cannot be overridden here. | Бібліотеки рендерера та Steam керуються NotProton, тут їх не замінити. | Библиотеки рендерера и Steam управляются NotProton, здесь их не заменить. | удаляется (шаг 1) |
| `setting.dllOverrides.choice[n,b]` | Native, then built-in | Рідна, потім вбудована | Родная, затем встроенная | удаляется (шаг 1) |
| `setting.dllOverrides.choice[b,n]` | Built-in, then native | Вбудована, потім рідна | Встроенная, затем родная | удаляется (шаг 1) |
| `setting.dllOverrides.choice[n]` | Native only | Лише рідна | Только родная | удаляется (шаг 1) |
| `setting.dllOverrides.choice[b]` | Built-in only | Лише вбудована | Только встроенная | удаляется (шаг 1) |
| `setting.dllOverrides.choice[]` | Disabled | Вимкнено | Отключено | удаляется (шаг 1) |
| `setting.environment.title` | Environment variables | Змінні середовища | Переменные окружения | удаляется (шаг 1) |
| `setting.environment.caption` | For advice that names a variable. | Для порад, що називають змінну. | Для советов, которые называют переменную. | удаляется (шаг 1) |
| `setting.environment.help.summary` | One VARIABLE=value per line, given to every program of the game. Steam launch options such as VAR=1 %command% are accepted too. | Одна ЗМІННА=значення в рядку, для кожної програми гри. Приймаються й параметри запуску Steam на кшталт VAR=1 %command%. | Одна ПЕРЕМЕННАЯ=значение в строке, для каждой программы игры. Принимаются и параметры запуска Steam вроде VAR=1 %command%. | удаляется (шаг 1) |
| `setting.environment.help.footnote` | Variables NotProton sets itself (WINEDLLOVERRIDES, WINEPREFIX, WINEMSYNC and the ones settings above own) are refused. | Змінні, які NotProton задає сам (WINEDLLOVERRIDES, WINEPREFIX, WINEMSYNC і ті, що належать налаштуванням вище), не приймаються. | Переменные, которые NotProton задаёт сам (WINEDLLOVERRIDES, WINEPREFIX, WINEMSYNC и те, что принадлежат настройкам выше), не принимаются. | удаляется (шаг 1) |
| `setting.msync.caption` | Always on. Turn it off only to test a problem in this game. | Завжди увімкнено. Вимикайте лише для перевірки проблеми в цій грі. | Всегда включён. Выключайте только для проверки проблемы в этой игре. |  |
| `setting.msync.help.summary` | Dormison's fast synchronisation of a game's threads through Mach semaphores. Off, the game falls back to Wine's slower server sync. | Швидка синхронізація потоків гри в Dormison через семафори Mach. Без неї гра повертається до повільнішої синхронізації через сервер Wine. | Быстрая синхронизация потоков игры в Dormison через семафоры Mach. Без неё игра возвращается к более медленной синхронизации через сервер Wine. |  |
| `text.add` | Add | Додати | Добавить |  |
| `text.advanced` | Advanced settings… | Додаткові налаштування… | Дополнительные настройки… |  |
| `text.advancedGlobalTitle` | Advanced settings for all games | Додаткові налаштування для всіх ігор | Дополнительные настройки для всех игр |  |
| `text.advancedTitle` | Advanced settings — %@ | Додаткові налаштування — %@ | Дополнительные настройки — %@ |  |
| `text.apply` | Apply | Застосувати | Применить |  |
| `text.backOff` | Back off | Відступати | Отступать |  |
| `text.close` | Close | Закрити | Закрыть |  |
| `text.customValue` | Custom… | Своє… | Своё… |  |
| `text.defaultValue` | NotProton default: %@ | Типово в NotProton: %@ | По умолчанию в NotProton: %@ |  |
| `text.deviceID` | Device ID (hex) | ID пристрою (hex) | ID устройства (hex) |  |
| `text.dllPlaceholder` | library, e.g. d3dcompiler_47 | бібліотека, напр. d3dcompiler_47 | библиотека, напр. d3dcompiler_47 |  |
| `text.done` | Done | Готово | Готово |  |
| `text.envPlaceholder` | VARIABLE=value or Steam launch options | ЗМІННА=значення або параметри запуску Steam | ПЕРЕМЕННАЯ=значение или параметры запуска Steam |  |
| `text.executables` | Game files: %@ | Файли гри: %@ | Файлы игры: %@ |  |
| `text.experimental` | experimental | експеримент | эксперимент |  |
| `text.firstLaunch` | The game has not started under NotProton yet: settings apply at its first launch. | Гру ще не запускали через NotProton: налаштування діють з першого запуску. | Игру ещё не запускали через NotProton: настройки применятся при первом запуске. |  |
| `text.fpsPlaceholder` | frames per second | кадрів за секунду | кадров в секунду |  |
| `text.globalApplies` | Changes apply the next time each game starts. | Зміни діють з наступного запуску кожної гри. | Изменения применятся при следующем запуске каждой игры. |  |
| `text.globalCaption` | A game can set its own value in its Properties. | Гра може задати своє значення у своїх властивостях. | Игра может задать своё значение в своих свойствах. |  |
| `text.globalSection` | NotProton — for all games | NotProton — для всіх ігор | NotProton — для всех игр |  |
| `text.gpuName` | Name | Назва | Название |  |
| `text.inherited` | For all games: %@ | Для всіх ігор: %@ | Для всех игр: %@ |  |
| `text.invalid` | This value is not accepted. | Це значення не підходить. | Это значение не подходит. |  |
| `text.memory` | Memory, MB | Пам’ять, МБ | Память, МБ |  |
| `text.nextLaunch` | Changes apply the next time the game starts. | Зміни діють з наступного запуску гри. | Изменения применятся при следующем запуске игры. |  |
| `text.objectSpin` | Object spin | Об’єкти (spin) | Объекты (spin) |  |
| `text.own` | Custom | Своє | Своё |  |
| `text.ownGlobal` | Changed | Змінено | Изменено |  |
| `text.remove` | Remove | Видалити | Удалить |  |
| `text.resetGame` | Reset game settings | Скинути налаштування гри | Сбросить настройки игры |  |
| `text.resetGlobal` | Reset to NotProton defaults | Повернути типові NotProton | Вернуть настройки NotProton по умолчанию |  |
| `text.restartGame` | The game is running: changes apply after you restart it. | Гра запущена: зміни діють після її перезапуску. | Игра запущена: изменения применятся после её перезапуска. |  |
| `text.saveFailed` | Could not save: %@ | Не вдалося зберегти: %@ | Не удалось сохранить: %@ |  |
| `text.unavailable` | NotProton settings are unavailable: %@ | Налаштування NotProton недоступні: %@ | Настройки NotProton недоступны: %@ |  |
| `text.vendorID` | Vendor ID (hex) | ID виробника (hex) | ID производителя (hex) |  |
| `text.waitSpin` | Wait spin | Очікування (spin) | Ожидание (spin) |  |

<!-- rows=191 same=29 -->
