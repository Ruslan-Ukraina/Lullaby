// The env files on disk: a header, every executable of a game, the run script's
// lines kept, WINEMSYNC never changed under a running game, idempotent rewrites;
// and the migration of the files NotProton wrote before the catalog.

import Foundation
import Testing
@testable import NotProtonSettings

/// A Steam library and a support directory in a temporary folder.
struct SettingsFixture {
    let root: URL
    let steam: URL
    let service: SettingsService

    init(running: Bool = false) throws {
        root = URL.temporaryDirectory.appending(path: "np-settings-\(UUID().uuidString)")
        steam = root.appending(path: "Steam")
        try FileManager.default.createDirectory(
            at: steam.appending(path: "steamapps/compatdata"), withIntermediateDirectories: true)
        service = SettingsService(
            store: SettingsStore(root: root.appending(path: "support/settings")),
            library: GameLibrary(roots: [steam]),
            cli: "/support/notproton-sevo",
            gameIsRunning: { _ in running },
            engineVersion: { "dormison-b1" },
            log: { _ in })
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    func prefix(_ appID: Int) -> URL { steam.appending(path: "steamapps/compatdata/\(appID)/pfx") }

    func write(_ text: String, _ path: String, in appID: Int) throws {
        let url = prefix(appID).appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func read(_ path: String, in appID: Int) -> String? {
        try? String(contentsOf: prefix(appID).appending(path: path), encoding: .utf8)
    }

    /// An installed game: its manifest and executables.
    func install(_ appID: Int, name: String, dir: String, exes: [String]) throws {
        let manifest = """
            "AppState"
            {
            \t"appid"\t\t"\(appID)"
            \t"name"\t\t"\(name)"
            \t"installdir"\t\t"\(dir)"
            }
            """
        try manifest.write(
            to: steam.appending(path: "steamapps/appmanifest_\(appID).acf"), atomically: true, encoding: .utf8)
        for exe in exes {
            let url = steam.appending(path: "steamapps/common/\(dir)/\(exe)")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("MZ".utf8).write(to: url)
        }
    }
}

@Suite("Config materializer")
struct ConfigMaterializerTests {

    @Test("every executable of a game gets the game's lines, the loader line stays")
    func severalExecutables() throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanUp() }
        try fixture.install(1422450, name: "Deadlock", dir: "Deadlock",
                            exes: ["game/bin/win64/deadlock.exe", "game/bin/win64/vconsole2.exe",
                                   "game/bin/win64/crashreporter.exe"])
        try FileManager.default.createDirectory(at: fixture.prefix(1422450), withIntermediateDirectories: true)
        try fixture.write("# written by NotProton; edits are overwritten\nSEVO_LOADER=/b/Deadlock.app/Contents/MacOS/wine\n",
                          ".sevo/apps/deadlock.exe.env", in: 1422450)

        try fixture.service.record(appID: 1422450, exe: "deadlock.exe", installDirectory: nil)
        #expect(fixture.service.store.game(1422450).exes == ["deadlock.exe", "vconsole2.exe"])
        #expect(fixture.service.store.game(1422450).name == "Deadlock")

        try fixture.service.set("fps", .bool(true), appID: 1422450)
        let deadlock = try #require(fixture.read(".sevo/apps/deadlock.exe.env", in: 1422450))
        let vconsole = try #require(fixture.read(".sevo/apps/vconsole2.exe.env", in: 1422450))
        #expect(deadlock.hasPrefix(ConfigMaterializer.header))
        #expect(deadlock.contains("SEVO_FPS=1"))
        #expect(vconsole.contains("SEVO_FPS=1"))
        #expect(deadlock.contains("SEVO_LOADER=/b/Deadlock.app/Contents/MacOS/wine"), "the run script's line stays")
        #expect(!vconsole.contains("SEVO_LOADER"))
        #expect(fixture.read(".sevo/apps/crashreporter.exe.env", in: 1422450) == nil)
    }

