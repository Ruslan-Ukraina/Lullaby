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

## Конфигурация публикации — `release/feed.json` (ROADMAP §3)

Все адреса — в одном файле, а не в коде:

```json
{
  "schema": 1,
  "repository": "Ruslan-Ukraina/NotProton",
  "access": "public",
  "manifestTag": "manifest",
  "signaturesTag": "signatures",
  "appcast": "appcast.xml",
  "engineManifest": "https://github.com/kageroumado/dormison/releases/download/manifest/engine.json"
}
```

- Из него выводятся адрес фида (`https://github.com/<repository>/releases/download/`) и appcast (`<фид><manifestTag>/<appcast>`).
- `make app` пишет значения в Info.plist (`NPReleaseFeedURL`, `NPReleaseAccess`, `NPReleaseRepository`, `NPReleaseManifestTag`, `NPEngineManifestURL`, `SUFeedURL`); workflow читают тот же файл (`python3 -I release/feed.py config <ключ>`).
- Workflow с публикацией сверяют `repository` с репозиторием, где запущены (`gh-publish.sh check-repo`): иначе приложение получило бы адреса, которые отвергает.
- `engineManifest` — по умолчанию манифест Dormison. Другой адрес допускается только как релиз GitHub по https, и подпись Dormison всё равно обязательна.
- Тест `ReleaseAccessTests.configAgreement` следит, чтобы файл и Info.plist в репозитории совпадали.

### Публичный и приватный доступ

| `access` | Как скачивает приложение | Как скачивает CI |
|---|---|---|
| `public` (сейчас) | https по адресам `…/releases/download/<тег>/<файл>`, как в манифестах | `gh release download` с `GITHUB_TOKEN` |
| `private` (Фаза 6, в приватном репозитории) | те же адреса — как имена: `GET /repos/<repo>/releases/tags/<тег>` → id ассета → `GET /repos/<repo>/releases/assets/<id>` с `Accept: application/octet-stream` и токеном. При переходе на хранилище GitHub заголовок `Authorization` снимается | так же |

- **Токен** — read-only (fine-grained, доступ только на чтение содержимого репозитория), хранится в Keychain пользователя (`ReleaseToken`). Ввод был в старом окне Status (удалено в Фазе 8, P8-14); новый ввод в ⚙︎ — Фаза 6, шаг 2а (`PHASE6_PLAN.md`). В файлы, лог и Info.plist токен не попадает.
- **Sparkle** в приватном режиме: токен идёт в `SPUUpdater.httpHeaders` вместе с `Accept: application/octet-stream`; адрес appcast перед каждой проверкой разрешается через API (у каждого выпуска новый id ассета). `release.yml` в приватном режиме записывает в appcast API-адрес архива и подписывает appcast заново.
- Подписи и проверки (Ed25519, sha256, `serial`) в обоих режимах одинаковые: токен даёт доступ, а не доверие.
- Переключение в приватный режим — Фаза 6, шаг 2а (Фаза 9 перенесла репозиторий, `PHASE9.md`): поменять `repository` и `access` в `feed.json`, выпустить новую версию приложения.

### Расписания CI — параметр

Переменные репозитория (Settings → Secrets and variables → Actions → Variables):

| Переменная | По умолчанию | Что значит |
|---|---|---|
| `NP_STEAM_CHECK_HOURS` | 3 | как часто искать новый билд Steam; округляется вверх до кратного 3; `0` — только вручную |
| `NP_DORMISON_CHECK_HOURS` | 24 | как часто искать новый Dormison; округляется вверх до кратного 24; `0` — только вручную |
| `NP_CI_ON_PUSH` | (не задана = вкл.) | `false` — не гонять `app.yml` на каждый push (PR и «Run workflow» остаются) |

По расписанию сначала идёт короткая проверка на Linux (`release/ci-gate.sh`: есть ли билд Steam без базы или Dormison без моста), и только тогда — задача на macOS. Сколько это стоит в минутах — DECISIONS P6-13.

## Лицензии и раздача бинарников

Мы раздаём бинарники: приложение (GPL-3.0 — NotProton), мост и B1-`ntdll.dll` (изменённый Wine — LGPL-2.1+; lsteamclient — Steamworks SDK License; `steam.exe`-шим — BSD-3). GPL и LGPL обязывают дать каждому получателю бинарника исходники, из которых он собран (для B1 — Dormison того же коммита плюс наш патч `ntdll-patch/b1/…patch`; для моста — `lsteamclient/`, `steam-shim/`, `bridge/`).

