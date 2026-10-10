# RELEASING — ключи, CI и выпуск Lullaby

Фаза 6. Приватный репозиторий `Ruslan-Ukraina/Lullaby`, ветка `main` (она же по умолчанию). Сверено с кодом 10.10.2026 (`PHASE6_PLAN.md`).
**Боевые ключи я не создавал и не видел.** Их создаёшь ты, один раз — раздел 1.

## Что подписывается и где лежит

Два ключа Ed25519, оба создаются одним скриптом `release/keygen.swift`:

| Ключ | Чем подписывает | Кто проверяет |
|---|---|---|
| **ключ релизов Lullaby** | `bridge-manifest.json`, `signatures-manifest.json`, тарболы мостов (`.sig` = base64 подписи над байтами файла) | Lullaby.app: `LBReleasePublicKey` в Info.plist |
| **ключ Sparkle** | архив приложения и сам appcast (подпись внутри XML) | Sparkle в Lullaby.app: `SUPublicEDKey` в Info.plist |

Файлы в релизах GitHub (`https://github.com/Ruslan-Ukraina/Lullaby/releases/download/<тег>/<файл>`):

| Тег релиза | Файлы | Кто публикует |
|---|---|---|
| `manifest` | `bridge-manifest.json` + `.sig`, `signatures-manifest.json` + `.sig`, `appcast.xml` | все три workflow |
| `bridge-<движок>-<rev>` | `bridge-…tar.xz` + `.sig`: lsteamclient, `steam.exe` (без отладочной информации, O1), B1-пара `ntdll.dll`, исправления движка; `bridge-…-debug.tar.xz` — те же PE с отладкой (приложение его не качает) | `dormison-bridge` |
| `signatures` | `<билд>.json` — базы сигнатур (их sha256 — в подписанном манифесте) | `steam-signatures` |
| `vX.Y.Z[-pre.N]` | `Lullaby-X.Y.Z….zip` | `release` |

Порядок публикации всегда один: сначала файлы, потом манифест или appcast. Иначе приложение увидело бы в манифесте файл, которого ещё нет.
`serial` манифеста = больший из опубликованного и репозиторного + 1: приложение не принимает манифест старше уже виденного.

## Конфигурация публикации — `release/feed.json` (ROADMAP §3)

Все адреса — в одном файле, а не в коде:

