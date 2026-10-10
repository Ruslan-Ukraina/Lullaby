// Moves an installation made under the project's old name (NotProton until 10.10.2026,
// docs/RENAME_LULLABY.md §3) to Lullaby's names, as the first step of Install, Update
// and Reinstall. Every part looks at what is on disk and does only what is still left,
// so a second run, or one after a failure, finishes the job and otherwise changes nothing.
//
// Order: no game of ours may run and Steam is closed first (the old dylib inside Steam
// reads the old folder); then the files of our own (folder, names inside it, markers in
// the prefixes, the prefixes' env files, the app's preferences); then Steam: Repair takes
// the old patch out, the old tool folder goes, and the games' tool choice in config.vdf
// is rewritten, with a copy beside it. Install puts the new patch in later in the flow.

import Foundation
import LullabySettings

enum LegacyMigration {

    static let step = "Move from NotProton"
    /// The old name, as the folders, files and the Steam tool id spelled it.
    static let oldName = "notproton"
    static let newName = "lullaby"
    /// The old app's preferences domain (its bundle id).
    static let oldDefaultsDomain = "com.notproton.NotProton"
    /// What config.vdf keeps before its first rewrite.
    static let configBackupName = "config.vdf.before-lullaby"
    /// What makes a Lullaby folder an installation of its own, which the move never merges.
    static let installationMarkers: Set<String> = ["runners", "bridges", "settings"]
    /// Left in the new folder while the moved files are still being brought in line.
    static let pendingName = ".moving-from-notproton"

    /// Files inside the support folder: old name → new name.
    static let renamedFiles = [
        "notproton.log": "lullaby.log",
        "notproton-settings.log": "lullaby-settings.log",
        "notproton-sevo.log": "lullaby-sevo.log",
        "backups/Info.plist.before-notproton": "backups/Info.plist.before-lullaby",
    ]
    /// Copies of helpers that Install and the run script put back under the new names.
    static let replacedFiles = ["notproton-settings", "notproton-sevo", "notproton.dylib"]
    /// Suffixes of the clean engine files kept beside the patched ones (BridgeStore).
    static let renamedSuffixes = [".notproton-orig": ".lullaby-orig", ".notproton-b2": ".lullaby-b2"]
    /// The run script's markers in `<compatdata>/<appid>/`.
    static let renamedMarkers = [
        "notproton-msync": "lullaby-msync",
        "notproton-hidden-controllers": "lullaby-hidden-controllers",
    ]
    /// The run script's icon key in `launchers/app-<appid>/`.
    static let renamedLauncherFiles = ["notproton-icon.source": "lullaby-icon.source"]
    /// Preferences worth keeping: old key → new key.
    static let defaultsKeys = [
        "NotProtonFirstInstallDone": "LullabyFirstInstallDone",
        "NotProtonSteamUpdatesTipSeen": "LullabySteamUpdatesTipSeen",
        "NotProtonPrereleaseUpdates": "LullabyPrereleaseUpdates",
        EngineChannel.defaultsKey: EngineChannel.defaultsKey,
        "SUEnableAutomaticChecks": "SUEnableAutomaticChecks",
        "SUHasLaunchedBefore": "SUHasLaunchedBefore",
        "SUSendProfileInfo": "SUSendProfileInfo",
    ]

    // MARK: Where

    struct Layout: Sendable {
        var home: URL
        var steamApp: URL
        /// Libraries from libraryfolders.vdf besides the default one. Off for a copy in a
        /// scratch folder: its vdf names the real libraries.
        var readsLibraryFolders = true

        static var live: Layout { Layout(home: SupportPaths.home, steamApp: SupportPaths.Steam.app) }

        var applicationSupport: URL { home.appending(path: "Library/Application Support") }
        var oldSupport: URL { applicationSupport.appending(path: LegacyMigration.oldName) }
        var newSupport: URL { applicationSupport.appending(path: LegacyMigration.newName) }
        var oldCaches: URL { home.appending(path: "Library/Caches/\(LegacyMigration.oldName)") }
        var newCaches: URL { home.appending(path: "Library/Caches/\(LegacyMigration.newName)") }
        var pending: URL { newSupport.appending(path: LegacyMigration.pendingName) }

