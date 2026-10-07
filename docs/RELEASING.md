# RELEASING — ключи, CI и выпуск NotProton

Фаза 6. CI готов и прогнан в режиме dry-run с тестовыми ключами (PROGRESS, 7 октября).
**Боевые ключи я не создавал и не видел.** Их создаёшь ты, один раз — раздел 1.

## Что подписывается и где лежит

Два ключа Ed25519, оба создаются одним скриптом `release/keygen.swift`:

| Ключ | Чем подписывает | Кто проверяет |
|---|---|---|
| **ключ релизов NotProton** | `bridge-manifest.json`, `signatures-manifest.json`, тарболы мостов (`.sig` = base64 подписи над байтами файла) | NotProton.app: `NPReleasePublicKey` в Info.plist |
| **ключ Sparkle** | архив приложения и сам appcast (подпись внутри XML) | Sparkle в NotProton.app: `SUPublicEDKey` в Info.plist |

Файлы в релизах GitHub (`https://github.com/Ruslan-Ukraina/NotProton/releases/download/<тег>/<файл>`):

| Тег релиза | Файлы | Кто публикует |
|---|---|---|
| `manifest` | `bridge-manifest.json` + `.sig`, `signatures-manifest.json` + `.sig`, `appcast.xml` | все три workflow |
| `bridge-<движок>-<rev>` | `bridge-…tar.xz` + `.sig`: lsteamclient, `steam.exe`, B1-пара `ntdll.dll` | `dormison-bridge` |
| `signatures` | `<билд>.json` — базы сигнатур (их sha256 — в подписанном манифесте) | `steam-signatures` |
| `vX.Y.Z[-pre.N]` | `NotProton-X.Y.Z….zip` | `release` |

Порядок публикации всегда один: сначала файлы, потом манифест или appcast. Иначе приложение увидело бы в манифесте файл, которого ещё нет.
`serial` манифеста = больший из опубликованного и репозиторного + 1: приложение не принимает манифест старше уже виденного.

## Тестовые ключи и релизная сборка

- Тестовые ключи выводятся из публичной фразы (`release/testkeys.swift release|sparkle`). Их может пересоздать кто угодно, поэтому они ничего не доказывают — и не должны.
- Открытые половины перечислены в `release/test-public-keys.txt` и в приложении (`TestKeys`, `BuildKind.swift`). Там же — тестовый ключ Фазы 5 (`dXwoMYHG…`).
- **Релизная сборка** (`NP_BUILD_KIND=release`, её делает только workflow `release` по тегу `v*`):
  - `make app` останавливается до сборки, если ключ пустой, тестовый, оба ключа совпадают, фид не https или задан `NP_DEV=1` (`release/check-release.sh config`);
  - после сборки проверяет сам бандл: `NPBuildKind`, ключи в Info.plist, отсутствие строки `steam-windows-debug` в `notproton.dylib` (BACKLOG 20), автопроверку обновлений, подписанный appcast, подпись кода (`check-release.sh bundle`);
  - приложение при запуске само отказывается от тестового ключа: фид и Sparkle выключаются, в Status — «This release build carries a TEST key…»;
  - workflow дополнительно проверяет, что конфигурация «релиз + тестовый ключ» отвергается.
- **Тестовая сборка** (`NP_BUILD_KIND=test`, dry-run) принимает только тестовые ключи. Обычная `make app` — `dev`: Sparkle и фид выключены, пока не переданы ключи.
- **Нативные окна Steam** (отложены, W19) в релизной сборке не показываются в Status, пока выключены. Код и dylib не менялись, по умолчанию — выключено (`BuildKindTests.nativeWindowsOff`).

## Workflow

Все три работают на раннере `xcode-27` (arm64, macOS 27, Xcode 27.0, тот же mingw GCC 16.2.0, что у тебя; Rosetta и графическая сессия есть — проверено пробным прогоном). Публикующие workflow стоят в общей очереди `release-feed`, чтобы не перебить друг другу `serial`.

