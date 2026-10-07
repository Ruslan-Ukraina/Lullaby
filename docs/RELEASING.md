# RELEASING — ключ релизов и фид NotProton

Заготовка Фазы 5. Фаза 6 допишет сюда CI, Sparkle и прогон на теге (dry-run).
**Ключей я не создавал.** Боевой ключ создаёшь ты, один раз.

## Что подписывается

Приложение доверяет только файлам, подписанным ключом релизов (Ed25519, тот же формат, что у Dormison: `.sig` = base64 сырой подписи над байтами файла):

| Файл | Тег релиза GitHub | Что в нём |
|---|---|---|
| `bridge-manifest.json` + `.sig` | `manifest` | мосты: id, движок, commit, ревизия, sha256 файлов и B1 (DECISIONS P5-1) |
| `signatures-manifest.json` + `.sig` | `manifest` | базы сигнатур и билды Steam, к которым они проверены (P5-3) |
| `bridge-<движок>-<rev>.tar.xz` + `.sig` | `bridge-<движок>-<rev>` | lsteamclient, `steam.exe`, `ntdll/<arch>-ntdll.dll` |
| `<билд>.json` | `signatures` | база сигнатур. Отдельной подписи нет: её sha256 записан в подписанном манифесте |

Адрес фида: `https://github.com/Ruslan-Ukraina/NotProton/releases/download/` (`NPReleaseFeedURL` в `app/Info.plist`, переменная `NP_RELEASE_FEED`).
`serial` в манифесте при каждой публикации увеличивается: старый подписанный манифест приложение не примет.

## 1. Создать ключ (ты, один раз)

```sh
swift release/keygen.swift ~/notproton-release.key
```

- Скрипт пишет приватный ключ в файл (права 0600, существующий не перезаписывает) и печатает публичный (`public key  …`).
- Файл ключа держи **вне репозитория**. Сохрани копию в менеджере паролей: без неё новые мосты и сигнатуры придётся выпускать новой сборкой приложения с новым ключом (RISKS R49).

## 2. Куда положить

- **Приватный ключ** → GitHub → репозиторий → Settings → Secrets and variables → Actions → New repository secret:
  - имя `NP_RELEASE_PRIVATE_KEY`;
  - значение — содержимое файла ключа (одна строка base64).
- **Публичный ключ** → там же, вкладка Variables:
  - имя `NP_RELEASE_PUBLIC_KEY`;
  - сборка приложения в CI: `make app NP_RELEASE_KEY=${{ vars.NP_RELEASE_PUBLIC_KEY }}`.
- Локальная сборка с боевым ключом: `make app NP_RELEASE_KEY=<публичный ключ>`.
  Без ключа (`make app`) фид выключен, приложение работает со встроенными мостом и сигнатурами.

## 3. Публикация (вручную, пока нет CI)

```sh
# мост: новая ревизия из файлов payload (после make bridge и make app-payload)
python3 -I release/feed.py bridge-artifact --manifest bridge/bridge-manifest.json \
    --like bridge-dormison-b1-1 --root app/Sources/NotProtonApp/Resources/payload \
    --rev 2 --feed https://github.com/Ruslan-Ukraina/NotProton/releases/download/ --out out/feed
python3 -I release/feed.py bridge-manifest --serial N --out out/feed/manifest/bridge-manifest.json \
    out/feed/bridge-dormison-b1-2.entry.json
# сигнатуры: из signatures/manifest.json
python3 -I release/feed.py signatures --manifest signatures/manifest.json --dir signatures/macos.arm64 \
    --feed https://github.com/Ruslan-Ukraina/NotProton/releases/download/ --serial N --out out/feed
# подпись
swift release/sign.swift ~/notproton-release.key out/feed/manifest/*.json out/feed/bridge-*/*.tar.xz
```

Затем загрузи файлы в релизы с соответствующими тегами (`gh release upload <тег> <файлы> --clobber`).
Порядок важен: сначала артефакты, потом манифесты — иначе приложение увидит в манифесте мост, которого ещё нет.

## 4. Новый билд Steam

1. Проверить базы против клиента этого билда:
   - пакеты Valve по манифесту `steam_client[_publicbeta]_osx`, sha256 из него;
   - `HOME=<дерево> out/anchorcheck`.
2. Добавить в `signatures/manifest.json` строку `{"build": N, "database": "<база>.json"}` или новую базу.
3. `serial` + 1, опубликовать (п. 3).

Как это делалось вручную для беты 1791249696 — PROGRESS, 7 октября. Автоматизация — BACKLOG 22 (Фаза 6).

## Тестовый фид (Фаза 5)

`scratch/testfeed/` (не в git):
- тестовый ключ `test-release.key`, публичный `dXwoMYHG7v/BEEHtb/ifHpQrAz397JPWlea0Np7rVWk=`;
- фид `feed/`;
- готовый serial 2 сигнатур в `pending/`.

Сборка для ручной проверки: `make app NP_RELEASE_FEED=file://$PWD/scratch/testfeed/feed/ NP_RELEASE_KEY=<тестовый публичный>`.
Тестовый ключ **никогда** не попадает в релизную сборку (RISKS R50).
