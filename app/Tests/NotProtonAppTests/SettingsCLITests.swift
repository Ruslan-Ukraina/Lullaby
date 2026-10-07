// notproton-settings as its callers use it: the Steam panel's requests, Dormison's
// View menu (`app config`, §5.3) and compat_run.sh's `launch`.

import Foundation
import Testing
@testable import NotProtonSettings

@Suite("Settings CLI")
struct SettingsCLITests {

    func object(_ text: String) throws -> [String: JSONValue] {
        try #require(try JSONValue.parse(text).object)
    }

    @Test("the panel reads the catalog and a game's state, then sets and resets")
    func panelRequests() throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanUp() }
        try fixture.install(3527290, name: "PEAK", dir: "PEAK", exes: ["PEAK.exe", "UnityCrashHandler64.exe"])
        try FileManager.default.createDirectory(at: fixture.prefix(3527290), withIntermediateDirectories: true)
        let cli = SettingsCLI(service: fixture.service)

        let catalog = try object(cli.panel(#"{"op":"catalog"}"#).text)
        #expect(catalog["ok"] == .bool(true))
        let settings = try #require(catalog["catalog"]?.object?["settings"]?.array)
        #expect(settings.count == SettingID.allCases.count)
        #expect(settings.compactMap { $0.object?["quick"]?.number }.sorted() == [1, 2, 3, 4, 5])

        // A game whose files are not installed yet has nothing to record.
        var answer = try object(cli.panel(#"{"op":"state","app":3527291}"#).text)
        var state = try #require(answer["state"]?.object)
        #expect(state["status"] == .string("firstLaunch"))
        #expect(state["exes"] == .array([]))

        // The page of an installed game records its executables at once.
        answer = try object(cli.panel(#"{"op":"state","app":3527290}"#).text)
        state = try #require(answer["state"]?.object)
        #expect(state["status"] == .string("nextLaunch"))
        #expect(state["exes"] == .array([.string("peak.exe")]))
        #expect(fixture.read(".sevo/apps/peak.exe.env", in: 3527290)?.hasPrefix(ConfigMaterializer.header) == true)
        #expect(state["name"] == .string("PEAK"))
        #expect(state["engine"] == .string("dormison-b1"))
        #expect(state["values"]?.object?["renderer"]?.object?["inheritedLabel"]?.object?["en"] == .string("DXMT"))

        answer = try object(cli.panel(#"{"op":"set","app":3527290,"id":"fpsLimit","value":60}"#).text)
        state = try #require(answer["state"]?.object)
        #expect(state["status"] == .string("nextLaunch"))
        #expect(state["exes"] == .array([.string("peak.exe")]))
        let limit = try #require(state["values"]?.object?["fpsLimit"]?.object)
        #expect(limit["own"] == .number(60))
        #expect(limit["inherited"] == .number(0))
        #expect(limit["effective"] == .number(60))
        #expect(fixture.read(".sevo/apps/peak.exe.env", in: 3527290)?.contains("DXVK_FRAME_RATE=60") == true)

        answer = try object(cli.panel(#"{"op":"set","app":3527290,"id":"fpsLimit","value":null}"#).text)
        #expect(answer["state"]?.object?["values"]?.object?["fpsLimit"]?.object?["own"] == .null)

        answer = try object(cli.panel(#"{"op":"set","app":3527290,"id":"fps","value":"loud"}"#).text)
        #expect(answer["ok"] == .bool(false))
        #expect(answer["error"]?.string?.contains("fps") == true)
        answer = try object(cli.panel(#"{"op":"set","id":"renderer","value":"dxvk"}"#).text)
        #expect(answer["ok"] == .bool(false), "the renderer is a game's own")
        answer = try object(cli.panel("not json").text)
        #expect(answer["ok"] == .bool(false))
    }

    @Test("a running game is told changes apply after a restart")
    func runningGame() throws {
        let fixture = try SettingsFixture(running: true)
        defer { fixture.cleanUp() }
        try fixture.service.store.updateGame(4) { $0.exes = ["a.exe"] }
        try FileManager.default.createDirectory(at: fixture.prefix(4), withIntermediateDirectories: true)
        let state = try #require(fixture.service.stateJSON(appID: 4).object)
        #expect(state["status"] == .string("restartGame"))
        #expect(state["running"] == .bool(true))
    }

    @Test("for all games: inherits NotProton's defaults, a game inherits from it")
    func globalLevel() throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanUp() }
        let cli = SettingsCLI(service: fixture.service)
        var result = cli.run(["set", "retina", "true"])
        #expect(result.status == 0, "\(result.error)")
        let global = try object(result.output)
        #expect(global["level"] == .string("global"))
        #expect(global["values"]?.object?["renderer"] == nil, "no renderer for all games")
        #expect(global["values"]?.object?["retina"]?.object?["inheritedFrom"] == .string("defaults"))

        result = cli.run(["state", "--app", "77"])
        let game = try object(result.output)
        let retina = try #require(game["values"]?.object?["retina"]?.object)
        #expect(retina["own"] == .null)
        #expect(retina["inherited"] == .bool(true))
        #expect(retina["inheritedFrom"] == .string("global"))
        #expect(retina["inheritedLabel"]?.object?["uk"] == .string("Увімк."))

        result = cli.run(["reset"])
        #expect(result.status == 0)
        #expect(fixture.service.store.global() == .empty)
        #expect(cli.run(["set", "nope", "1"]).status == 1)
        #expect(cli.run(["bogus"]).status == 2)
    }

    @Test("Dormison's View menu choices are stored for the game")
    func viewMenu() throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanUp() }
        let cli = SettingsCLI(service: fixture.service)
        for call in [
            ["app", "config", "227300", "upscaler", "metalfx"],
            ["app", "config", "227300", "filter", "bilinear"],
            ["app", "config", "227300", "fps", "on"],
            ["app", "config", "227300", "fps-graph", "off"],
            ["app", "config", "227300", "windows", "window"],
        ] {
            let result = cli.run(call)
            #expect(result.status == 0, "\(call): \(result.error)")
        }
        let game = fixture.service.store.game(227300)
        #expect(game.upscaler == .metalfx)
        #expect(game.filter == .bilinear)
        #expect(game.fps == true)
        #expect(game.fpsGraph == false)
        #expect(game.windows == .window)

        #expect(cli.run(["app", "config", "227300", "upscaler", "anime4k"]).status == 1, "no shader packages")
        #expect(cli.run(["app", "config", "227300", "fps", "maybe"]).status == 1)
        #expect(cli.run(["app", "config", "x", "fps", "on"]).status == 2)
        #expect(fixture.service.store.game(227300) == game)
    }

    @Test("compat_run.sh's launch records the game's programs and writes the prefix")
    func launch() throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanUp() }
        try fixture.install(1422450, name: "Deadlock", dir: "Deadlock",
                            exes: ["game/bin/win64/deadlock.exe", "game/bin/win64/vconsole2.exe"])
        try fixture.service.store.updateGame(1422450) { $0.cursorConfine = true }
        let pfx = fixture.prefix(1422450)
        let result = SettingsCLI(service: fixture.service).run([
            "launch", "--app", "1422450", "--exe",
            fixture.steam.appending(path: "steamapps/common/Deadlock/game/bin/win64/deadlock.exe").path,
            "--install", fixture.steam.appending(path: "steamapps/common/Deadlock").path,
            "--prefix", pfx.path,
        ])
        #expect(result.status == 0, "\(result.error)")
        #expect(fixture.read(".sevo/apps/deadlock.exe.env", in: 1422450)?.contains("SEVO_CURSOR_CONFINE=1") == true)
        #expect(fixture.read(".sevo/apps/vconsole2.exe.env", in: 1422450)?.contains("SEVO_CURSOR_CONFINE=1") == true)
        #expect(fixture.read(".sevo/bottle.env", in: 1422450)?.hasPrefix(ConfigMaterializer.header) == true)

        // A helper Steam runs in the prefix is not the game.
        _ = SettingsCLI(service: fixture.service).run([
            "launch", "--app", "1422450", "--exe", "C:\\steam\\legacycompat\\iscriptevaluator.exe", "--prefix", pfx.path,
        ])
        #expect(fixture.service.store.game(1422450).exes == ["deadlock.exe", "vconsole2.exe"])
    }

    /// dylib/tests/panel-behavior/fixtures: what the panel tests draw.
    static var panelFixtures: URL {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "dylib/tests/panel-behavior/fixtures")
    }

    @Test("the panel's fixtures are what the CLI prints today")
    func panelFixturesAreCurrent() throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanUp() }
        let catalog = try JSONValue.parse(String(
            contentsOf: Self.panelFixtures.appending(path: "catalog.json"), encoding: .utf8))
        #expect(catalog == fixture.service.catalogJSON(),
                "regenerate dylib/tests/panel-behavior/fixtures/catalog.json with notproton-settings catalog")
        for (file, level) in [("state-game.json", SettingLevel.game), ("state-global.json", .global)] {
            let state = try JSONValue.parse(String(
                contentsOf: Self.panelFixtures.appending(path: file), encoding: .utf8))
            let ids = Set(state.object?["values"]?.object?.keys.map { $0 } ?? [])
            let wanted = Set(SettingCatalog.all.filter { $0.levels.contains(level) }.map(\.id.rawValue))
            #expect(ids == wanted, "\(file) lists the settings of its level")
        }
    }

    @Test("executables: the game's own, not Windows' or the tools beside it")
    func executables() {
        #expect(GameExecutables.recordable("C:\\Games\\X\\Game.EXE") == "game.exe")
        #expect(GameExecutables.recordable("/a/b/steam.exe") == nil)
        #expect(GameExecutables.recordable("explorer.exe") == nil)
        #expect(GameExecutables.recordable("readme.txt") == nil)
        #expect(!GameExecutables.isGameLike("unitycrashhandler64.exe"))
        #expect(GameExecutables.isGameLike("vconsole2.exe"))
    }
}

@Suite("Localization")
struct LocalizationTests {

    /// Every text the catalog can show, with where it comes from.
    static var allTexts: [(String, L10n)] {
        var texts: [(String, L10n)] = []
        for setting in SettingCatalog.all {
            texts += setting.copy.texts.map { ("\(setting.id)", $0) }
            let choices: [SettingChoice]
            switch setting.control {
            case let .choice(list), let .limit(list, _), let .tuning(list), let .gpu(list), let .dllOverrides(list):
                choices = list
            case .toggle, .environment:
                choices = []
            }
            texts += choices.map { ("\(setting.id) choice \($0.value.text)", $0.label) }
        }
        texts += SettingGroup.allCases.map { ("group \($0)", GroupTitles.title($0)) }
        texts += PanelText.all.map { ("panel \($0.key)", $0.value) }
        texts += [("on", Words.on), ("off", Words.off), ("custom", Words.custom)]
        return texts
    }

    @Test("every text exists in English, Ukrainian and Russian")
    func complete() {
        for (place, text) in Self.allTexts {
            for language in Language.allCases {
                #expect(!text[language].trimmingCharacters(in: .whitespaces).isEmpty, "\(place) has no \(language)")
            }
        }
    }

    @Test("Ukrainian and Russian are translations, not English left in place")
    func translated() {
        for (place, text) in Self.allTexts {
            // A name that reads the same everywhere (DXMT, Lanczos, msync+) is one text.
            if text.en == text.uk && text.en == text.ru { continue }
            #expect(text.uk != text.en, "\(place): uk is English: \(text.en)")
            #expect(text.ru != text.en, "\(place): ru is English: \(text.en)")
        }
    }

    @Test("placeholders survive translation")
    func placeholders() {
        for (place, text) in Self.allTexts {
            let count = { (s: String) in s.components(separatedBy: "%@").count - 1 }
            #expect(count(text.uk) == count(text.en) && count(text.ru) == count(text.en), "\(place)")
        }
    }

    @Test("Steam's language names pick the panel's language, English otherwise")
    func steamLanguage() {
        #expect(Language(steam: "ukrainian") == .uk)
        #expect(Language(steam: "russian") == .ru)
        #expect(Language(steam: "english") == .en)
        #expect(Language(steam: "german") == .en)
        #expect(Language(locale: "uk_UA") == .uk)
    }
}