| Workflow | Когда | Что делает |
|---|---|---|
| `dormison-bridge.yml` | каждый день 05:41 UTC; вручную | Подписанный `engine.json` Dormison → версия канала без моста → движок (подпись, sha256, каждый файл) → исходники Dormison того же коммита → `setup-wine-tree.sh`, `build-b1.sh --check-base` (непропатченный код совпадает с релизным инструкция в инструкцию), lsteamclient, `steam.exe` → `test-b1.sh` в Wine: x86_64 и i386 OK, а релизный `ntdll.dll` обязан провалить тот же тест → тарбол, `bridge-manifest.json`, подписи → публикация и чтение обратно. Ошибка — issue |
| `steam-signatures.yml` | каждые 3 часа; вручную | Манифесты Valve stable и publicbeta → новый билд → пакеты Valve (sha256 из манифеста Valve, подпись Valve `MXGJJ98X76` по каждому срезу, наличие x86_64 — BACKLOG 24) → `out/sigslice` режет базу из самой новой подходящей → `out/anchorcheck` только по новой базе обязан дать 0 → `signatures-manifest.json`, подпись → публикация. Не режется или нет x86_64 — issue |
| `release.yml` | тег `v*` | Версия из тега (база должна совпасть с `dylib/version.h`), CFBundleVersion = число коммитов → мост из опубликованного артефакта (sha256 из `bridge/bridge-manifest.json` + подпись) → `make app NP_BUILD_KIND=release` → проверки релиза → C-тесты и Swift-тесты (с `NP_REQUIRE_PAYLOAD=1`) → собранное приложение читает опубликованный фид (`--release check`) → zip, подпись Sparkle, appcast (старые записи сохраняются; пре-релиз — канал `beta`) → релиз GitHub, затем appcast; оба читаются обратно |
| `app.yml`, `lint.yml` | push в `dormison`, PR | dylib, шим, помощники, C-тесты, Swift-тесты (без собранного payload часть пропускается), shellcheck |

**Dry-run** — тег `dryrun-bridge-*`, `dryrun-signatures-*`, `dryrun-app-*` (или «Run workflow» с галочкой `dry_run`, когда ветка по умолчанию — `dormison`):
- тестовые ключи, ничего не публикуется, issue не создаются (в итоге run написано, какое было бы открыто);
- всё, что было бы опубликовано, — артефакт run;
- `dormison-bridge` без нового движка пересобирает мост для движка бета-канала, чтобы прогнать весь путь;
- `release` берёт мост из последнего успешного run `dormison-bridge`.

**Без ключей** (секреты ещё не добавлены) запуски по расписанию заканчиваются уведомлением «keys are not set up yet», без ошибки.

## Мост в релизе

Сборка PE не воспроизводится побайтно: в `ntdll.dll` записано время сборки (`TimeDateStamp`, проверено на `scratch/ntdll-b1`). Поэтому мост собирает только `dormison-bridge` и публикует подписанным. `release` встраивает опубликованный мост, сверяя sha256 с `bridge/bridge-manifest.json` и подпись (`make app BRIDGE_FEED_DIR=…`, `feed.py stage-bridge --from-feed`). Мост без `url`/`sha256` в репозиторном манифесте релиз не соберёт — так и задумано (DECISIONS P6-2).
Локальная `make app` по-прежнему берёт мост из твоего дерева wine.

## 1. Ключи — пошагово (делаешь ты, один раз)

Нужно ~10 минут. Закрытые ключи никому не показывай, мне тоже.

1. **Открой Терминал** (Программы → Утилиты → Терминал) и перейди в проект:
   ```sh
   cd ~/Projects/NotProton
   ```
2. **Папка для ключей**, доступная только тебе:
   ```sh
   mkdir -p ~/NotProton-keys && chmod 700 ~/NotProton-keys
   ```
3. **Ключ релизов NotProton:**
   ```sh
   swift release/keygen.swift ~/NotProton-keys/notproton-release.key
   ```
   - Ожидаемый результат — две строки: `private key written to …` и `public key  <44 символа, кончается на =>`.
   - Строку после `public key` (открытый ключ) сохрани в заметку — это **открытый ключ релизов**.
4. **Ключ Sparkle** — та же команда, другой файл:
   ```sh
   swift release/keygen.swift ~/NotProton-keys/notproton-sparkle.key
   ```
   - Строка после `public key` — **открытый ключ Sparkle**. Он должен отличаться от ключа релизов.
   - Sparkle читает ключ в этом же формате — проверено (`sign_update`, PROGRESS).
5. **Резервная копия** (без неё новые мосты и сигнатуры придётся выпускать новой сборкой приложения с новым ключом, R49):
   - открой `~/NotProton-keys` в Finder (`open ~/NotProton-keys`);
   - перетащи оба файла `.key` в менеджер паролей (1Password, Bitwarden и т. п. — как вложения к записи «NotProton keys») **или** в зашифрованный образ диска (Дисковая утилита → Файл → Новый образ → Образ из папки, шифрование AES-256);
   - вторая копия — на флешку, которая хранится отдельно от Mac;
   - открытый ключ всегда можно получить снова: `swift release/sign.swift ~/NotProton-keys/<файл>.key --public`.
