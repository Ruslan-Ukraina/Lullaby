// Every operation on the settings, for the CLI the Steam panel and the View menu call
// and for the app: read the catalog and a level's state, set or reset a value,
// record a game's executables, and write the env files of the prefixes it touches.

import Foundation

public struct SettingsService: Sendable {
    public var store: SettingsStore
    public var library: GameLibrary
    /// What SEVO_CLI names in bottle.env.
    public var cli: String?
    /// Whether the game runs now (its bundle's wine is a process).
    public var gameIsRunning: @Sendable (Int) -> Bool
    /// The engine's version for the panel's header, e.g. "dormison-b1".
    public var engineVersion: @Sendable () -> String?
    public var log: @Sendable (String) -> Void

    public init(
        store: SettingsStore = .standard, library: GameLibrary = .standard(),
        cli: String? = SettingsPaths.sevoStub.path(percentEncoded: false),
        gameIsRunning: @escaping @Sendable (Int) -> Bool = SettingsService.processCheck,
        engineVersion: @escaping @Sendable () -> String? = SettingsService.currentEngine,
        log: @escaping @Sendable (String) -> Void = SettingsService.fileLog
    ) {
        self.store = store
        self.library = library
        self.cli = cli
        self.gameIsRunning = gameIsRunning
        self.engineVersion = engineVersion
        self.log = log
    }

    // MARK: - Reading

    public func catalogJSON() -> JSONValue {
        func control(_ setting: Setting) -> JSONValue {
            func choices(_ list: [SettingChoice]) -> JSONValue {
                .array(list.map { .object(["value": $0.value, "label": $0.label.json]) })
            }
            switch setting.control {
            case .toggle: return .object(["kind": .string("toggle")])
            case let .choice(list): return .object(["kind": .string("choice"), "choices": choices(list)])
            case let .limit(list, range):
                return .object([
                    "kind": .string("limit"), "choices": choices(list),
                    "min": .number(range.lowerBound), "max": .number(range.upperBound),
                ])
            case let .tuning(list):
                return .object([
                    "kind": .string("tuning"), "choices": choices(list),
                    "min": .number(TuningParameters.spinRange.lowerBound),
                    "max": .number(TuningParameters.spinRange.upperBound),
                ])
            case let .gpu(list): return .object(["kind": .string("gpu"), "choices": choices(list)])
            case let .dllOverrides(list): return .object(["kind": .string("dllOverrides"), "choices": choices(list)])
            case .environment: return .object(["kind": .string("environment")])
            }
        }
        let settings: [JSONValue] = SettingCatalog.all.map { setting in
            var help: [String: JSONValue] = [
                "summary": setting.copy.help.summary.json,
                "entries": .array(setting.copy.help.entries.map {
                    .object(["name": $0.name.json, "text": $0.text.json])
                }),
            ]
            if let footnote = setting.copy.help.footnote { help["footnote"] = footnote.json }
            var object: [String: JSONValue] = [
                "id": .string(setting.id.rawValue),
                "group": .string(setting.group.rawValue),
                "levels": .array(SettingLevel.allCases.filter(setting.levels.contains).map { .string($0.rawValue) }),
                "experimental": .bool(setting.experimental),
                "title": setting.copy.title.json,
                "help": .object(help),
                "control": control(setting),
            ]
            if let quick = setting.quick { object["quick"] = .number(quick) }
            if let caption = setting.copy.caption { object["caption"] = caption.json }
            return .object(object)
        }
        return .object([
            "version": .number(1),
            "groups": .array(SettingGroup.allCases.map {
                .object(["id": .string($0.rawValue), "title": GroupTitles.title($0).json])
            }),
            "settings": .array(settings),
            "text": .object(PanelText.all.mapValues(\.json)),
        ])
    }

    /// What the game's page needs before it shows its state: its prefixes from before the
    /// catalog migrated, and the executables its install directory holds recorded (with
    /// their env files written), so a setting reaches every one of them from the start.
    public func prepare(appID: Int) throws {
        for prefix in library.prefixes(of: appID) where ConfigMigration.needsMigration(prefix: prefix) {
            try materialize(appID: appID, prefix: prefix)
        }
        if try !record(appID: appID, exe: nil, installDirectory: nil).isEmpty {
            try materialize(appID: appID)
        }
    }

    /// One level's values: its own, what it inherits and from where, and what applies.
    public func stateJSON(appID: Int?) -> JSONValue {
        let global = store.global()
        let game = appID.map(store.game) ?? .empty
        let stack = ConfigStack(global: global, game: game)
        var values: [String: JSONValue] = [:]
        for setting in SettingCatalog.all {
            let level: SettingLevel = appID == nil ? .global : .game
            guard setting.levels.contains(level) else { continue }
            let own = setting.read(appID == nil ? global : game)
            let parent = appID == nil ? ConfigStack(global: .empty) : stack.globalOnly
            let inherited = setting.resolved(parent)
            let inheritedFrom: ConfigLevel =
                appID != nil && setting.read(global) != nil ? .global : .defaults
            values[setting.id.rawValue] = .object([
                "own": own ?? .null,
                "inherited": inherited,
                "inheritedFrom": .string(inheritedFrom.rawValue),
                "inheritedLabel": setting.label(of: inherited).json,
                "effective": setting.resolved(stack),
            ])
        }
        var object: [String: JSONValue] = [
            "level": .string(appID == nil ? "global" : "game"),
            "values": .object(values),
        ]
        if let engine = engineVersion() { object["engine"] = .string(engine) }
        if let appID {
            let exes = game.exes ?? []
            let running = gameIsRunning(appID)
            let hasPrefix = !library.prefixes(of: appID).isEmpty
            object["appID"] = .number(appID)
            object["exes"] = .array(exes.map(JSONValue.string))
            object["running"] = .bool(running)
            object["prefix"] = .bool(hasPrefix)
            object["status"] = .string(running ? "restartGame" : (exes.isEmpty || !hasPrefix) ? "firstLaunch" : "nextLaunch")
            if let name = game.name ?? library.installed(appID)?.name { object["name"] = .string(name) }
        }
        return .object(object)
    }