- **Пока проект открытый** (сейчас): исходники лежат в этом же репозитории, рядом с релизами; каждый артефакт указывает коммит (`engineCommit`, тег релиза). Этого достаточно.
- **Пока проект закрытый** (с Фазы 9): артефакты тоже закрытые — только по токену, тем же людям, у кого есть доступ к исходникам. Публичных ссылок на бинарники быть не должно.
- **При открытии проекта** — открыть исходники вместе с артефактами (весь репозиторий или как минимум всё, из чего собраны опубликованные бинарники, с тем же коммитом), иначе публичная раздача нарушит GPL/LGPL.
- D3DMetal (Apple) не распространяется ни в каком виде (ROADMAP §2).

### При будущем открытии проекта — по шагам

Цель: каждый, кто может скачать бинарник, может скачать и исходники того же коммита (GPL-3.0 для приложения, LGPL-2.1+ для изменённого Wine).

1. **Исходники.** Сделать приватный репозиторий публичным (Settings → General → Danger Zone → Change visibility) **или** опубликовать отдельный публичный репозиторий со всей историей тех коммитов, из которых собраны выпущенные бинарники. Перед этим — повторить проверку истории на личные данные (`PHASE9.md`, раздел «Проверка истории»).
2. **Что обязательно должно быть открыто вместе с бинарниками:**
   - приложение: весь этот репозиторий того коммита, на котором тег `v…` (GPL-3.0);
   - мост и B1-`ntdll.dll`: `lsteamclient/`, `steam-shim/`, `bridge/`, `ntdll-patch/b1/…patch`, исправления движка (`engineFiles`, `build-fixes.sh`), а для Wine — **исходники Dormison того же `engineCommit`** (наш форк `~/Projects/dormison` с патчами или ссылка на публичный коммит апстрима + наши патчи). Ссылки на чужой репозиторий мало, если он может исчезнуть: лучше положить архив исходников рядом с релизом моста (`INDEPENDENCE.md`);
   - `NOTICE` и тексты лицензий (GPL-3, LGPL-2.1, MIT Sevoflurane/Highball, BSD-3 steam-shim, Steamworks SDK License для lsteamclient).
3. **Артефакты.** `release/feed.json`: `access` → `public`, `repository` → публичный; выпустить новую версию приложения (старые приватные сборки без токена новые адреса не увидят — им одна ручная установка или выпуск, который ещё понимает оба режима).
4. **Старые приватные релизы.** Если сделать публичным тот же репозиторий, его релизы станут публичными сразу: проверить, что к каждому `bridge-*`, `signatures`, `v*` есть исходники по п. 2.
5. **Нельзя публиковать никогда:** D3DMetal/GPTK (Apple), закрытые ключи, токены, снимки экрана с личными данными.
6. **CI.** В публичном репозитории минуты стандартных раннеров бесплатны: вернуть расписания по умолчанию (`NP_STEAM_CHECK_HOURS=3`, `NP_DORMISON_CHECK_HOURS=24`). Self-hosted runner в публичном репозитории **отключить** — PR из форка может запустить чужой код (P6-14).

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
| `dormison-bridge.yml` | раз в сутки (`NP_DORMISON_CHECK_HOURS`); вручную | Подписанный `engine.json` Dormison → версия канала без моста → движок (подпись, sha256, каждый файл) → исходники Dormison того же коммита → `setup-wine-tree.sh`, `build-b1.sh --check-base` (непропатченный код совпадает с релизным инструкция в инструкцию), lsteamclient, `steam.exe` → `test-b1.sh` в Wine: x86_64 и i386 OK, а релизный `ntdll.dll` обязан провалить тот же тест → тарбол, `bridge-manifest.json`, подписи → публикация и чтение обратно. Ошибка — issue |
| `steam-signatures.yml` | каждые 3 часа (`NP_STEAM_CHECK_HOURS`); вручную | Манифесты Valve stable и publicbeta → новый билд → пакеты Valve (sha256 из манифеста Valve, подпись Valve `MXGJJ98X76` по каждому срезу, наличие x86_64 — BACKLOG 24) → `out/sigslice` режет базу из самой новой подходящей → `out/anchorcheck` только по новой базе обязан дать 0 → `signatures-manifest.json`, подпись → публикация. Не режется или нет x86_64 — issue |
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