6. **Секреты в GitHub** (закрытые ключи). Открой https://github.com/Ruslan-Ukraina/NotProton/settings/secrets/actions → вкладка **Secrets** → **New repository secret**:
   - скопируй ключ релизов в буфер, не показывая его на экране:
     ```sh
     pbcopy < ~/NotProton-keys/notproton-release.key
     ```
     Name: `NP_RELEASE_PRIVATE_KEY`, Secret: вставь (⌘V) → **Add secret**;
   - то же для Sparkle:
     ```sh
     pbcopy < ~/NotProton-keys/notproton-sparkle.key
     ```
     Name: `SPARKLE_PRIVATE_KEY` → вставь → **Add secret**;
   - очисти буфер: `pbcopy < /dev/null`.
7. **Открытые ключи** — там же, вкладка **Variables** → **New repository variable**:
   - Name `NP_RELEASE_PUBLIC_KEY`, Value — открытый ключ релизов (шаг 3);
   - Name `SPARKLE_PUBLIC_KEY`, Value — открытый ключ Sparkle (шаг 4).

   Больше открытые ключи никуда вставлять не нужно: `release.yml` сам записывает их в Info.plist (`NPReleasePublicKey`, `SUPublicEDKey`), а CI перед каждой подписью сверяет, что закрытый ключ из Secrets соответствует открытому из Variables и не тестовый.
8. **Ветка по умолчанию** — `dormison`: https://github.com/Ruslan-Ukraina/NotProton/settings → General → Default branch → значок ⇄ → `dormison` → Update → подтвердить. Без этого GitHub не запускает workflow по расписанию и не даёт кнопку «Run workflow».
9. Напиши мне **«ключи готовы»**.

## 2. После «ключи готовы» — боевой прогон (делаю я)

1. `dormison-bridge` вручную, `dry_run` = выкл., `rebuild` = вкл., `rev` = 3 → публикуется `bridge-dormison-b1-3` и `bridge-manifest.json` (serial 2). Номер 2 занят мостом тестового фида Фазы 5 (он мог остаться в `notproton/bridges`), а id никогда не повторяется. Запись моста — в `bridge/bridge-manifest.json` репозитория: релиз встраивает именно его.
2. `steam-signatures` вручную, `dry_run` = выкл. → база беты 1791249696 и `signatures-manifest.json` (serial 2).
3. Тег `v1.1.0-pre.1` → `release` → пре-релиз на GitHub и `appcast.xml`. Ставлю его в `/Applications` (старое приложение — в резервную копию), Status показывает «NotProton 1.1.0-pre.1», фид и Sparkle включены.
4. Тег `v1.1.0-pre.2` → установленный NotProton с включённым «Pre-release versions» находит обновление через Sparkle и ставит его. Это и есть проверка обновления; шаги для тебя — SPIKE_TEST §13.

## 3. Обычный выпуск

- **Новая версия приложения:** поменять `NOTPROTON_VERSION` в `dylib/version.h` (например, `1.1.0`), коммит, тег:
  ```sh
  git tag -a v1.1.0 -m "Что нового — это текст в окне обновления"
  git push origin v1.1.0
  ```
  Пре-релиз — тег `v1.1.0-pre.N`; его получают только приложения с «Pre-release versions».
- **Новый Dormison** — ничего: `dormison-bridge` сам соберёт мост на следующий день. Ошибка — issue «Steam bridge for … did not build».
- **Новый билд Steam** — ничего: `steam-signatures` в течение 3 часов нарежет и опубликует базу. Не вышло — issue «Steam … build N needs a signature database», Steam остаётся на старом билде (гейт P5-4).
- **Встроить новую базу или мост в приложение** (необязательно, приложение и так скачает их из фида): скопировать базу в `signatures/macos.arm64` и строку в `signatures/manifest.json`, запись моста — в `bridge/bridge-manifest.json`.

## 4. Ручная публикация (запасной путь, без CI)

```sh
# подпись любых файлов ключом релизов
swift release/sign.swift ~/NotProton-keys/notproton-release.key <файлы>
# проверка
swiftc -O -o /tmp/verify engine/verify-ed25519.swift
/tmp/verify <открытый ключ> <файл> <файл>.sig
```
Инструменты: `release/feed.py` (сборка манифестов, см. `--help`), `release/steam-client.sh` (клиент Steam канала), `out/sigslice` (`make sigslice`), `release/steam-signatures.sh` (весь путь сигнатур).

## Тестовый фид Фазы 5

`scratch/testfeed/` (не в git), ключ `dXwoMYHG…`. Установленный сейчас `/Applications/NotProton.app` собран с ним (P5-7); после боевого прогона его заменит релиз `v1.1.0-pre.1` (BACKLOG 25). Релизная сборка этот ключ не принимает.