    // MARK: - Changing

    /// Sets one setting at a level (`appID` nil: for all games); nil or JSON null inherits.
    public func set(_ id: String, _ value: JSONValue?, appID: Int?) throws {
        guard let setting = SettingCatalog.setting(named: id) else { throw SettingsError.unknownSetting(id) }
        guard setting.levels.contains(appID == nil ? .global : .game) else { throw SettingsError.wrongLevel(id) }
        if let appID {
            try store.updateGame(appID) { values in
                try setting.write(&values, value)
                if values.name == nil, let name = library.installed(appID)?.name { values.name = name }
            }
            log("set app \(appID) \(setting.id.rawValue)=\(value?.text ?? "inherit")")
        } else {
            try store.updateGlobal { try setting.write(&$0, value) }
            log("set global \(setting.id.rawValue)=\(value?.text ?? "inherit")")
        }
        try materialize(appID: appID)
    }

    /// Every setting of a level back to inherit; a game keeps its executables.
    public func reset(appID: Int?) throws {
        if let appID {
            try store.updateGame(appID) { values in
                var kept = ConfigValues()
                kept.exes = values.exes
                kept.name = values.name
                values = kept
            }
            log("reset app \(appID)")
        } else {
            try store.updateGlobal { $0 = .empty }
            log("reset global")
        }
        try materialize(appID: appID)
    }

    /// Notes executables of a game: the one being launched and the ones its install
    /// directory holds. Answers the names that were new.
    @discardableResult
    public func record(appID: Int, exe: String?, installDirectory: URL?) throws -> [String] {
        var found: [String] = []
        if let exe, let name = GameExecutables.recordable(exe) { found.append(name) }
        let installed = library.installed(appID)
        if let directory = installDirectory ?? installed?.directory {
            found += GameExecutables.scan(directory)
        }
        var added: [String] = []
        try store.updateGame(appID) { values in
            let known = values.exes ?? []
            added = Array(NSOrderedSet(array: found.filter { !known.contains($0) })) as? [String] ?? []
            if !added.isEmpty { values.exes = known + added }
            if values.name == nil, let name = installed?.name { values.name = name }
        }
        if !added.isEmpty { log("app \(appID): recorded \(added.joined(separator: ", "))") }
        return added
    }

    // MARK: - Files

    /// Writes the prefixes a change at this level reaches: the game's, or every
    /// NotProton prefix for the shared level.
    public func materialize(appID: Int?) throws {
        if let appID {
            for prefix in library.prefixes(of: appID) { try materialize(appID: appID, prefix: prefix) }
        } else {
            for (id, prefix) in library.allPrefixes() { try materialize(appID: id, prefix: prefix) }
        }
    }

    /// One prefix. A prefix written before the catalog gives its values to the store first.
    public func materialize(appID: Int, prefix: URL) throws {
        if ConfigMigration.needsMigration(prefix: prefix) {
            ConfigMigration.backUp(prefix: prefix)
            let old = ConfigMigration.values(fromPrefix: prefix)
            try store.updateGame(appID) { values in
                values = ConfigMigration.merge(old, under: values)
                if values.name == nil, let name = library.installed(appID)?.name { values.name = name }
            }
            log("app \(appID): migrated \(prefix.path(percentEncoded: false)) \(JSONValue.encode(old).text)")
        }
        let outcome = try store.locked {
            try ConfigMaterializer.write(prefix: prefix, appID: appID, stack: store.stack(for: appID), cli: cli)
        }
        if !outcome.written.isEmpty || !outcome.removed.isEmpty {
            log("app \(appID): wrote \((outcome.written + outcome.removed.map { "-" + $0 }).joined(separator: " "))")
        }
    }

    /// Every NotProton prefix written before the catalog, migrated and rewritten.
    public func migrateAll() throws -> [Int] {
        var migrated: [Int] = []
        for (id, prefix) in library.allPrefixes() where ConfigMigration.needsMigration(prefix: prefix) {
            try materialize(appID: id, prefix: prefix)
            migrated.append(id)
        }
        return migrated
    }

    // MARK: - Defaults for the real system

    public static let processCheck: @Sendable (Int) -> Bool = { appID in
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/pgrep")
        let fragment = SettingsPaths.launchers.appending(path: "app-\(appID)/").path(percentEncoded: false)
        process.arguments = ["-f", NSRegularExpression.escapedPattern(for: fragment)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    public static let currentEngine: @Sendable () -> String? = {
        let info = SettingsPaths.support.appending(path: "runners/current/engine-info.json")
        guard let data = try? Data(contentsOf: info),
            let object = try? JSONDecoder().decode(JSONValue.self, from: data).object
        else { return nil }
        return object["version"]?.string
    }

    public static let fileLog: @Sendable (String) -> Void = { line in
        let url = SettingsPaths.support.appending(path: "notproton-settings.log")
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        let text = "\(formatter.string(from: Date())) \(line)\n"
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
    }
}