```json
{
  "schema": 1,
  "repository": "Ruslan-Ukraina/Lullaby",
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
| `LB_STEAM_CHECK_HOURS` | 6 | как часто искать новый билд Steam; округляется вверх до кратного 6; `0` — только вручную |
| `LB_DORMISON_CHECK_HOURS` | 24 | как часто искать новый Dormison; округляется вверх до кратного 24; `0` — только вручную |
| `LB_CI_ON_PUSH` | (не задана = выкл.) | `true` — гонять `app.yml` на каждый push в `main` (PR и «Run workflow» — всегда) |

По расписанию сначала идёт короткая проверка на Linux (`release/ci-gate.sh`: есть ли билд Steam без базы или Dormison без моста), и только тогда — задача на macOS. Билд Steam с открытым issue и версия Dormison с любым issue (кандидат ждёт, сборка упала, вы отказались) не запускают macOS повторно. Сколько это стоит в минутах — `PHASE6_PLAN.md` «Минуты».

## Лицензии и раздача бинарников

Мы раздаём бинарники: приложение (GPL-3.0 — Lullaby, форк NotProton), мост и B1-`ntdll.dll` (изменённый Wine — LGPL-2.1+; lsteamclient — Steamworks SDK License; `steam.exe`-шим — BSD-3). GPL и LGPL обязывают дать каждому получателю бинарника исходники, из которых он собран (для B1 — Dormison того же коммита плюс наш патч `ntdll-patch/b1/…patch`; для моста — `lsteamclient/`, `steam-shim/`, `bridge/`).

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
6. **CI.** В публичном репозитории минуты стандартных раннеров бесплатны: вернуть расписания по умолчанию (`LB_STEAM_CHECK_HOURS=3`, `LB_DORMISON_CHECK_HOURS=24`). Self-hosted runner в публичном репозитории **отключить** — PR из форка может запустить чужой код (P6-14).

## Тестовые ключи и релизная сборка

- Тестовые ключи выводятся из публичной фразы (`release/testkeys.swift release|sparkle`). Их может пересоздать кто угодно, поэтому они ничего не доказывают — и не должны.
- Открытые половины перечислены в `release/test-public-keys.txt` и в приложении (`TestKeys`, `BuildKind.swift`). Там же — тестовый ключ Фазы 5 (`dXwoMYHG…`).
- **Релизная сборка** (`LB_BUILD_KIND=release`, её делает только workflow `release` по тегу `v*`):
  - `make app` останавливается до сборки, если ключ пустой, тестовый, оба ключа совпадают, фид не https или задан `LB_DEV=1` (`release/check-release.sh config`);
  - после сборки проверяет сам бандл: `NPBuildKind`, ключи в Info.plist, отсутствие строки `steam-windows-debug` в `notproton.dylib` (BACKLOG 20), автопроверку обновлений, подписанный appcast, подпись кода (`check-release.sh bundle`);
  - приложение при запуске само отказывается от тестового ключа: фид и Sparkle выключаются, в Status — «This release build carries a TEST key…»;
  - workflow дополнительно проверяет, что конфигурация «релиз + тестовый ключ» отвергается.
- **Тестовая сборка** (`LB_BUILD_KIND=test`, dry-run) принимает только тестовые ключи. Обычная `make app` — `dev`: Sparkle и фид выключены, пока не переданы ключи.
- **Нативные окна Steam** (отложены, W19) в релизной сборке не показываются в Status, пока выключены. Код и dylib не менялись, по умолчанию — выключено (`BuildKindTests.nativeWindowsOff`).

## Workflow

Все macOS-задачи работают на раннере `xcode-27` (arm64, macOS 27, Xcode 27.0, тот же mingw GCC 16.2.0, что у тебя; Rosetta и графическая сессия есть — проверено пробным прогоном). Публикующие workflow стоят в общей очереди `release-feed`, чтобы не перебить друг другу `serial`.

| Workflow | Когда | Что делает |
|---|---|---|
| `dormison-bridge.yml` | раз в сутки (`LB_DORMISON_CHECK_HOURS`); вручную | Подписанный `engine.json` Dormison → версия канала без моста (или вход `engine`, напр. `dormison-r5`: адрес и sha256 — из `engineRelease` записи моста) → mingw GCC ровно 16.2.0 (I4) → движок (подпись, sha256, каждый файл) → исходники Dormison того же коммита → `setup-wine-tree.sh`, `build-b1.sh --check-base` (непропатченный код совпадает с релизным инструкция в инструкцию), lsteamclient, `steam.exe` → `strip --strip-debug` (O1) → `test-b1.sh` в Wine: x86_64 и i386 OK, а релизный `ntdll.dll` обязан провалить тот же тест → тарбол, `bridge-manifest.json`, подписи → публикация и чтение обратно. Ошибка — issue. **По расписанию — только кандидат** (тестовые ключи, артефакт, issue «candidate … not published»); публикует «Run workflow» с `promote_run` = id проверенного run: те же байты подписываются боевым ключом, без пересборки |
| `steam-signatures.yml` | каждые 6 часов (`LB_STEAM_CHECK_HOURS`); вручную | Раз в сутки (05:23 UTC) Linux-ворота проверяют, что Valve отдаёт закреплённые пакеты (`release/valve-check.sh`, I5; пропажа — issue). Дальше: Манифесты Valve stable и publicbeta → новый билд → пакеты Valve (sha256 из манифеста Valve, подпись Valve `MXGJJ98X76` по каждому срезу, наличие x86_64 — BACKLOG 24) → `out/sigslice` режет базу из самой новой подходящей → `out/anchorcheck` только по новой базе обязан дать 0 → `signatures-manifest.json`, подпись → публикация. Не режется или нет x86_64 — issue |
| `release.yml` | тег `v*` | Версия из тега (база должна совпасть с `dylib/version.h`), CFBundleVersion = число коммитов → мост из опубликованного артефакта (sha256 из `bridge/bridge-manifest.json` + подпись) → `make app LB_BUILD_KIND=release` → проверки релиза → C-тесты и Swift-тесты (с `LB_REQUIRE_PAYLOAD=1`) → собранное приложение читает опубликованный фид (`--release check`) → zip, подпись Sparkle, appcast (старые записи сохраняются; пре-релиз — канал `beta`) → релиз GitHub, затем appcast; оба читаются обратно |
| `app.yml` (macOS), `lint.yml` (Linux) | PR, «Run workflow»; push в `main` без изменений только в документации — `lint` всегда, `app` при `LB_CI_ON_PUSH=true` | dylib, шим, помощники, C-тесты, Swift-тесты (без собранного payload часть пропускается), shellcheck |

**Dry-run** — тег `dryrun-bridge-*`, `dryrun-signatures-*`, `dryrun-app-*` (или «Run workflow» с галочкой `dry_run`):
- тестовые ключи, ничего не публикуется, issue не создаются (в итоге run написано, какое было бы открыто);
- всё, что было бы опубликовано, — артефакт run;
- `dormison-bridge` без нового движка пересобирает мост для движка бета-канала, чтобы прогнать весь путь;
- `release` берёт мост из последнего успешного run `dormison-bridge`.

**Без ключей** (секреты ещё не добавлены) запуски по расписанию заканчиваются уведомлением «keys are not set up yet», без ошибки.

## Мост в релизе

Сборка PE не воспроизводится побайтно: в `ntdll.dll` записано время сборки (`TimeDateStamp`, проверено на `scratch/ntdll-b1`). Поэтому мост собирает только `dormison-bridge` и публикует подписанным. `release` встраивает опубликованный мост, сверяя sha256 с `bridge/bridge-manifest.json` и подпись (`make app BRIDGE_FEED_DIR=…`, `feed.py stage-bridge --from-feed`). Мост без `url`/`sha256` в репозиторном манифесте релиз не соберёт — так и задумано (DECISIONS P6-2).
Локальная `make app` по-прежнему берёт мост из твоего дерева wine.

## 1. Ключи — пошагово (делаешь ты, один раз, ~15 минут)

Закрытые ключи никому не показывай, мне тоже. Ни одна команда ниже не печатает закрытый ключ на экран.
Нужно: Терминал, флешка (любая), менеджер паролей, если есть (Bitwarden, 1Password, «Пароли» Apple).

**1. Терминал и проект** (Программы → Утилиты → Терминал):
```sh
cd ~/Projects/NotProton
```

**2. Папка для ключей**, доступная только тебе:
```sh
mkdir -p ~/Lullaby-keys && chmod 700 ~/Lullaby-keys
```

**3. Ключ релизов Lullaby** (подписывает мосты и базы сигнатур):
```sh
swift release/keygen.swift ~/Lullaby-keys/lullaby-release.key
```
Увидишь две строки: `private key written to …` и `public key  …` (44 символа, в конце `=`). Это **открытый** ключ — его показывать можно.

**4. Ключ Sparkle** (подписывает обновления самого приложения):
```sh
swift release/keygen.swift ~/Lullaby-keys/lullaby-sparkle.key
```
Открытый ключ должен отличаться от ключа релизов.

**5. Резервная копия вне Mac — обязательно, две копии в разных местах.**
Если потерять ключ Sparkle, уже установленные Lullaby больше не смогут обновиться сами — только ручная переустановка.

- **Копия А — менеджер паролей.** Создай запись «Lullaby release keys». Для каждого ключа:
  ```sh
  pbcopy < ~/Lullaby-keys/lullaby-release.key
  ```
  вставь (⌘V) в поле-пароль «release private key»; потом
  ```sh
  pbcopy < ~/Lullaby-keys/lullaby-sparkle.key
  ```
  — в поле «sparkle private key». В заметку записи впиши оба открытых ключа (шаги 3–4). Очисти буфер: `pbcopy < /dev/null`.
  Нет менеджера паролей — вместо него перепиши обе строки от руки на бумагу (44 символа каждая) и убери её туда, где хранишь документы.
- **Копия Б — флешка.** Вставь флешку; в Finder правый клик по ней → «Зашифровать "…"» → придумай пароль (запиши его в менеджер паролей) — дождись окончания. Перетащи папку `Lullaby-keys` (`open ~` в Терминале покажет её) на флешку. Извлеки флешку и храни отдельно от Mac.
- Проверка копии: открой файл с флешки в TextEdit — одна строка, 44 символа. Закрой, не сохраняя.

**6. Закрытые ключи → GitHub Secrets** (прямо из файла, без буфера и без экрана):
```sh
gh secret set LB_RELEASE_PRIVATE_KEY -R Ruslan-Ukraina/Lullaby < ~/Lullaby-keys/lullaby-release.key
gh secret set SPARKLE_PRIVATE_KEY   -R Ruslan-Ukraina/Lullaby < ~/Lullaby-keys/lullaby-sparkle.key
```
Каждая команда отвечает `✓ Set Actions secret …`.
(Через сайт то же самое: https://github.com/Ruslan-Ukraina/Lullaby/settings/secrets/actions → **New repository secret**.)

**7. Открытые ключи → GitHub Variables:**
```sh
gh variable set LB_RELEASE_PUBLIC_KEY -R Ruslan-Ukraina/Lullaby --body "$(swift release/sign.swift ~/Lullaby-keys/lullaby-release.key --public)"
gh variable set SPARKLE_PUBLIC_KEY   -R Ruslan-Ukraina/Lullaby --body "$(swift release/sign.swift ~/Lullaby-keys/lullaby-sparkle.key --public)"
```
Больше открытые ключи никуда вставлять не нужно: `release.yml` сам пишет их в Info.plist (`LBReleasePublicKey`, `SUPublicEDKey`), а CI перед каждой подписью сверяет, что закрытый ключ из Secrets соответствует открытому и не тестовый.

**8. Ключи на Mac** — по желанию. CI подписывает сам; на Mac они нужны только для ручной публикации (§4). Если копии А и Б проверены, папку `~/Lullaby-keys` можно удалить (Finder → в Корзину → очистить Корзину).

**9.** Напиши мне **«ключи готовы»**. Я проверю только имена (`gh secret list`, `gh variable list`) и что открытые ключи не тестовые (`release/test-public-keys.txt`).

## 1а. Токен для приватных релизов (делаешь ты, ~5 минут, Фаза 6 шаг 6)

Пока релизы приватные, Lullaby скачивает мост, сигнатуры и обновления только с токеном **на чтение**.

1. https://github.com/settings/personal-access-tokens/new (GitHub → Settings → Developer settings → Personal access tokens → **Fine-grained tokens** → Generate new token).
2. **Token name:** `Lullaby updates`. **Expiration:** 1 год (запиши дату в календарь — после неё Update напишет «токен не подходит»).
3. **Repository access:** Only select repositories → `Ruslan-Ukraina/Lullaby`.
4. **Permissions → Repository permissions → Contents: Read-only.** Больше ничего не включай (Metadata: Read-only GitHub ставит сам).
5. **Generate token** → скопируй (`github_pat_…`) → Lullaby → ⚙︎ → «Токен доступу…» → вставь → Зберегти. Токен хранится в Keychain, в файлы и журналы не попадает.
6. Больше никуда его не вставляй. Потерял — отзови на той же странице и создай новый.

## 2. После «ключи готовы» — боевой прогон (делаю я)

1. **Мост r5 без отладки уже проверен тобой** (PEAK, RE9 — `SPIKE_TEST.md` §19) как кандидат из пробного run `dormison-bridge` (`engine` = `dormison-r5`, тестовый ключ).
2. `dormison-bridge` → «Run workflow»: `promote_run` = id того run, `dry_run` = выкл. → публикуются `bridge-dormison-r5-2` (те же байты, подпись боевым ключом), `bridge-dormison-r5-2-debug.tar.xz` и `bridge-manifest.json` (serial 2). Номер 1 занят тестовым мостом, который стоит у тебя; id никогда не повторяется.
3. Запись моста — в `bridge/bridge-manifest.json` репозитория (вместо тестовой r5-1): релиз встраивает именно её.
4. `steam-signatures` → «Run workflow», `dry_run` = выкл. → базы для текущих stable и beta и `signatures-manifest.json` (serial 2).
5. `release/feed.json` → `access: private`; тег `v1.1.0-pre.1` → `release` → приватный пре-релиз и `appcast.xml` (архив — по API-адресу, Sparkle берёт его с токеном).
6. По твоему «можно»: `/Applications/Lullaby.app` → `scratch/applications-backup/`, ставлю pre.1; ты вводишь токен (§1а); тег `v1.1.0-pre.2`; ты включаешь «Pre-release versions» и жмёшь Update (SPIKE_TEST §13).

## 3. Обычный выпуск

- **Новая версия приложения:** поменять `LULLABY_VERSION` в `dylib/version.h` (например, `1.1.0`), коммит, тег:
  ```sh
  git tag -a v1.1.0 -m "Что нового — это текст в окне обновления"
  git push origin v1.1.0
  ```
  Пре-релиз — тег `v1.1.0-pre.N`; его получают только приложения с «Pre-release versions».
- **Новый Dormison** — `dormison-bridge` на следующий день сам соберёт **кандидата** (не публикует) и откроет issue «Steam bridge candidate for … is built, not published». Дальше: проверка игр владельцем → «Run workflow» с `promote_run`. Ошибка сборки — issue «Steam bridge for … did not build». Движок по умолчанию у игроков не меняется, пока мост не опубликован.
- **Новый билд Steam** — ничего: `steam-signatures` в течение 6 часов нарежет и опубликует базу. Не вышло — issue «Steam … build N needs a signature database», Steam остаётся на старом билде (гейт P5-4).
- **Встроить новую базу или мост в приложение** (необязательно, приложение и так скачает их из фида): скопировать базу в `signatures/macos.arm64` и строку в `signatures/manifest.json`, запись моста — в `bridge/bridge-manifest.json`.

## 4. Ручная публикация (запасной путь, без CI)

```sh
# подпись любых файлов ключом релизов
swift release/sign.swift ~/Lullaby-keys/lullaby-release.key <файлы>
# проверка
swiftc -O -o /tmp/verify engine/verify-ed25519.swift
/tmp/verify <открытый ключ> <файл> <файл>.sig
```
Инструменты: `release/feed.py` (сборка манифестов, см. `--help`), `release/steam-client.sh` (клиент Steam канала), `out/sigslice` (`make sigslice`), `release/steam-signatures.sh` (весь путь сигнатур).

## Тестовый фид Фазы 5

`scratch/testfeed/` (не в git), ключ `dXwoMYHG…`. Установленный сейчас `/Applications/Lullaby.app` — dev-сборка `7e9853e` с тестовым мостом `bridge-dormison-r5-1`; после боевого прогона его заменит релиз `v1.1.0-pre.1` (BACKLOG 25). Релизная сборка этот ключ не принимает.