        var steamUserData: URL { applicationSupport.appending(path: "Steam") }
        var configVDF: URL { steamUserData.appending(path: "config/config.vdf") }
        var oldTool: URL { steamUserData.appending(path: "compatibilitytools.d/\(LegacyMigration.oldName)") }
        var innerApp: URL { steamUserData.appending(path: "Steam.AppBundle/Steam") }
        var innerPlist: URL { innerApp.appending(path: "Contents/Info.plist") }
        var updateBlocks: [URL] {
            [steamUserData.appending(path: "steam.cfg"), innerApp.appending(path: "Contents/MacOS/steam.cfg")]
        }

        var library: GameLibrary {
            readsLibraryFolders ? .standard(steam: steamUserData) : GameLibrary(roots: [steamUserData])
        }
    }

    /// What touches processes and preferences; the tests and a scratch copy hand in inert ones.
    struct Effects: Sendable {
        var gameIsRunning: @Sendable (Layout) -> Bool
        var steamIsRunning: @Sendable () -> Bool
        var quitSteam: @Sendable (Layout) throws -> Void
        var repairSteam: @Sendable (Layout) async throws -> Void
        var copyDefaults: @Sendable () -> [String]
        var log: @Sendable (String) -> Void

        static var live: Effects {
            Effects(
                gameIsRunning: { layout in
                    [layout.oldSupport, layout.newSupport].flatMap {
                        [$0.appending(path: "runners"), $0.appending(path: "launchers")]
                    }.contains { Shell.processIsRunning(commandLineContaining: $0.path(percentEncoded: false) + "/") }
                },
                steamIsRunning: { SteamBundle.isRunning },
                quitSteam: { layout in
                    _ = try SteamBundle.quitClient(app: layout.steamApp, helpers: [layout.innerApp])
                },
                repairSteam: { layout in
                    _ = try await SteamRepair.run(
                        app: layout.steamApp, innerPlist: layout.innerPlist, updateBlocks: layout.updateBlocks,
                        backups: layout.newSupport.appending(path: "backups"),
                        downloads: layout.newCaches.appending(path: "valve-packages"))
                },
                copyDefaults: {
                    guard let old = UserDefaults(suiteName: LegacyMigration.oldDefaultsDomain) else { return [] }
                    return LegacyMigration.copyDefaults(from: old, to: .standard)
                },
                log: { AppLog.note("migration: \($0)") })
        }

        /// For a copy in a scratch folder: nothing outside it is looked at or changed.
        static func inert(log: @escaping @Sendable (String) -> Void) -> Effects {
            Effects(
                gameIsRunning: { _ in false }, steamIsRunning: { false }, quitSteam: { _ in },
                repairSteam: { _ in }, copyDefaults: { [] }, log: log)
        }
    }

    // MARK: What is left

    /// Steam.app loads the old dylib, or still has it.
    static func steamHasOldPatch(_ app: URL) -> Bool {
        let oldDylib = app.appending(path: "Contents/MacOS/\(oldName).dylib")
        if FileManager.default.fileExists(atPath: oldDylib.path(percentEncoded: false)) { return true }
        let insert = SteamBundle.currentInsert(at: SupportPaths.Steam.infoPlist(inBundle: app)) ?? ""
        return insert.split(separator: ":").contains { $0.hasSuffix("/\(oldName).dylib") }
    }

    static func isNeeded(_ layout: Layout = .live) -> Bool {
        let files = FileManager.default
        func exists(_ url: URL) -> Bool { files.fileExists(atPath: url.path(percentEncoded: false)) }
        if exists(layout.oldSupport) || exists(layout.pending) || exists(layout.oldTool) { return true }
        if steamHasOldPatch(layout.steamApp) { return true }
        guard let text = try? String(contentsOf: layout.configVDF, encoding: .utf8) else { return false }
        return rewriteToolMapping(text).count > 0
    }

    /// What one run did, for the log and the tests.
    struct Report: Equatable, Sendable {
        var movedSupport = false
        var movedCaches = false
        var renamed: [String] = []
        var removed: [String] = []
        var engineFiles: [String] = []
        var materialized = false
        var defaults: [String] = []
        var repairedSteam = false
        var removedOldTool = false
        var mappings = 0
        var configBackup = false
    }

