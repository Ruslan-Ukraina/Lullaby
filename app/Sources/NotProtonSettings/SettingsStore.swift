// Where the levels live: JSON files under ~/Library/Application Support/notproton/settings,
// `global.json` for every game and `games/<appid>.json` per game. They are the source of
// truth; the env files Dormison reads are derived from them (ConfigMaterializer).
//
// Three writers can meet here: the Steam panel, the View menu of a running game and the
// run script recording an executable. A change is a read-modify-write under an
// exclusive flock on `settings/.lock`, so none of them loses another's value.

import Foundation

public struct SettingsStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// ~/Library/Application Support/notproton/settings.
    public static var standard: SettingsStore {
        SettingsStore(root: SettingsPaths.support.appending(path: "settings"))
    }

    var globalURL: URL { root.appending(path: "global.json") }
    var gamesRoot: URL { root.appending(path: "games") }

    func gameURL(_ appID: Int) -> URL { gamesRoot.appending(path: "\(appID).json") }

    public func global() -> ConfigValues { read(globalURL) }

    public func game(_ appID: Int) -> ConfigValues { read(gameURL(appID)) }

    public func stack(for appID: Int?) -> ConfigStack {
        ConfigStack(global: global(), game: appID.map(game) ?? .empty)
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
    case storage(String)
    case usage(String)

    public var description: String {
        switch self {
        case let .unknownSetting(id): "unknown setting \(id)"
        case let .wrongLevel(id): "\(id) cannot be set at this level"
        case let .invalidValue(id, value): "\(value) is not a value of \(id)"
        case let .reservedVariable(key): "\(key) is set by NotProton and cannot be set here"
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
        home.appending(path: "Library/Application Support/notproton")
    }

    /// The CLI the installer places next to the other helpers; Dormison's View menu
    /// calls it through SEVO_CLI.
    public static var cli: URL { support.appending(path: "notproton-settings") }

    /// The shell stand-in compat_run.sh writes and names in SEVO_CLI (S1); it hands
    /// every call to `cli`.
    public static var sevoStub: URL { support.appending(path: "notproton-sevo") }

    public static var launchers: URL { support.appending(path: "launchers") }

    public static var steamUserData: URL {
        home.appending(path: "Library/Application Support/Steam")
    }
}
