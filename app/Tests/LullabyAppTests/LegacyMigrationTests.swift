import Foundation
import Testing

@testable import LullabyApp
@testable import LullabySettings

// The move from NotProton (docs/RENAME_LULLABY.md §3) on a temporary home that looks like
// the owner's: the old folder with two engines, a bridge, settings and launchers, five
// games tied to the old tool in config.vdf, markers in the prefixes, Steam.app patched.
@Suite("Move from NotProton", .serialized)
struct LegacyMigrationTests {

    final class Calls: @unchecked Sendable {
        var quit = 0
        var repair = 0
        var steamRunning = false
        var steamRunningAfterQuit = false
        var log: [String] = []
    }

    struct Rig {
        let home: URL
        let layout: LegacyMigration.Layout
        let calls = Calls()

        static let games = [4022369388, 227300, 3527290, 240, 1422450]

        init() throws {
            home = URL.temporaryDirectory.appending(path: "lb-migrate-\(UUID().uuidString)")
            layout = LegacyMigration.Layout(
                home: home, steamApp: home.appending(path: "Applications/Steam.app"), readsLibraryFolders: false)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: home) }

        func write(_ text: String, _ url: URL, executable: Bool = false) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
            if executable {
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path(percentEncoded: false))
            }
        }

        func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }
        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

        var old: URL { layout.oldSupport }
        var new: URL { layout.newSupport }
        func compat(_ id: Int) -> URL { layout.steamUserData.appending(path: "steamapps/compatdata/\(id)") }

        static func configVDF(tool: String = "notproton", extra: String = "") -> String {
            var mapping = ""
            for id in games {
                mapping += "\t\t\t\t\t\"\(id)\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"name\"\t\t\"\(tool)\"\n"
                    + "\t\t\t\t\t\t\"config\"\t\t\"\"\n\t\t\t\t\t\t\"priority\"\t\t\"250\"\n\t\t\t\t\t}\n"
            }
            return "\"InstallConfigStore\"\n{\n\t\"Software\"\n\t{\n\t\t\"Valve\"\n\t\t{\n\t\t\t\"Steam\"\n\t\t\t{\n"
                + "\t\t\t\t\"CompatToolMapping\"\n\t\t\t\t{\n" + mapping + extra + "\t\t\t\t}\n"
                + "\t\t\t\t\"Other\"\n\t\t\t\t{\n\t\t\t\t\t\"name\"\t\t\"notproton\"\n\t\t\t\t}\n"
                + "\t\t\t}\n\t\t}\n\t}\n}\n"
        }

        /// The owner's layout, under the old names.
        func makeOld(patchedSteam: Bool = true) throws {
            for engine in ["dormison-b2", "dormison-r5"] {
                let root = old.appending(path: "runners/\(engine)")
                try write("#!/bin/sh\n", root.appending(path: "wine/bin/wine"), executable: true)
                try write("#!/bin/sh\n", root.appending(path: "wine/bin/wineserver"), executable: true)
                try write("{\"version\":\"\(engine)\",\"commit\":\"abc\"}", root.appending(path: "engine-info.json"))
                try write("NP_ENGINE_VERSION='\(engine)'\n", root.appending(path: "notproton-engine.env"))
                try write("clean", root.appending(path: "wine/lib/wine/x86_64-windows/ntdll.dll.notproton-orig"))
                try write("b1", root.appending(path: "wine/lib/wine/x86_64-windows/ntdll.dll"))
            }
            try FileManager.default.createSymbolicLink(
                atPath: old.appending(path: "runners/current").path(percentEncoded: false), withDestinationPath: "dormison-r5")
            try write("{\"current\":\"bridge-dormison-r5-1\"}", old.appending(path: "bridges/state.json"))
            try write("log line\n", old.appending(path: "app.log"))
            try write("dylib log\n", old.appending(path: "notproton.log"))
            try write("binary", old.appending(path: "notproton-settings"))
            try write("#!/bin/sh\n", old.appending(path: "notproton-sevo"))
            try write("plist", old.appending(path: "backups/Info.plist.before-notproton"))
            try write("src\n", old.appending(path: "launchers/app-3527290/notproton-icon.source"))
            try write("manual\n", old.appending(path: "steam-update-gate"))
            let store = SettingsStore(root: old.appending(path: "settings"))
            try store.updateGame(3527290) { values in
                values.renderer = .dxmt
                values.exes = ["peak.exe"]
            }
            try write("pkg", home.appending(path: "Library/Caches/notproton/valve-packages/appdmg.zip"))

            for id in Self.games {
                try write("0\n", compat(id).appending(path: "notproton-msync"))
                try write("=== run\n", compat(id).appending(path: "notproton-run.log"))
            }
            try write("057e/2006\n", compat(3527290).appending(path: "notproton-hidden-controllers"))
            let sevo = compat(3527290).appending(path: "pfx/.sevo")
            try write("# written by NotProton; edits are overwritten\nWINEMSYNC=1\n", sevo.appending(path: "bottle.env"))
            try write("# written by NotProton; edits are overwritten\nNOTPROTON_RENDERER=dxmt\nSEVO_LOADER=/x/wine\n",
                      sevo.appending(path: "apps/peak.exe.env"))

            try write(Self.configVDF(extra: "\t\t\t\t\t\"999\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"name\"\t\t\"proton_9\"\n\t\t\t\t\t}\n"),
                      layout.configVDF)
            try write("\"compatibilitytools\"{}\n", layout.oldTool.appending(path: "compatibilitytool.vdf"))

            let macOS = layout.steamApp.appending(path: "Contents/MacOS")
            try write("steam", macOS.appending(path: "steam_osx"))
            var environment: [String: Any] = ["LC_ALL": "en_US.UTF-8"]
            if patchedSteam {
                try write("dylib", macOS.appending(path: "notproton.dylib"))
                environment["DYLD_INSERT_LIBRARIES"] = macOS.appending(path: "notproton.dylib").path(percentEncoded: false)
            }
            try FileManager.default.createDirectory(at: layout.steamApp.appending(path: "Contents"), withIntermediateDirectories: true)
            try SteamBundle.writeInfoPlist(["CFBundleIdentifier": "com.valvesoftware.steam", "LSEnvironment": environment],
                                           at: layout.steamApp.appending(path: "Contents/Info.plist"))
        }

        var effects: LegacyMigration.Effects {
            let calls = calls
            return LegacyMigration.Effects(
                gameIsRunning: { _ in false },
                steamIsRunning: { calls.steamRunning },
                quitSteam: { _ in
                    calls.quit += 1
                    calls.steamRunning = calls.steamRunningAfterQuit
                },
                repairSteam: { layout in
                    calls.repair += 1
                    try HeadlessMigration.standInRepair(layout.steamApp)
                },
                copyDefaults: { [] },
                log: { calls.log.append($0) })
        }
    }

    @Test("The whole move: folder, names inside, markers, env files, Steam, config.vdf; nothing old is left")
    func fullMove() async throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        try rig.makeOld()
        #expect(LegacyMigration.isNeeded(rig.layout))

        let report = try await LegacyMigration.run(rig.layout, effects: rig.effects)

        #expect(report.movedSupport && report.movedCaches)
        #expect(!rig.exists(rig.old) && rig.exists(rig.new))
        #expect(rig.exists(rig.layout.newCaches.appending(path: "valve-packages/appdmg.zip")))
        #expect(!rig.exists(rig.layout.pending))
        // Inside the folder.
        #expect(rig.read(rig.new.appending(path: "lullaby.log")) == "dylib log\n")
        #expect(rig.read(rig.new.appending(path: "app.log")) == "log line\n")
        #expect(!rig.exists(rig.new.appending(path: "notproton-settings")) && !rig.exists(rig.new.appending(path: "notproton-sevo")))
        #expect(rig.exists(rig.new.appending(path: "backups/Info.plist.before-lullaby")))
        #expect(rig.exists(rig.new.appending(path: "launchers/app-3527290/lullaby-icon.source")))
        #expect(rig.read(rig.new.appending(path: "steam-update-gate")) == "manual\n", "the manual Steam block moves with the folder")
        for engine in ["dormison-b2", "dormison-r5"] {
            let root = rig.new.appending(path: "runners/\(engine)")
            #expect(!rig.exists(root.appending(path: "notproton-engine.env")))
            let env = try #require(rig.read(root.appending(path: "lullaby-engine.env")))
            #expect(env.contains("LB_ENGINE_VERSION='\(engine)'"))
            #expect(env.contains(rig.new.appending(path: "runners/\(engine)/wine/bin/wine").path(percentEncoded: false)))
            #expect(!env.contains("/notproton/"))
            #expect(rig.read(root.appending(path: "wine/lib/wine/x86_64-windows/ntdll.dll.lullaby-orig")) == "clean")
        }
        #expect(report.engineFiles.sorted() == ["dormison-b2", "dormison-r5"])
        #expect((try? FileManager.default.destinationOfSymbolicLink(
            atPath: rig.new.appending(path: "runners/current").path(percentEncoded: false))) == "dormison-r5")
        // Prefixes.
        for id in Rig.games {
            #expect(rig.exists(rig.compat(id).appending(path: "lullaby-msync")))
            #expect(!rig.exists(rig.compat(id).appending(path: "notproton-msync")))
        }
        #expect(rig.exists(rig.compat(3527290).appending(path: "lullaby-hidden-controllers")))
        let game = try #require(rig.read(rig.compat(3527290).appending(path: "pfx/.sevo/apps/peak.exe.env")))
        #expect(game.hasPrefix(ConfigMaterializer.header))
        #expect(game.contains("LULLABY_RENDERER=dxmt") && !game.contains("NOTPROTON_"))
        #expect(game.contains("SEVO_LOADER=/x/wine"), "the run script's line stays")
        let bottle = try #require(rig.read(rig.compat(3527290).appending(path: "pfx/.sevo/bottle.env")))
        #expect(bottle.hasPrefix(ConfigMaterializer.header))
        #expect(bottle.contains(rig.new.appending(path: "lullaby-sevo").path(percentEncoded: false)))
        #expect(!rig.exists(rig.compat(3527290).appending(path: "pfx/.sevo/pre-catalog-backup")),
                "files with the old header are the catalog's, not migrated as the player's")
        let store = SettingsStore(root: rig.new.appending(path: "settings"))
        #expect(store.game(3527290).renderer == .dxmt)
        // Steam.
        #expect(rig.calls.repair == 1 && report.repairedSteam)
        #expect(!LegacyMigration.steamHasOldPatch(rig.layout.steamApp))
        #expect(!rig.exists(rig.layout.oldTool) && report.removedOldTool)
        #expect(report.mappings == 5 && report.configBackup)
        let config = try #require(rig.read(rig.layout.configVDF))
        #expect(config == Rig.configVDF(tool: "lullaby",
            extra: "\t\t\t\t\t\"999\"\n\t\t\t\t\t{\n\t\t\t\t\t\t\"name\"\t\t\"proton_9\"\n\t\t\t\t\t}\n"))
        #expect(config.contains("\"Other\"\n\t\t\t\t{\n\t\t\t\t\t\"name\"\t\t\"notproton\""), "outside CompatToolMapping nothing changes")
        let backup = rig.layout.configVDF.deletingLastPathComponent().appending(path: "config.vdf.before-lullaby")
        #expect(rig.read(backup)?.components(separatedBy: "\"notproton\"").count == 7, "the copy is the file as it was")
        #expect(!LegacyMigration.isNeeded(rig.layout))
        #expect(rig.calls.log.last == "done")
    }

    @Test("A second run changes nothing, and the config.vdf copy is never overwritten")
    func idempotent() async throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        try rig.makeOld()
        _ = try await LegacyMigration.run(rig.layout, effects: rig.effects)
        let config = rig.read(rig.layout.configVDF)
        let backup = rig.layout.configVDF.deletingLastPathComponent().appending(path: "config.vdf.before-lullaby")
        let backupText = rig.read(backup)
        let game = rig.read(rig.compat(3527290).appending(path: "pfx/.sevo/apps/peak.exe.env"))

        let again = try await LegacyMigration.run(rig.layout, effects: rig.effects)

        #expect(!again.movedSupport && !again.movedCaches && again.renamed.isEmpty && again.removed.isEmpty)
        #expect(again.engineFiles.isEmpty && !again.repairedSteam && !again.removedOldTool)
        #expect(again.mappings == 0 && !again.configBackup)
        #expect(rig.calls.repair == 1)
        #expect(rig.read(rig.layout.configVDF) == config && rig.read(backup) == backupText)
        #expect(rig.read(rig.compat(3527290).appending(path: "pfx/.sevo/apps/peak.exe.env")) == game)
    }

    @Test("A Lullaby installation already there stops the move; nothing is moved or merged")
    func bothFolders() async throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        try rig.makeOld()
        try rig.write("{}", rig.new.appending(path: "settings/global.json"))

        await #expect(throws: StepFailure.self) {
            try await LegacyMigration.run(rig.layout, effects: rig.effects)
        }
        #expect(rig.exists(rig.old.appending(path: "runners/dormison-r5")))
        #expect(!rig.exists(rig.new.appending(path: "runners")))
        #expect(rig.calls.repair == 0)
        #expect(rig.read(rig.layout.configVDF)?.contains("\"lullaby\"") == false, "config.vdf untouched")
    }

    @Test("The original NotProton's folder beside a Lullaby installation stays; the rest goes on")
    func upstreamBesideInstallation() async throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        try rig.write("1.1.7\n", rig.old.appending(path: "dylib.version"))
        try rig.write("x", rig.old.appending(path: "runners/crossover-26.3.0.39832/marker"))
        try rig.write("x", rig.old.appending(path: "bridge/steam.exe"))
        try rig.write("{}", rig.new.appending(path: "settings/global.json"))
        #expect(!LegacyMigration.isNeeded(rig.layout), "Install no longer offers the move")

        let report = try await LegacyMigration.run(rig.layout, effects: rig.effects)

        #expect(!report.movedSupport)
        #expect(rig.exists(rig.old.appending(path: "runners/crossover-26.3.0.39832/marker")))
        #expect(rig.exists(rig.new.appending(path: "settings/global.json")))
        #expect(!rig.exists(rig.new.appending(path: "runners")))
        #expect(!rig.exists(rig.layout.pending))
    }

    @Test("What the window wrote before the move joins the moved folder")
    func earlyLogs() async throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        try rig.makeOld()
        try rig.write("new start\n", rig.new.appending(path: "app.log"))
        try rig.write("auto\n", rig.new.appending(path: "steam-update-gate"))

        let report = try await LegacyMigration.run(rig.layout, effects: rig.effects)

        #expect(report.movedSupport)
        #expect(rig.read(rig.new.appending(path: "app.log")) == "log line\nnew start\n")
        #expect(rig.read(rig.new.appending(path: "steam-update-gate")) == "manual\n", "the moved folder's own file wins")
        #expect(rig.read(rig.new.appending(path: "backups/before-move/steam-update-gate")) == "auto\n")
        #expect(!rig.exists(rig.layout.applicationSupport.appending(path: "lullaby.early-logs")))
    }

    @Test("config.vdf: no old tool → untouched, no copy; other tools and keys stay byte for byte")
    func configCases() throws {
        let none = Rig.configVDF(tool: "proton_9")
        #expect(LegacyMigration.rewriteToolMapping(none).count == 0)
        #expect(LegacyMigration.rewriteToolMapping(none).text == none)
        let one = none.replacingOccurrences(of: "\"proton_9\"", with: "\"notproton\"")
        #expect(LegacyMigration.rewriteToolMapping(one).count == 5)
        let mixed = "\"CompatToolMapping\"\n{\n\t\"1\"\n\t{\n\t\t\"name\"\t\t\"notproton\"\n\t}\n"
            + "\t\"2\"\n\t{\n\t\t\"name\"\t\t\"notproton-fork\"\n\t\t\"config\"\t\t\"notproton\"\n\t}\n}\n"
        let (text, count) = LegacyMigration.rewriteToolMapping(mixed)
        #expect(count == 1)
        #expect(text == mixed.replacingOccurrences(of: "\"name\"\t\t\"notproton\"\n", with: "\"name\"\t\t\"lullaby\"\n"))

        let rig = try Rig()
        defer { rig.cleanUp() }
        try rig.write(none, rig.layout.configVDF)
        let (moved, copy) = try LegacyMigration.rewriteConfig(rig.layout)
        #expect(moved == 0 && !copy)
        #expect(!rig.exists(rig.layout.configVDF.deletingLastPathComponent().appending(path: "config.vdf.before-lullaby")))
        #expect(rig.read(rig.layout.configVDF) == none)
    }

    @Test("A running game stops the move before anything changes")
    func gameRunning() async throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        try rig.makeOld()
        var effects = rig.effects
        effects.gameIsRunning = { _ in true }
        await #expect(throws: KnownProblem.self) {
            try await LegacyMigration.run(rig.layout, effects: effects)
        }
        #expect(rig.exists(rig.old) && !rig.exists(rig.new) && rig.calls.quit == 0)
    }

    @Test("Steam is closed first; if it is back before config.vdf, the run stops there and Retry finishes")
    func steamClosedFirst() async throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        try rig.makeOld()
        rig.calls.steamRunning = true
        rig.calls.steamRunningAfterQuit = true
        await #expect(throws: SteamBundle.StillRunning.self) {
            try await LegacyMigration.run(rig.layout, effects: rig.effects)
        }
        #expect(rig.calls.quit == 1)
        #expect(rig.read(rig.layout.configVDF)?.contains("\"lullaby\"") == false)
        #expect(LegacyMigration.isNeeded(rig.layout), "what is left is found again")

        rig.calls.steamRunning = false
        let report = try await LegacyMigration.run(rig.layout, effects: rig.effects)
        #expect(report.mappings == 5 && !report.movedSupport)
        #expect(!LegacyMigration.isNeeded(rig.layout))
    }

    @Test("Nothing of NotProton: the step is not in the flow")
    func notNeeded() throws {
        let rig = try Rig()
        defer { rig.cleanUp() }
        try rig.write(Rig.configVDF(tool: "lullaby"), rig.layout.configVDF)
        #expect(!LegacyMigration.isNeeded(rig.layout))
        var env = SetupEnvironment()
        env.legacy = rig.layout
        #expect(!SetupSteps.setup(nil, env).contains { $0.id == .migrate })
        try rig.makeOld()
        #expect(SetupSteps.setup(nil, env).first?.id == .migrate)
        #expect(SetupSteps.reinstall(env).first?.id == .migrate)
        env.legacy = nil
        #expect(!SetupSteps.setup(nil, env).contains { $0.id == .migrate })
    }

    @Test("Preferences worth keeping move to the new domain; a value already there wins")
    func defaults() throws {
        let oldName = "lullaby-tests-old-\(UUID().uuidString)", newName = "lullaby-tests-new-\(UUID().uuidString)"
        let old = try #require(UserDefaults(suiteName: oldName)), new = try #require(UserDefaults(suiteName: newName))
        defer {
            old.removePersistentDomain(forName: oldName)
            new.removePersistentDomain(forName: newName)
        }
        old.set(true, forKey: "NotProtonFirstInstallDone")
        old.set(true, forKey: "NotProtonSteamUpdatesTipSeen")
        old.set(false, forKey: "SUEnableAutomaticChecks")
        old.set("x", forKey: "Unrelated")
        new.set(false, forKey: "LullabySteamUpdatesTipSeen")
        let copied = LegacyMigration.copyDefaults(from: old, to: new)
        #expect(copied == ["LullabyFirstInstallDone", "SUEnableAutomaticChecks"])
        #expect(new.bool(forKey: "LullabyFirstInstallDone"))
        #expect(new.object(forKey: "SUEnableAutomaticChecks") as? Bool == false)
        #expect(new.bool(forKey: "LullabySteamUpdatesTipSeen") == false)
        #expect(new.object(forKey: "Unrelated") == nil)
    }

    @Test("The window offers Install when NotProton is found")
    func window() {
        let screen = MainScreen.make(install: .legacy, plan: nil, flow: nil)
        #expect(screen.button == MainScreen.Button.install && screen.buttonEnabled)
        #expect(screen.status.contains("NotProton") && screen.tone == .attention)
    }
}