    @Test("bottle.env keeps a running game's WINEMSYNC and names the stand-in")
    func bottleKeepsMsync() throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(at: fixture.prefix(5), withIntermediateDirectories: true)
        try fixture.service.set("msync", .bool(false), appID: 5)
        var bottle = try #require(fixture.read(".sevo/bottle.env", in: 5))
        #expect(bottle.contains("NOTPROTON_MSYNC=0"))
        #expect(bottle.contains("WINEMSYNC=0"), "a new bottle.env starts with the setting")
        #expect(bottle.contains("SEVO_CLI=/support/notproton-sevo"))

        // The run script set WINEMSYNC=1 for the session now running.
        try fixture.write(bottle.replacingOccurrences(of: "WINEMSYNC=0", with: "WINEMSYNC=1"), ".sevo/bottle.env", in: 5)
        try fixture.service.set("fps", .bool(true), appID: nil)
        bottle = try #require(fixture.read(".sevo/bottle.env", in: 5))
        #expect(bottle.contains("WINEMSYNC=1"))
        #expect(bottle.contains("SEVO_FPS=1"))
    }

    @Test("rewrites are whole-file and idempotent; files of others are left alone")
    func idempotent() throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(at: fixture.prefix(9), withIntermediateDirectories: true)
        var stack = ConfigStack(global: .empty)
        stack.game.exes = ["a.exe", "b.exe"]
        stack.game.fps = true
        var outcome = try ConfigMaterializer.write(prefix: fixture.prefix(9), appID: 9, stack: stack, cli: nil)
        #expect(outcome.written.sorted() == ["apps/a.exe.env", "apps/b.exe.env", "bottle.env"])
        outcome = try ConfigMaterializer.write(prefix: fixture.prefix(9), appID: 9, stack: stack, cli: nil)
        #expect(outcome.written.isEmpty)

        try fixture.write("MY_OWN=1\n", ".sevo/apps/tool.exe.env", in: 9)
        stack.game.exes = ["a.exe"]
        outcome = try ConfigMaterializer.write(prefix: fixture.prefix(9), appID: 9, stack: stack, cli: nil)
        #expect(outcome.removed == ["apps/b.exe.env"])
        #expect(fixture.read(".sevo/apps/b.exe.env", in: 9) == nil)
        #expect(fixture.read(".sevo/apps/tool.exe.env", in: 9) == "MY_OWN=1\n", "a file without the header is not ours")
    }

    @Test("a change for all games reaches every prefix")
    func globalReachesEveryPrefix() throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanUp() }
        for id in [10, 20] {
            try fixture.write("# written by NotProton; edits are overwritten\n", ".sevo/bottle.env", in: id)
        }
        try FileManager.default.createDirectory(at: fixture.prefix(30), withIntermediateDirectories: true)
        try fixture.service.set("upscaler", .string("lanczos"), appID: nil)
        #expect(fixture.read(".sevo/bottle.env", in: 10)?.contains("SEVO_UPSCALER=lanczos") == true)
        #expect(fixture.read(".sevo/bottle.env", in: 20)?.contains("SEVO_UPSCALER=lanczos") == true)
        #expect(fixture.read(".sevo/bottle.env", in: 30) == nil, "a prefix NotProton never ran is not touched")
    }

    @Test("reset returns a game to inherit and keeps its executables")
    func reset() throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanUp() }
        try FileManager.default.createDirectory(at: fixture.prefix(3), withIntermediateDirectories: true)
        try fixture.service.record(appID: 3, exe: "Game.EXE", installDirectory: nil)
        try fixture.service.set("retina", .bool(true), appID: 3)
        try fixture.service.set("renderer", .string("dxvk"), appID: 3)
        try fixture.service.reset(appID: 3)
        #expect(fixture.service.store.game(3).exes == ["game.exe"])
        #expect(fixture.service.store.game(3).hasSettings == false)
        let file = try #require(fixture.read(".sevo/apps/game.exe.env", in: 3))
        #expect(!file.contains("NOTPROTON_RETINA"))
        #expect(!file.contains("NOTPROTON_RENDERER"))
    }
}

@Suite("Config migration")
struct ConfigMigrationTests {