    // MARK: The run

    @discardableResult
    static func run(_ layout: Layout = .live, effects: Effects = .live) async throws -> Report {
        var report = Report()
        let files = FileManager.default
        func exists(_ url: URL) -> Bool { files.fileExists(atPath: url.path(percentEncoded: false)) }

        if effects.gameIsRunning(layout) {
            throw KnownProblem(.gameRunning, log: "migration: a game runs from \(oldName)/ or \(newName)/")
        }
        if effects.steamIsRunning() {
            effects.log("closing Steam")
            try effects.quitSteam(layout)
        }

        // Our own files.
        try moveSupport(layout, report: &report, log: effects.log)
        if exists(layout.oldCaches), !exists(layout.newCaches) {
            try files.moveItem(at: layout.oldCaches, to: layout.newCaches)
            report.movedCaches = true
            effects.log("moved \(layout.oldCaches.path(percentEncoded: false)) to \(newName)")
        }
        if exists(layout.newSupport) {
            renameInside(layout, report: &report)
            report.engineFiles = try rewriteEngineFiles(layout)
            renameMarkers(layout, report: &report)
            try materialize(layout, log: effects.log)
            report.materialized = true
        }
        report.defaults = effects.copyDefaults()
        for line in report.renamed { effects.log("renamed \(line)") }
        for line in report.removed { effects.log("removed \(line)") }
        if !report.engineFiles.isEmpty { effects.log("engine files written: \(report.engineFiles.joined(separator: " "))") }
        if !report.defaults.isEmpty { effects.log("preferences kept: \(report.defaults.joined(separator: " "))") }

        // Steam: the old patch out first, Install puts the new one in later.
        if steamHasOldPatch(layout.steamApp) {
            effects.log("Steam carries the NotProton patch, repairing Steam")
            try await effects.repairSteam(layout)
            report.repairedSteam = true
        }
        if exists(layout.oldTool) {
            try files.removeItem(at: layout.oldTool)
            report.removedOldTool = true
            effects.log("removed \(layout.oldTool.path(percentEncoded: false))")
        }
        if exists(layout.configVDF) {
            guard !effects.steamIsRunning() else {
                throw SteamBundle.StillRunning(seconds: Int(SteamBundle.quitTimeout))
            }
            let (count, backup) = try rewriteConfig(layout)
            report.mappings = count
            report.configBackup = backup
            if count > 0 {
                effects.log("config.vdf: \(count) game(s) moved from \(oldName) to \(newName)"
                    + (backup ? ", copy in \(configBackupName)" : ""))
            }
        }

        try? files.removeItem(at: layout.pending)
        effects.log("done")
        return report
    }

    // MARK: Parts

    /// One rename of the whole folder, the same disk, no copy. A Lullaby folder that is
    /// there already stops it when it is an installation (an engine, a bridge or settings).
    /// Otherwise it is what the window wrote before the move (it logs as soon as it opens):
    /// its logs are appended to the moved ones, anything else goes to
    /// `backups/before-move/` in the moved folder.
    static func moveSupport(_ layout: Layout, report: inout Report, log: (String) -> Void) throws {
        let files = FileManager.default
        let old = layout.oldSupport.path(percentEncoded: false)
        let new = layout.newSupport.path(percentEncoded: false)
        guard files.fileExists(atPath: old) else { return }

        var early: [String] = []
        if files.fileExists(atPath: new) {
            let entries = try files.contentsOfDirectory(atPath: new).filter { $0 != ".DS_Store" }
            guard !entries.contains(where: installationMarkers.contains) else {
                throw StepFailure(
                    step: step,
                    detail: "Both \(old) and \(new) exist. Nothing was moved. "
                        + "Move one of them away, then press Install again.")
            }
            early = entries
            let aside = layout.applicationSupport.appending(path: "\(newName).early-logs")
            try? files.removeItem(at: aside)
            try files.moveItem(at: layout.newSupport, to: aside)
            try files.moveItem(at: layout.oldSupport, to: layout.newSupport)
            let kept = layout.newSupport.appending(path: "backups/before-move")
            for name in early {
                if name.hasSuffix(".log") {
                    try appendLog(aside.appending(path: name), to: layout.newSupport.appending(path: name))
                } else {
                    try files.createDirectory(at: kept, withIntermediateDirectories: true)
                    try? files.removeItem(at: kept.appending(path: name))
                    try files.moveItem(at: aside.appending(path: name), to: kept.appending(path: name))
                }
            }
            try files.removeItem(at: aside)
        } else {
            try files.moveItem(at: layout.oldSupport, to: layout.newSupport)
        }
        try Data().write(to: layout.pending)
        report.movedSupport = true
        log("moved \(old) to \(new)" + (early.isEmpty ? "" : ", what the window wrote first joined it: \(early.joined(separator: " "))"))
    }

