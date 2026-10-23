// Where the levels live: JSON files under ~/Library/Application Support/lullaby/settings,
// `global.json` for every game and `games/<appid>.json` per game. They are the source of
// truth; the env files Dormison reads are derived from them (ConfigMaterializer).
//
// Three writers can meet here: the Steam panel, the View menu of a running game and the
// run script recording an executable. A change is a read-modify-write under an
// exclusive flock on `settings/.lock`, so none of them loses another's value.

import Foundation

public struct SettingsStore: Sendable {
    public let root: URL
    /// The engine and Game Porting Toolkit versions the catalog's `needsEngine` and
    /// `notNeededFromGPTK` are measured against; nil for a part that is not there.
    public var versions: @Sendable () -> (engine: String?, gptk: String?) = {
        (SettingsService.currentEngine(), D3DMetalStore.standard.active()?.version)
    }

    public init(root: URL) {
        self.root = root
    }

    /// ~/Library/Application Support/lullaby/settings.
    public static var standard: SettingsStore {
        SettingsStore(root: SettingsPaths.support.appending(path: "settings"))
    }

    var globalURL: URL { root.appending(path: "global.json") }
    var gamesRoot: URL { root.appending(path: "games") }

    func gameURL(_ appID: Int) -> URL { gamesRoot.appending(path: "\(appID).json") }

    public func global() -> ConfigValues { read(globalURL) }

    public func game(_ appID: Int) -> ConfigValues { read(gameURL(appID)) }

    public func stack(for appID: Int?) -> ConfigStack {
        let own = appID.map(game) ?? .empty
        guard appID != nil else { return ConfigStack(global: global(), game: own) }
        // The signed catalog first, the built-in recipes when it has nothing for the game.
        if let fix = gameFix(appID: appID, exes: own.exes) {
            return ConfigStack(global: global(), recipe: fix.recipeValues, game: own, fixLines: fix.envLines())
        }
        let recipe = GameRecipes.recipe(appID: appID, exes: own.exes)
        return ConfigStack(global: global(), recipe: recipe?.values ?? .empty, game: own)
    }

    var catalogURL: URL { root.appending(path: "game-fixes.json") }

    /// The catalog's fix for a game; `unfit` and unverified entries are shown, never applied.
    public func gameFix(appID: Int?, exes: [String]?) -> GameFix? {
        guard let fix = GameFixCatalog.load(from: catalogURL)?
            .resolve(appID: appID, exes: exes, engine: versions().engine, gptk: versions().gptk)?.fix,
            fix.verdict == .fits, fix.verifiedOn != nil else { return nil }
        return fix
    }

    /// Every game with a file, by app id.
    public func games() -> [Int: ConfigValues] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: gamesRoot, includingPropertiesForKeys: nil)) ?? []
        var result: [Int: ConfigValues] = [:]
        for url in entries where url.pathExtension == "json" {
            guard let id = Int(url.deletingPathExtension().lastPathComponent), id > 0 else { continue }
            result[id] = read(url)
        }
        return result
    }

    public func setGlobal(_ values: ConfigValues) throws {
        try write(values, to: globalURL)
    }

    /// Stores a game's level; an empty one (no settings, no executables) removes the file.
    public func setGame(_ appID: Int, _ values: ConfigValues) throws {
        let url = gameURL(appID)
        if values == .empty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try write(values, to: url)
    }

    /// Runs `body` holding the store's lock.
    public func locked<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appending(path: ".lock").path(percentEncoded: false)
        let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw SettingsError.storage("cannot open \(path)") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw SettingsError.storage("cannot lock \(path)") }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    public func updateGame(_ appID: Int, _ change: (inout ConfigValues) throws -> Void) throws {
        try locked {
            var values = game(appID)
            try change(&values)
            try setGame(appID, values)
        }
    }

    public func updateGlobal(_ change: (inout ConfigValues) throws -> Void) throws {
        try locked {
            var values = global()
            try change(&values)
            try setGlobal(values)
        }
    }

    // MARK: - Schema

    /// The store's shape: 1 before Amendment 09.10, 2 since (ConfigMigration.upgradeStore).
    public static let schema = 2

    var schemaURL: URL { root.appending(path: "schema") }

    /// A store with no schema file is the first one.
    public var schema: Int {
        guard let text = try? String(contentsOf: schemaURL, encoding: .utf8) else { return 1 }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1
    }

    func setSchema(_ version: Int) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "\(version)\n".write(to: schemaURL, atomically: true, encoding: .utf8)
    }

    /// A level's file as it stands, keys no setting knows any more included.
    func rawObject(_ url: URL) -> [String: JSONValue]? {
        guard let data = try? Data(contentsOf: url),
            let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return nil }
        return value.object
    }

    /// Copies global.json and games/ into `name`, once.
    func backUp(into name: String) throws {
        let manager = FileManager.default
        let backup = root.appending(path: name)
        guard !manager.fileExists(atPath: backup.path(percentEncoded: false)) else { return }
        try manager.createDirectory(at: backup, withIntermediateDirectories: true)
        if manager.fileExists(atPath: globalURL.path(percentEncoded: false)) {
            try manager.copyItem(at: globalURL, to: backup.appending(path: "global.json"))
        }
        if manager.fileExists(atPath: gamesRoot.path(percentEncoded: false)) {
            try manager.copyItem(at: gamesRoot, to: backup.appending(path: "games"))
        }
    }

    private func read(_ url: URL) -> ConfigValues {
        guard let data = try? Data(contentsOf: url),
            let values = try? JSONDecoder().decode(ConfigValues.self, from: data)
        else { return .empty }
        return values
    }

    private func write(_ values: ConfigValues, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(values).write(to: url, options: .atomic)
    }
}

public enum SettingsError: Error, Equatable, CustomStringConvertible {
    case unknownSetting(String)
    case wrongLevel(String)
    case invalidValue(String, String)
    case reservedVariable(String)
    case d3dmetalMissing
    case storage(String)
    case usage(String)

    public var description: String {
        switch self {
        case let .unknownSetting(id): "unknown setting \(id)"
        case let .wrongLevel(id): "\(id) cannot be set at this level"
        case let .invalidValue(id, value): "\(value) is not a value of \(id)"
        case let .reservedVariable(key): "\(key) is set by Lullaby and cannot be set here"
        case .d3dmetalMissing: "D3DMetal is not installed: add Apple's Game Porting Toolkit first"
        case let .storage(what): what
        case let .usage(what): what
        }
    }
}

/// Paths the settings code shares with the app and the run script. The app's own
/// SupportPaths names the same directory.
public enum SettingsPaths {
    public static var home: URL { URL(filePath: NSHomeDirectory()) }

    public static var support: URL {
        home.appending(path: "Library/Application Support/lullaby")
    }

    /// The CLI the installer places next to the other helpers; Dormison's View menu
    /// calls it through SEVO_CLI.
    public static var cli: URL { support.appending(path: "lullaby-settings") }

    /// The shell stand-in compat_run.sh writes and names in SEVO_CLI (S1); it hands
    /// every call to `cli`.
    public static var sevoStub: URL { support.appending(path: "lullaby-sevo") }

    public static var launchers: URL { support.appending(path: "launchers") }

    public static var steamUserData: URL {
        home.appending(path: "Library/Application Support/Steam")
    }
}