    /// PEAK's and Deadlock's files as Phase 2 left them.
    static let oldBottle = """
        # Dormison settings for every program in this prefix, first written by NotProton.
        # One KEY=VALUE per line; .sevo/apps/<program>.env overrides them per program.
        SEVO_RESIZABLE_WINDOWS=1
        SEVO_UPSCALER=off
        SEVO_FINAL_FILTER=lanczos
        SEVO_FPS=0
        SEVO_FPS_GRAPH=0
        SEVO_LINEAR_MOUSE=0
        SEVO_CURSOR_CONFINE=0
        WINEMSYNC=1
        SEVO_CLI=/support/notproton-sevo

        """

    @Test("the old files' values move into the store, nothing is lost, a backup stays")
    func migratesPhase2Files() throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanUp() }
        try fixture.write(Self.oldBottle.replacingOccurrences(of: "SEVO_FINAL_FILTER=lanczos", with: "SEVO_FINAL_FILTER=nearest"),
                          ".sevo/bottle.env", in: 1422450)
        try fixture.write("""
            SEVO_LOADER=/b/Deadlock.app/Contents/MacOS/wine
            SEVO_FPS_GRAPH=1
            NOTPROTON_RENDERER=dxmt
            ROSETTA_ADVERTISE_AVX=1
            NOTPROTON_RETINA=1
            DXVK_HUD=fps

            """, ".sevo/apps/deadlock.exe.env", in: 1422450)
        try fixture.write("SEVO_LOADER=/b/Deadlock.app/Contents/MacOS/wine\n", ".sevo/apps/steam.exe.env", in: 1422450)
        try fixture.write("deadlock.exe\n", ".sevo/game-exe", in: 1422450)
        try "0".write(to: fixture.prefix(1422450).deletingLastPathComponent().appending(path: "notproton-msync"),
                      atomically: true, encoding: .utf8)

        // What the panel's first look at the game runs (SettingsCLI "state").
        try fixture.service.migrateIfNeeded(appID: 1422450)

        let game = fixture.service.store.game(1422450)
        #expect(game.fpsGraph == true)
        #expect(game.renderer == .dxmt)
        #expect(game.avx == true)
        #expect(game.retina == true)
        #expect(game.filter == .nearest, "a bottle.env value the player changed is the game's")
        #expect(game.fps == nil, "the old profile's own values are not the player's")
        #expect(game.msync == false)
        #expect(game.environment == ["DXVK_HUD=fps"])
        #expect(game.exes == ["deadlock.exe"])

        let file = try #require(fixture.read(".sevo/apps/deadlock.exe.env", in: 1422450))
        #expect(file.hasPrefix(ConfigMaterializer.header))
        #expect(file.contains("SEVO_LOADER=/b/Deadlock.app/Contents/MacOS/wine"))
        #expect(file.contains("SEVO_FPS_GRAPH=1"))
        #expect(file.contains("DXVK_HUD=fps"))
        #expect(fixture.read(".sevo/apps/steam.exe.env", in: 1422450) == "SEVO_LOADER=/b/Deadlock.app/Contents/MacOS/wine\n",
                "the Steam shim's file is the run script's")
        #expect(fixture.read(".sevo/pre-catalog-backup/apps/deadlock.exe.env", in: 1422450)?.contains("NOTPROTON_RETINA=1") == true)
        #expect(fixture.read(".sevo/pre-catalog-backup/bottle.env", in: 1422450)?.contains("SEVO_FINAL_FILTER=nearest") == true)
        #expect(!ConfigMigration.needsMigration(prefix: fixture.prefix(1422450)))
    }

    @Test("a value already in the store wins over the old files")
    func storeWins() throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanUp() }
        try fixture.write(Self.oldBottle, ".sevo/bottle.env", in: 3527290)
        try fixture.write("SEVO_FPS=1\nNOTPROTON_RETINA=1\n", ".sevo/apps/peak.exe.env", in: 3527290)
        try fixture.service.store.updateGame(3527290) { $0.fps = false }
        let migrated = try fixture.service.migrateAll()
        #expect(migrated == [3527290])
        let game = fixture.service.store.game(3527290)
        #expect(game.fps == false)
        #expect(game.retina == true)
        #expect(try fixture.service.migrateAll().isEmpty, "a migrated prefix is not migrated again")
    }
}