    private static func appendLog(_ source: URL, to target: URL) throws {
        let data = try Data(contentsOf: source)
        guard FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) else {
            try data.write(to: target)
            return
        }
        let handle = try FileHandle(forWritingTo: target)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    /// Renames what the old name spelled inside the folder. A file already under its new
    /// name is newer and stays; the old one is then left as it is.
    static func renameInside(_ layout: Layout, report: inout Report) {
        let files = FileManager.default
        let root = layout.newSupport
        func move(_ from: URL, _ to: URL) {
            guard files.fileExists(atPath: from.path(percentEncoded: false)),
                !files.fileExists(atPath: to.path(percentEncoded: false)),
                (try? files.moveItem(at: from, to: to)) != nil
            else { return }
            report.renamed.append(String(from.path(percentEncoded: false).dropFirst(root.path(percentEncoded: false).count)))
        }
        for (from, to) in renamedFiles.sorted(by: { $0.key < $1.key }) {
            move(root.appending(path: from), root.appending(path: to))
        }
        for name in replacedFiles {
            let url = root.appending(path: name)
            if (try? files.removeItem(at: url)) != nil { report.removed.append(name) }
        }
        // Engines and bridges: the clean copies of the files the bridge patches.
        for folder in ["runners", "bridges"] {
            let base = root.appending(path: folder)
            guard let walk = files.enumerator(at: base, includingPropertiesForKeys: nil, options: []) else { continue }
            for case let url as URL in walk {
                let name = url.lastPathComponent
                guard let (from, to) = renamedSuffixes.first(where: { name.hasSuffix($0.key) }) else { continue }
                move(url, url.deletingLastPathComponent().appending(path: String(name.dropLast(from.count)) + to))
            }
        }
        let launchers = root.appending(path: "launchers")
        for app in (try? files.contentsOfDirectory(at: launchers, includingPropertiesForKeys: nil)) ?? [] {
            for (from, to) in renamedLauncherFiles {
                move(app.appending(path: from), app.appending(path: to))
            }
        }
    }

