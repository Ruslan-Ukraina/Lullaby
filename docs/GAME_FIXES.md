# Каталог исправлений игр (Этап 8)

Статус: дизайн и схема (2026-10-18). Продолжает «рецепты игр» (`GameRecipes.swift`, DECISIONS A1010-3): рецепт остаётся уровнем `recipe` в `ConfigStack`, каталог — его подписанный и обновляемый источник.

## 1. Что это и чем не является

Каталог — данные, а не код. Запись говорит: «для игры с таким AppID или exe нужны такие переменные окружения, переопределения DLL, ключи реестра **Wine** и такой рендерер». Ничего исполняемого в каталоге нет.

Не делаем (жёстко, проверяется валидатором):
- не запускаем чужой Python/shell (`umu-protonfixes` берём только как данные, код не исполняется и не вызывается);
- не кладём прокси-DLL и любые файлы в папку игры, не трогаем файлы настроек и реестр самой игры (CLAUDE.md §8);
- не пишем системные переменные загрузчика (`DYLD_*`, `WINELOADER`, `WINEPREFIX`, `PATH`, …).

## 2. Формат (схема 1)

Файлы релиза: `game-fixes.json` и `game-fixes.json.sig` (загрузка и проверка — готовые `ReleaseFeed.fetch/verify`, целое `serial` не меньше кэшированного; base64 сырой Ed25519-подписи над байтами файла, ключ — наш, как у `signatures-manifest.json`). Неподписанный или с неверной подписью каталог не применяется; остаётся встроенный набор (`GameRecipes.all`).

```json
{
  "schema": 1,
  "serial": 12,
  "entries": [{
    "id": "peak",
    "name": "PEAK",
    "match": { "appIDs": [3527290], "exes": ["peak.exe"] },
    "verdict": "fits",
    "backend": "dxmt",
    "needsEngine": "r6",
    "notNeededFromGPTK": "4.0",
    "env": { "WINE_FOO": "1" },
    "dllOverrides": { "xaudio2_9": "b" },
    "registry": [{ "key": "HKCU\\Software\\Wine\\DllOverrides", "name": "x", "type": "REG_SZ", "value": "native" }],
    "source": { "kind": "lullaby", "ref": "DECISIONS A1010-3", "license": "GPL-3.0" },
    "reason": "DXMT 92.9 FPS against D3DMetal 77–78"
  }]
}
```

Поля:
- `match` — `appIDs` и/или `exes` (нижний регистр, только имя файла). Хотя бы одно непусто. AppID главнее exe (как в `GameRecipes.recipe`).
- `verdict` — как в MacGameFix: `fits` (применять), `not_needed` (исправление не требуется, запись только как пояснение), `unfit` (игра не подходит; показываем причину, ничего не применяем).
- `backend` — `d3dmetal | dxmt | dxvk | wined3d` (то же, что `RendererChoice`) → `ConfigValues.renderer`.
- `needsEngine` — минимальный тег движка; на более старом запись пропускается. `notNeededFromGPTK` — с этой версии GPTK запись не нужна (пропускается).
- `env` — переменные окружения процесса игры. Ключ `[A-Z][A-Z0-9_]*`, значение без перевода строки и NUL, до 256 байт. Запрещены префиксы `DYLD_`, `LD_`, `LULLABY_`, `SEVO_`, имена `WINELOADER`, `WINESERVER`, `WINEPREFIX`, `WINEDLLPATH*`, `WINEDLLOVERRIDES` (для DLL есть своё поле), `PATH`, `HOME`, `MTL_HUD_ENABLED`.
- `dllOverrides` — имя DLL (`[A-Za-z0-9_.-]+`, без путей) → `n | b | n,b | b,n | d`.
- `registry` — только внутри `HKCU\Software\Wine\`, типы `REG_SZ | REG_DWORD`. Реестр игры (`HKCU\Software\<издатель>`) запрещён.
- `source` — `kind`: `lullaby | umu-protonfixes | macgamefix | highball`; `ref` — путь/AppID в источнике; `license`. Для чужих источников обязательны `ref` и `license`.
- Неизвестные поля — ошибка (каталог не принимается целиком), чтобы новые возможности не проходили незамеченными в старом приложении.

## 3. Применение

1. Загружается подписанный каталог; проверка подписи, схемы и каждой записи (валидатор в `LullabySettings/GameFixCatalog.swift`). Одна плохая запись отклоняет весь файл.
2. Запись выбирается по AppID, затем по exe; фильтруются по `needsEngine` и `notNeededFromGPTK`.
3. `backend` становится значениями рецепта (`ConfigValues`); `env`, `dllOverrides`, `registry` пишутся в `<prefix>/.sevo/apps/<exe>.env` и реестр префикса — только как наши настройки (CLAUDE.md §8). Своё значение игрока главнее.
4. Кнопка «Вернуть рецепт» возвращает к значениям записи.

## 4. Импортёр (следующий шаг, не сделан)

`tools/import-umu.py` (запускается у нас в CI, не у пользователя): читает таблицу `umu-database.csv` и каталог `gamefixes-steam/*.py` **как текст**, из известных шаблонов (`util.protontricks`, `util.set_environment`, `util.winedll_override`) извлекает только декларативные вызовы; всё, что не разобралось, пропускает с отчётом. Результат — черновик записей `source.kind = umu-protonfixes`; в каталог попадает после проверки владельцем и теста на движке.

## 5. Тесты (без игр)

`app/Tests/LullabyAppTests/GameFixCatalogTests.swift`: разбор, поиск по AppID/exe, фильтры версий, отказ на неизвестные поля, на запрещённые ключи env, на пути в DLL, на реестр вне `Software\Wine`, на запись без `source.ref` у чужого источника.
