# Тексты каталога настроек — на проверку

Выгрузка 09.10.2026 после шага 2 «Поправки 09.10» (`docs/ROADMAP.md` §13), из `notproton-settings catalog` сборки `3C98864C`, которая сейчас стоит в Steam. Первая выгрузка (до шага 2, со строками удалённых настроек) — в истории git, коммит `0551508`. Переводы и описания правит пользователь; агент их не меняет.

- **Где в коде:** тексты настроек — `app/Sources/NotProtonSettings/SettingCopy.swift` (по одному `SettingCopy` на настройку), общие слова панели (`text.*`) — там же, `PanelText.all`; варианты выбора — `SettingCatalog.swift`; названия разделов — `GroupTitles` в `SettingCopy.swift`.
- **Ключ:** `group.<id>.title` — раздел; `setting.<id>.title` — название, `.caption` — серая строка под ним, `.help.summary` / `.help.entry[…]` / `.help.footnote` — подсказка (i), `.choice[…]` — пункт списка; `text.<ключ>` — общие слова панели (`%@` — подставляемое значение).
- **Не включены** строки, одинаковые во всех языках (DXMT, MetalFX, Lanczos, msync+ и т. п.).
- Тексты D3DMetal (шаг 3) появятся после него; выгружу заново.

| ключ | en | uk | ru |
|---|---|---|---|
| `group.picture.title` | Graphics | Графіка | Графика |
| `group.mouse.title` | Mouse | Миша | Мышь |
| `group.performance.title` | Performance | Продуктивність | Производительность |
| `group.oldGames.title` | Old games | Старі ігри | Старые игры |
| `group.diagnostics.title` | Diagnostics | Діагностика | Диагностика |
| `setting.renderer.title` | Renderer | Рендерер | Рендерер |
| `setting.renderer.help.summary` | How the game's graphics (Direct3D) are shown on your Mac. If a game looks wrong or won't start, try another option. | Як графіка гри (Direct3D) показується на вашому Mac. Якщо гра виглядає неправильно або не запускається, спробуйте інший варіант. | Как графика игры (Direct3D) показывается на вашем Mac. Если игра выглядит неправильно или не запускается, попробуйте другой вариант. |
| `setting.renderer.help.entry[DXMT]` | Direct3D 10 and 11 straight through Metal. The fastest option for most games. | Direct3D 10 і 11 напряму через Metal. Найшвидший варіант для більшості ігор. | Direct3D 10 и 11 напрямую через Metal. Самый быстрый вариант для большинства игр. |
| `setting.renderer.help.entry[DXVK]` | Direct3D 10 and 11 through Vulkan (MoltenVK). Try it if DXMT draws a game wrong. | Direct3D 10 і 11 через Vulkan (MoltenVK). Спробуйте, якщо DXMT неправильно малює гру. | Direct3D 10 и 11 через Vulkan (MoltenVK). Попробуйте, если DXMT неправильно рисует игру. |
| `setting.renderer.help.entry[WineD3D]` | Wine's built-in renderer (OpenGL). Direct3D 9 games always use it; Direct3D 11 games only at feature level 9_3. | Вбудований рендерер Wine (OpenGL). Ігри на Direct3D 9 завжди йдуть через нього, а Direct3D 11 — лише на рівні 9_3. | Встроенный рендерер Wine (OpenGL). Игры на Direct3D 9 всегда идут через него, а Direct3D 11 — только на уровне 9_3. |
| `setting.renderer.help.footnote` | Direct3D 12 needs D3DMetal from Apple's Game Porting Toolkit. You add it yourself. | Для Direct3D 12 потрібен D3DMetal із Game Porting Toolkit від Apple. Ви додаєте його самі. | Для Direct3D 12 нужен D3DMetal из Game Porting Toolkit от Apple. Вы добавляете его сами. |
| `setting.retina.title` | High resolution (Retina) | Висока роздільність (Retina) | Высокое разрешение (Retina) |
| `setting.retina.caption` | The game draws at the screen's full pixel resolution. | Гра малює в повній роздільності екрана. | Игра рисует в полном разрешении экрана. |
| `setting.retina.help.summary` | Retina screens have four pixels for every point macOS counts in. By default a game gets the size in points, and the picture is stretched. | Екран Retina має чотири пікселі на кожну точку, якими рахує macOS. Типово гра отримує розмір у точках, і картинка розтягується. | У экрана Retina четыре пикселя на каждую точку, которыми считает macOS. По умолчанию игра получает размер в точках, и картинка растягивается. |
| `setting.retina.help.entry[On].name` | On | Увімк. | Вкл. |
| `setting.retina.help.entry[On]` | Sharp picture at the screen's real resolution, but fewer frames. Old games may show tiny text and menus. | Чітка картинка в реальній роздільності екрана, але менше кадрів. У старих іграх текст і меню можуть бути дрібними. | Чёткая картинка в реальном разрешении экрана, но кадров меньше. В старых играх текст и меню могут быть мелкими. |
| `setting.retina.help.entry[Off].name` | Off | Вимк. | Выкл. |
| `setting.retina.help.entry[Off]` | Half the pixels in each direction: faster and a bit softer, and everything stays readable. | Удвічі менше пікселів по кожній осі: швидше й трохи м’якше, усе лишається читабельним. | Вдвое меньше пикселей по каждой оси: быстрее и чуть мягче, всё остаётся читаемым. |
| `setting.retina.help.footnote` | Saved to the game's Wine registry at launch. | Зберігається в реєстрі Wine гри під час запуску. | Сохраняется в реестре Wine игры при запуске. |
| `setting.upscaler.title` | Upscaler | Апскейлер | Апскейлер |
| `setting.upscaler.caption` | Enlarges a picture the game draws smaller than the window. | Збільшує картинку, яку гра малює меншою за вікно. | Увеличивает картинку, которую игра рисует меньше окна. |
| `setting.upscaler.help.summary` | Two steps between the game and the window: the upscaler, then the final filter. | Два кроки між грою та вікном: апскейлер, потім фінальний фільтр. | Два шага между игрой и окном: апскейлер, потом финальный фильтр. |
| `setting.upscaler.help.entry[Off].name` | Off | Вимк. | Выкл. |
| `setting.upscaler.help.entry[Off]` | macOS stretches the picture softly. A smaller picture keeps black borders. | macOS м’яко розтягує картинку. Менша картинка лишається з чорними смугами. | macOS мягко растягивает картинку. Меньшая картинка остаётся с чёрными полосами. |
| `setting.upscaler.help.entry[Final filter only].name` | Final filter only | Лише фінальний фільтр | Только финальный фильтр |
| `setting.upscaler.help.entry[Final filter only]` | No upscaler: the final filter just fits the picture to the window. | Без апскейлера: фінальний фільтр лише підганяє картинку під вікно. | Без апскейлера: финальный фильтр просто подгоняет картинку под окно. |
| `setting.upscaler.help.entry[MetalFX Spatial]` | For 3D games that render below the screen's resolution. | Для 3D-ігор, які рендеряться в роздільності нижчій за екранну. | Для 3D-игр, которые рендерятся в разрешении ниже экранного. |
| `setting.upscaler.help.footnote` | View › Upscaler in the game's menu changes it while you play. NotProton remembers your choice. | View › Upscaler у меню гри змінює його під час гри. NotProton запам’ятовує ваш вибір. | View › Upscaler в меню игры меняет его во время игры. NotProton запоминает ваш выбор. |
| `setting.upscaler.choice[off]` | Off | Вимк. | Выкл. |
| `setting.upscaler.choice[lanczos]` | Final filter only | Лише фінальний фільтр | Только финальный фильтр |
| `setting.fps.title` | Frame rate counter | Лічильник FPS | Счётчик FPS |
| `setting.fps.caption` | Apple's Metal HUD shown over the game. | Metal HUD від Apple поверх гри. | Metal HUD от Apple поверх игры. |
| `setting.fps.help.summary` | Apple's own performance overlay: frames per second, frame time and GPU memory, taken from the graphics driver. Works in games that draw through Metal: DXMT, DXVK and D3DMetal. | Власна накладка Apple з показниками: кадри за секунду, час кадру й пам’ять GPU — дані беруться з графічного драйвера. Працює в іграх, що малюють через Metal: DXMT, DXVK і D3DMetal. | Собственная панель Apple с показателями: кадры в секунду, время кадра и память GPU — данные берутся из графического драйвера. Работает в играх, которые рисуют через Metal: DXMT, DXVK и D3DMetal. |
| `setting.windows.title` | Resizable windows | Вікна зі змінним розміром | Изменяемый размер окон |
| `setting.windows.caption` | Lets you resize the game window; the picture scales to fit. | Дозволяє змінювати розмір вікна гри; картинка масштабується. | Позволяет менять размер окна игры; картинка масштабируется. |
| `setting.windows.help.summary` | A game draws at the size it picked. With resizable windows that picture is scaled to the window, and the game thinks nothing changed. | Гра малює в обраному нею розмірі. Зі змінним розміром цю картинку масштабують під вікно, а гра вважає, що нічого не змінилося. | Игра рисует в выбранном ею размере. С изменяемым размером эту картинку масштабируют под окно, а игра считает, что ничего не изменилось. |
| `setting.windows.help.entry[Never].name` | Never | Ніколи | Никогда |
| `setting.windows.help.entry[Never]` | Windows stay as the game makes them. A full-screen game covers the screen. | Вікна такі, як їх робить гра. Повноекранна гра займає весь екран. | Окна такие, как их делает игра. Полноэкранная игра занимает весь экран. |
| `setting.windows.help.entry[Fixed-size windows].name` | Fixed-size windows | Вікна фіксованого розміру | Окна фиксированного размера |
| `setting.windows.help.entry[Fixed-size windows]` | A window the game locks to one size gets a resize handle, and the picture scales. | Вікно, яке гра зафіксувала в одному розмірі, можна розтягувати, а картинка масштабується. | Окно, которое игра зафиксировала в одном размере, можно растягивать, а картинка масштабируется. |
| `setting.windows.help.entry[Fixed-size and full-screen games].name` | Fixed-size and full-screen games | Фіксовані й повноекранні ігри | Фиксированные и полноэкранные игры |
| `setting.windows.help.entry[Fixed-size and full-screen games]` | Also, a full-screen game runs in a window you can move and resize. | Також повноекранна гра йде у вікні, яке можна переміщати й розтягувати. | Также полноэкранная игра идёт в окне, которое можно перемещать и растягивать. |
| `setting.windows.help.entry[Every window with a title bar].name` | Every window with a title bar | Кожне вікно із заголовком | Каждое окно с заголовком |
| `setting.windows.help.entry[Every window with a title bar]` | Windows the game already lets you resize are scaled as well, instead of being redrawn. | Вікна, розмір яких гра й так дозволяє змінювати, теж масштабуються, а не перемальовуються. | Окна, размер которых игра и так позволяет менять, тоже масштабируются, а не перерисовываются. |
| `setting.windows.help.footnote` | View › Resizable Windows in the game's menu changes it. NotProton remembers your choice. | View › Resizable Windows у меню гри змінює це. NotProton запам’ятовує ваш вибір. | View › Resizable Windows в меню игры меняет это. NotProton запоминает ваш выбор. |
| `setting.windows.choice[off]` | Never | Ніколи | Никогда |
| `setting.windows.choice[fixed]` | Fixed-size windows | Вікна фіксованого розміру | Окна фиксированного размера |
| `setting.windows.choice[window]` | Fixed-size and full-screen games | Фіксовані й повноекранні ігри | Фиксированные и полноэкранные игры |
| `setting.windows.choice[all]` | Every window with a title bar | Кожне вікно із заголовком | Каждое окно с заголовком |
| `setting.filter.title` | Final filter | Фінальний фільтр | Финальный фильтр |
| `setting.filter.help.summary` | Fits the upscaler's picture to the exact window size. Works only while an upscaler is on. | Підганяє картинку апскейлера під точний розмір вікна. Працює, лише коли апскейлер увімкнено. | Подгоняет картинку апскейлера под точный размер окна. Работает, только когда апскейлер включён. |
| `setting.filter.help.entry[Nearest].name` | Nearest | Найближчий | Ближайший |
| `setting.filter.help.entry[Nearest]` | Copies pixels. Crisp at whole-number scales, uneven at others. | Копіює пікселі. Чітко при цілому масштабі, нерівно при інших. | Копирует пиксели. Чётко при целом масштабе, неровно при остальных. |
| `setting.filter.help.entry[Bilinear].name` | Bilinear | Білінійний | Билинейный |
| `setting.filter.help.entry[Bilinear]` | Blends neighbouring pixels. The softest option. | Змішує сусідні пікселі. Найм’якший варіант. | Смешивает соседние пиксели. Самый мягкий вариант. |
| `setting.filter.help.entry[Lanczos]` | Sharp resampling that works well at fractional scales. | Чітке перемасштабування, добре для дробових масштабів. | Чёткое масштабирование, хорошо подходит для дробных масштабов. |
| `setting.filter.choice[nearest]` | Nearest | Найближчий | Ближайший |
| `setting.filter.choice[bilinear]` | Bilinear | Білінійний | Билинейный |
| `setting.dlss.caption` | For games with DLSS: MetalFX works in its place, and the game sees an NVIDIA GeForce RTX 5060 Ti. | Для ігор із DLSS: замість нього працює MetalFX, а гра бачить NVIDIA GeForce RTX 5060 Ti. | Для игр с DLSS: вместо него работает MetalFX, а игра видит NVIDIA GeForce RTX 5060 Ti. |
| `setting.dlss.help.summary` | DXMT answers the game's NVIDIA (NVAPI) and DLSS calls and upscales with MetalFX. Works with DXMT only. | DXMT відповідає на виклики NVIDIA (NVAPI) і DLSS від гри та масштабує через MetalFX. Працює лише з DXMT. | DXMT отвечает на вызовы NVIDIA (NVAPI) и DLSS от игры и масштабирует через MetalFX. Работает только с DXMT. |
| `setting.dlss.help.entry[Graphics card].name` | Graphics card | Відеокарта | Видеокарта |
| `setting.dlss.help.entry[Graphics card]` | NotProton chooses the card the game sees: an AMD Radeon RX 9060 XT, or, with this on, an NVIDIA GeForce RTX 5060 Ti, because games offer DLSS only on NVIDIA. | NotProton сам обирає відеокарту, яку бачить гра: AMD Radeon RX 9060 XT, а з цією опцією — NVIDIA GeForce RTX 5060 Ti, бо ігри пропонують DLSS лише на NVIDIA. | NotProton сам выбирает видеокарту, которую видит игра: AMD Radeon RX 9060 XT, а с этой опцией — NVIDIA GeForce RTX 5060 Ti, потому что игры предлагают DLSS только на NVIDIA. |
| `setting.dlss.help.entry[If a game misbehaves].name` | If a game misbehaves | Якщо гра поводиться дивно | Если игра ведёт себя странно |
| `setting.dlss.help.entry[If a game misbehaves]` | Turn it off for that game. Few games have been tested this way. | Вимкніть для цієї гри. Цим шляхом перевірено мало ігор. | Выключите для этой игры. Этим путём проверено мало игр. |
| `setting.mouse.title` | Mouse movement | Рух миші | Движение мыши |
| `setting.mouse.caption` | What the game receives when it captures the pointer for mouse-look. | Що отримує гра, коли захоплює курсор для огляду мишею. | Что получает игра, когда захватывает курсор для обзора мышью. |
| `setting.mouse.help.summary` | Applies only while a game has captured the pointer, as a first-person camera does. Menus and the desktop keep the Mac's normal pointer. | Діє лише тоді, коли гра захопила курсор, як камера від першої особи. У меню й на робочому столі курсор лишається звичайним, як у Mac. | Действует только когда игра захватила курсор, как камера от первого лица. В меню и на рабочем столе курсор остаётся обычным, как в Mac. |
| `setting.mouse.help.entry[macOS acceleration].name` | macOS acceleration | Прискорення macOS | Ускорение macOS |
| `setting.mouse.help.entry[macOS acceleration]` | The usual pointer curve: a fast flick goes farther than a slow movement of the same length. | Звичайна крива курсора: швидкий рух відводить далі, ніж повільний такої ж довжини. | Обычная кривая курсора: быстрый рывок уводит дальше, чем медленное движение той же длины. |
| `setting.mouse.help.entry[Linear (no acceleration)].name` | Linear (no acceleration) | Лінійний (без прискорення) | Линейное (без ускорения) |
| `setting.mouse.help.entry[Linear (no acceleration)]` | The same hand movement turns the camera the same amount at any speed. What shooters expect. | Однаковий рух руки повертає камеру однаково за будь-якої швидкості. Саме цього чекають шутери. | Одинаковое движение руки поворачивает камеру одинаково при любой скорости. Именно этого ждут шутеры. |
| `setting.mouse.choice[system]` | macOS acceleration | Прискорення macOS | Ускорение macOS |
| `setting.mouse.choice[linear]` | Linear (no acceleration) | Лінійний (без прискорення) | Линейное (без ускорения) |
| `setting.tuning.title` | Thread waiting | Очікування потоків | Ожидание потоков |
| `setting.tuning.caption` | How long a game's threads look for work before they sleep. | Як довго потоки гри шукають роботу, перш ніж заснути. | Как долго потоки игры ищут работу, прежде чем уснуть. |
| `setting.tuning.help.summary` | Putting a thread to sleep and waking it costs much more on macOS than on Windows, so a thread can briefly spin and wait for its wake-up. | Приспати потік і розбудити його на macOS значно дорожче, ніж у Windows, тому потік може ненадовго «покрутитися» в очікуванні. | Усыпить поток и разбудить его на macOS заметно дороже, чем в Windows, поэтому поток может ненадолго «покрутиться» в ожидании. |
| `setting.tuning.help.entry[Standard].name` | Standard | Стандарт | Стандарт |
| `setting.tuning.help.entry[Standard]` | A waiting thread goes to sleep at once, as in Wine. | Потік, що чекає, одразу засинає, як у Wine. | Ждущий поток сразу засыпает, как в Wine. |
| `setting.tuning.help.entry[Experimental].name` | Experimental | Експериментально | Экспериментально |
| `setting.tuning.help.entry[Experimental]` | Spins for about two microseconds first (5200, 1, 5200). Hand-offs get faster; a game with more busy threads than cores pays with extra processor time. | Спершу крутиться близько двох мікросекунд (5200, 1, 5200). Передача роботи між потоками швидша, але гра, у якої зайнятих потоків більше, ніж ядер, витрачає більше часу процесора. | Сначала крутится около двух микросекунд (5200, 1, 5200). Передача работы между потоками быстрее, но игра, у которой занятых потоков больше, чем ядер, тратит больше времени процессора. |
| `setting.tuning.help.entry[Custom].name` | Custom values | Власні значення | Свои значения |
| `setting.tuning.help.entry[Custom]` | Wait spin and Object spin count loop iterations of about 0.4 ns each, from 0 to 1 000 000. Back off stops spinning when waits keep coming up empty. | «Очікування» й «Об’єкти» — кількість ітерацій циклу по ~0,4 нс, від 0 до 1 000 000. «Відступати» зупиняє крутіння, якщо очікування раз у раз марне. | «Ожидание» и «Объекты» — число итераций цикла по ~0,4 нс, от 0 до 1 000 000. «Отступать» останавливает кручение, если ожидание раз за разом оказывается напрасным. |
| `setting.tuning.help.footnote` | Measure with the frame rate counter. Most games show no difference. | Вимірюйте лічильником FPS. У більшості ігор різниці немає. | Измеряйте счётчиком FPS. В большинстве игр разницы нет. |
| `setting.tuning.choice[standard]` | Standard | Стандарт | Стандарт |
| `setting.tuning.choice[experimental]` | Experimental | Експериментально | Экспериментально |
| `setting.tuning.choice[custom]` | Custom values | Власні значення | Свои значения |
| `setting.unifiedMemory.title` | Unified memory | Єдина пам’ять | Единая память |
| `setting.unifiedMemory.caption` | Tells games the GPU shares memory with the Mac. | Повідомляє іграм, що GPU ділить пам’ять із Mac. | Сообщает играм, что GPU делит память с Mac. |
| `setting.unifiedMemory.help.summary` | A Mac has one memory pool for the processor and graphics. Windows games expect a separate graphics card and copy every texture twice. With this on, the game is told the truth (UMA) and writes each texture once. | У Mac одна пам’ять і для процесора, і для графіки. Ігри Windows чекають окрему відеокарту й копіюють кожну текстуру двічі. З цією опцією гра знає правду (UMA) і записує текстуру один раз. | У Mac одна память и для процессора, и для графики. Игры Windows ждут отдельную видеокарту и копируют каждую текстуру дважды. С этой опцией игра знает правду (UMA) и записывает текстуру один раз. |
| `setting.unifiedMemory.help.entry[If a game misbehaves].name` | If a game misbehaves | Якщо гра поводиться дивно | Если игра ведёт себя странно |
| `setting.unifiedMemory.help.entry[If a game misbehaves]` | Wrong textures, or a game that stops at launch: turn it off for that game. | Неправильні текстури або гра зупиняється під час запуску: вимкніть для цієї гри. | Неправильные текстуры или игра останавливается при запуске: выключите для этой игры. |
| `setting.avx.title` | Report AVX to games | Повідомляти іграм про AVX | Сообщать играм об AVX |
| `setting.avx.caption` | Games that check for AVX at launch will find it. | Ігри, які перевіряють AVX під час запуску, його знайдуть. | Игры, которые проверяют AVX при запуске, его найдут. |
| `setting.avx.help.summary` | Many games since 2020 require AVX and AVX2. Rosetta can run them either way; this setting makes it report that support. | Багато ігор після 2020 року вимагають AVX і AVX2. Rosetta виконує їх у будь-якому разі; ця опція змушує її повідомляти про підтримку. | Многие игры после 2020 года требуют AVX и AVX2. Rosetta выполняет их в любом случае; эта опция заставляет её сообщать о поддержке. |
| `setting.avx.help.entry[If a game misbehaves].name` | If a game misbehaves | Якщо гра поводиться дивно | Если игра ведёт себя странно |
| `setting.avx.help.entry[If a game misbehaves]` | A game that picks a slower AVX code path may run better with this off. | Гра, що обирає повільніший шлях з AVX, може працювати краще без цього. | Игра, которая выбирает более медленный путь с AVX, может работать лучше без этого. |
| `setting.emulateModeset.title` | Display mode emulation | Емуляція зміни роздільності | Эмуляция смены разрешения |
| `setting.emulateModeset.caption` | When a game changes the screen resolution, it gets a window instead. | Коли гра змінює роздільність екрана, вона отримує натомість вікно. | Когда игра меняет разрешение экрана, она получает вместо этого окно. |
| `setting.emulateModeset.help.summary` | Older games ask Windows to switch the display to 800 × 600 or 1024 × 768. A Mac screen has no such modes. With this on, the game is told the switch happened and its picture goes into a window. | Старі ігри просять Windows перемкнути дисплей на 800 × 600 або 1024 × 768. У екрана Mac таких режимів немає. З цією опцією гра отримує відповідь, що режим змінено, а її картинка йде у вікно. | Старые игры просят Windows переключить дисплей на 800 × 600 или 1024 × 768. У экрана Mac таких режимов нет. С этой опцией игре отвечают, что режим сменился, а её картинка идёт в окно. |
| `setting.emulateModeset.help.footnote` | Saved to the game's Wine registry at launch. | Зберігається в реєстрі Wine гри під час запуску. | Сохраняется в реестре Wine игры при запуске. |
| `setting.largeAddressAware.title` | 4 GB for 32-bit games | 4 ГБ для 32-бітних ігор | 4 ГБ для 32-битных игр |
| `setting.largeAddressAware.caption` | A 32-bit game can use 4 GB where Windows would give it 2. | 32-бітна гра може використати 4 ГБ замість 2 у Windows. | 32-битная игра может использовать 4 ГБ вместо 2 в Windows. |
| `setting.largeAddressAware.help.summary` | 32-bit games with mods or heavy textures run out of 2 GB and crash. With this on, every 32-bit game gets the full 4 GB. | 32-бітні ігри з модами або важкими текстурами вичерпують 2 ГБ і вилітають. З цією опцією кожна 32-бітна гра отримує всі 4 ГБ. | 32-битные игры с модами или тяжёлыми текстурами исчерпывают 2 ГБ и вылетают. С этой опцией каждая 32-битная игра получает все 4 ГБ. |
| `setting.largeAddressAware.help.entry[If a game misbehaves].name` | If a game misbehaves | Якщо гра поводиться дивно | Если игра ведёт себя странно |
| `setting.largeAddressAware.help.entry[If a game misbehaves]` | A few old games crash above 2 GB: turn it off for that game. | Кілька старих ігор вилітають вище 2 ГБ: вимкніть для цієї гри. | Несколько старых игр вылетают выше 2 ГБ: выключите для этой игры. |
| `setting.msync.caption` | Always on. Turn it off only to test a problem in this game. | Завжди увімкнено. Вимикайте лише для перевірки проблеми в цій грі. | Всегда включён. Выключайте только для проверки проблемы в этой игре. |
| `setting.msync.help.summary` | Dormison's fast synchronisation of a game's threads through Mach semaphores. Off, the game falls back to Wine's slower server sync. | Швидка синхронізація потоків гри в Dormison через семафори Mach. Без неї гра повертається до повільнішої синхронізації через сервер Wine. | Быстрая синхронизация потоков игры в Dormison через семафоры Mach. Без неё игра возвращается к более медленной синхронизации через сервер Wine. |
| `text.advanced` | Advanced settings… | Додаткові налаштування… | Дополнительные настройки… |
| `text.advancedGlobalTitle` | Advanced settings for all games | Додаткові налаштування для всіх ігор | Дополнительные настройки для всех игр |
| `text.advancedTitle` | Advanced settings — %@ | Додаткові налаштування — %@ | Дополнительные настройки — %@ |
| `text.backOff` | Back off | Відступати | Отступать |
| `text.close` | Close | Закрити | Закрыть |
| `text.defaultValue` | Default: %@ | Типово: %@ | По умолчанию: %@ |
| `text.done` | Done | Готово | Готово |
| `text.executables` | Game files: %@ | Файли гри: %@ | Файлы игры: %@ |
| `text.experimental` | experimental | експеримент | эксперимент |
| `text.firstLaunch` | The game hasn't been run through NotProton yet. Settings apply from its first launch. | Гру ще не запускали через NotProton. Налаштування діють з першого запуску. | Игру ещё не запускали через NotProton. Настройки применятся при первом запуске. |
| `text.globalApplies` | Changes apply the next time each game starts. | Зміни діють з наступного запуску кожної гри. | Изменения применятся при следующем запуске каждой игры. |
| `text.globalCaption` | A game can have its own value in its Properties. | Гра може мати власне значення у своїх властивостях. | У игры может быть своё значение в её свойствах. |
| `text.globalSection` | NotProton — for all games | NotProton — для всіх ігор | NotProton — для всех игр |
| `text.inherited` | For all games: %@ | Для всіх ігор: %@ | Для всех игр: %@ |
| `text.nextLaunch` | Changes apply the next time the game starts. | Зміни діють з наступного запуску гри. | Изменения применятся при следующем запуске игры. |
| `text.objectSpin` | Object spin | Об’єкти (spin) | Объекты (spin) |
| `text.resetGame` | Reset game settings | Скинути налаштування гри | Сбросить настройки игры |
| `text.resetGlobal` | Reset to defaults | Скинути до типових | Сбросить по умолчанию |
| `text.restartGame` | The game is running. Changes apply after you restart it. | Гра запущена. Зміни діють після її перезапуску. | Игра запущена. Изменения применятся после её перезапуска. |
| `text.saveFailed` | Could not save: %@ | Не вдалося зберегти: %@ | Не удалось сохранить: %@ |
| `text.unavailable` | NotProton settings are unavailable: %@ | Налаштування NotProton недоступні: %@ | Настройки NotProton недоступны: %@ |
| `text.waitSpin` | Wait spin | Очікування (spin) | Ожидание (spin) |

<!-- rows=129 same=13 -->