    /// Every installed engine gets its env file under the new name, with the new paths;
    /// the old file goes. Returns the engines written.
    static func rewriteEngineFiles(_ layout: Layout) throws -> [String] {
        let files = FileManager.default
        let runners = layout.newSupport.appending(path: "runners")
        var written: [String] = []
        for entry in (try? files.contentsOfDirectory(at: runners, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? [] {
            if (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { continue }
            let old = entry.appending(path: "\(oldName)-engine.env")
            // The file holds the real directory's paths (writeEnvironmentFile), so compare with those.
            let engine = DormisonEngine(root: entry.resolvingSymlinksInPath())
            let current = entry.appending(path: DormisonEngine.envFileName)
            let wanted = engine.isUsable ? engine.environmentFile : nil
            if let wanted, (try? String(contentsOf: current, encoding: .utf8)) != wanted {
                try engine.writeEnvironmentFile()
                written.append(entry.lastPathComponent)
            }
            if files.fileExists(atPath: old.path(percentEncoded: false)), wanted != nil {
                try files.removeItem(at: old)
            }
        }
        return written
    }

    /// The run script's markers in every library's compatdata.
    static func renameMarkers(_ layout: Layout, report: inout Report) {
        let files = FileManager.default
        for root in layout.library.roots {
            let compat = root.appending(path: "steamapps/compatdata")
            for game in (try? files.contentsOfDirectory(at: compat, includingPropertiesForKeys: nil)) ?? [] {
                for (from, to) in renamedMarkers {
                    let source = game.appending(path: from), target = game.appending(path: to)
                    guard files.fileExists(atPath: source.path(percentEncoded: false)),
                        !files.fileExists(atPath: target.path(percentEncoded: false)),
                        (try? files.moveItem(at: source, to: target)) != nil
                    else { continue }
                    report.renamed.append("\(game.lastPathComponent)/\(from)")
                }
            }
        }
    }

    /// The prefixes' env files again, from the moved settings: new header, new variable
    /// names, D3DMetal's path in the new folder. Nothing is written where nothing changed.
    static func materialize(_ layout: Layout, log: @escaping @Sendable (String) -> Void) throws {
        var service = SettingsService(
            store: SettingsStore(root: layout.newSupport.appending(path: "settings")),
            library: layout.library,
            cli: layout.newSupport.appending(path: "\(newName)-sevo").path(percentEncoded: false),
            gameIsRunning: { _ in false },
            engineVersion: { nil },
            log: { log("settings: \($0)") })
        service.d3dmetal = D3DMetalStore(root: layout.newSupport.appending(path: "d3dmetal"))
        try service.materialize(appID: nil)
    }

    /// Copies the preferences worth keeping that the new domain does not have yet.
    static func copyDefaults(from old: UserDefaults, to new: UserDefaults) -> [String] {
        var copied: [String] = []
        for (from, to) in defaultsKeys.sorted(by: { $0.key < $1.key }) {
            guard let value = old.object(forKey: from), new.object(forKey: to) == nil else { continue }
            new.set(value, forKey: to)
            copied.append(to)
        }
        return copied
    }

    // MARK: config.vdf

    /// The games' tool choice: `"name" "notproton"` inside a CompatToolMapping block
    /// becomes `"name" "lullaby"`. Other tools, other keys and everything outside the
    /// block stay byte for byte.
    static func rewriteToolMapping(_ text: String) -> (text: String, count: Int) {
        var lines = text.components(separatedBy: "\n")
        var depth = 0
        var mappingDepth: Int?
        var opensMapping = false
        var count = 0
        for index in lines.indices {
            let line = lines[index]
            let token = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if token == "{" {
                depth += 1
                if opensMapping { mappingDepth = depth }
                opensMapping = false
                continue
            }
            if token == "}" {
                if depth == mappingDepth { mappingDepth = nil }
                depth -= 1
                continue
            }
            opensMapping = token == "\"CompatToolMapping\""
            guard let mapping = mappingDepth, depth == mapping + 1,
                let match = line.firstMatch(of: /^(\s*"name"\s+")notproton("\s*)$/)
            else { continue }
            lines[index] = "\(match.1)\(newName)\(match.2)"
            count += 1
        }
        return (lines.joined(separator: "\n"), count)
    }

    /// Rewrites config.vdf when it names the old tool: a copy first (once, never over an
    /// earlier one), then the new text through a temporary file. Returns the games moved
    /// and whether the copy was made now.
    static func rewriteConfig(_ layout: Layout) throws -> (Int, Bool) {
        let files = FileManager.default
        let url = layout.configVDF
        let text = try String(contentsOf: url, encoding: .utf8)
        let (rewritten, count) = rewriteToolMapping(text)
        guard count > 0 else { return (0, false) }
        let backup = url.deletingLastPathComponent().appending(path: configBackupName)
        var madeBackup = false
        if !files.fileExists(atPath: backup.path(percentEncoded: false)) {
            try files.copyItem(at: url, to: backup)
            madeBackup = true
        }
        let temporary = url.deletingLastPathComponent().appending(path: "config.vdf.\(newName)-new")
        try rewritten.write(to: temporary, atomically: false, encoding: .utf8)
        if let mode = try? files.attributesOfItem(atPath: url.path(percentEncoded: false))[.posixPermissions] {
            try? files.setAttributes([.posixPermissions: mode], ofItemAtPath: temporary.path(percentEncoded: false))
        }
        _ = try files.replaceItemAt(url, withItemAt: temporary)
        return (count, madeBackup)
    }
}
