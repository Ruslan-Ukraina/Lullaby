# Переменные исправлений игр: что переводим, что отбрасываем

Дата: 2026-10-19. Основа: исходники protonfixes `e89ce7b43800` (473 файла, 29 разных переменных и вспомогательные вызовы). Проверка наличия — grep по исходникам Dormison (`~/Projects/dormison`: `dlls`, `server`, `loader`, `programs`, `libs`) и DXMT (`src`). Принцип владельца: игре ставится только то, что на нашем стеке реально что-то значит.

## Переменные окружения

| Переменная | Игр | Что это в оригинале | У нас | Решение |
|---|---:|---|---|---|
| `OPENSSL_ia32cap`, `SDL_*`, `DOTNET_*` | 5 | настройки самой программы и её рантайма (читает сам Windows-процесс) | работают как есть | **оставляем** (белый список) |
| `LC_ALL` | 1 | локаль unix-стороны Wine | Dormison читает из env-файлов (`load_sevo_env`) | **оставляем** |
| `set_cpu_topology_limit(N)` | 20 вызовов, 9 игр с числом | меньше логических процессоров, только если N меньше ядер машины | `SEVO_CPU_COUNT` есть (`dlls/ntdll/unix/system.c`) | **переводим** в поле `cpuLimit`; применяется только если N < числа процессоров Mac (на M4 Pro: 2, 4, 12 да; 16, 24, 31 нет) |
| `WINE_DISABLE_SFN`, `WINE_NO_OPEN_FILE_SEARCH`, `WINE_BLOCK_HOSTS`, `WINE_MONO_HIDETYPES`, `WINE_DISABLE_KERNEL_WRITEWATCH`, `WINE_DISABLE_VULKAN_OPWR` | 12 | патчи Valve-Wine (Proton) | **нет в Dormison** (0 упоминаний) | отбрасываем |
| `PROTON_*` (`DLL_COPY`, `OLD_GL_STRING`, `ENABLE_INT3_HACK`, `USE_XALIA`, `USE_D7VK`, `NO_D3D10`, `SET_GAME_DRIVE`), `UMU_USE_STEAM`, `SteamDeck` | 40 | флаги Proton | нет аналога | отбрасываем |
| `PULSE_LATENCY_MSEC`, `AMD_DEBUG`, `MESA_*`, `__GL_*`, `radeonsi_*`, `vk_x11_*`, `ENABLE_GAMESCOPE_WSI` | 20 | драйверы и звук Linux | на macOS не существуют | отбрасываем |
| `disable_esync`, `disable_fsync`, `disable_ntsync` | 51 вызов | обходы Linux-синхронизации | у нас msync+ (всегда вкл.) | отбрасываем |
| `disable_nvapi` | 5 | скрыть видеокарту NVIDIA | мы и так сообщаем AMD (DLSS выкл. по умолчанию) | отбрасываем |

Итог на 473 файла: **переносимо 38 записей** (4 вида переменных, 9 лимитов процессоров, 25 переопределений DLL), всё остальное — без аналога.

## Переопределения DLL (25 записей) — осторожно

Вид `WINEDLLOVERRIDES` работает в любом Wine, но многие записи Proton рассчитаны на его набор DLL (`n` = взять Windows-библиотеку, которой у нас нет; `d` = выключить). Поэтому это **кандидаты**, а не рецепты: в каталог попадают только после проверки на движке.

## Правило применения

В записи есть `verifiedOn` (тег движка, на котором исправление проверено). Без него запись показывается, но **не применяется** (`SettingsStore.gameFix`). Импортёр (`tools/import-macgamefix.py`) `verifiedOn` не ставит.

## MacGameFix (GPL-3.0, `process-features.json`)

26 игр по exe: `title`, `symptom`, `backend`, `gptk`, `env` (почти везде пусто), `not_needed_from_gptk`, редко `needs_engine`. Сами исправления — прокси-DLL в папке игры, у нас не принимаются (правило: файлы в папку игры не кладём; через `WINEDLLPATH_PREPEND` — отдельным решением по конкретной игре). Импорт таблицы — следующий шаг (поля `title`, `symptom`, `gptk` в схеме ещё не добавлены).
