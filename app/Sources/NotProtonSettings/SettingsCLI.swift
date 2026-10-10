// notproton-settings: the one writer of the settings outside the app.
//
//   catalog                              the catalog as JSON (texts in en/uk/ru)
//   state [--app ID]                     a level's values as JSON
//   set [--app ID] SETTING VALUE         VALUE is JSON (true, "metalfx", 60, null = inherit)
//   reset [--app ID]                     every setting of the level back to inherit
//   launch --app ID --exe PROGRAM [--install DIR] [--prefix PFX]
//                                        compat_run.sh before a game starts: migrate, record
//                                        the executables, write the prefix's env files
//   materialize [--app ID]               rewrite the env files of one game or of all
//   migrate                              bring every pre-catalog prefix into the store
//   panel JSON                           one request of the Steam panel, answered as JSON
//   toolkit add PATH                     install D3DMetal from a Game Porting Toolkit image
//   toolkit list                         installed D3DMetal versions as JSON
//   app config APPID KEY VALUE           what Dormison's View menu runs through SEVO_CLI
//                                        (the `sevo app config` call; docs/ROADMAP.md §5.3)

import Foundation

public struct SettingsCLI {
    public var service: SettingsService

    public init(service: SettingsService = SettingsService()) {
        self.service = service
    }

    public struct Result: Equatable {
        public var status: Int32
        public var output: String
        public var error: String

        static func ok(_ output: String = "") -> Result { Result(status: 0, output: output, error: "") }
        static func fail(_ message: String, status: Int32 = 1) -> Result {
            Result(status: status, output: "", error: message)
        }
    }

    /// A CLI over a support directory and a Steam directory other than the user's, for
    /// tests and checks: `--support DIR --steam DIR` ahead of the command.
    public static func configured(_ arguments: [String]) -> (SettingsCLI, [String]) {
        var rest = arguments
        var service = SettingsService()
        let probe = SettingsCLI(service: service)
        if let support = try? probe.option("--support", &rest) {
            let root = URL(filePath: support)
            service.store = SettingsStore(root: root.appending(path: "settings"))
            service.d3dmetal = D3DMetalStore(root: root.appending(path: "d3dmetal"))
            service.cli = root.appending(path: "notproton-sevo").path(percentEncoded: false)
            service.log = { _ in }
            service.engineVersion = { nil }
        }
        if let steam = try? probe.option("--steam", &rest) {
            service.library = .standard(steam: URL(filePath: steam))
        }
        return (SettingsCLI(service: service), rest)
    }

    public func run(_ arguments: [String]) -> Result {
        do {
            return try dispatch(arguments)
        } catch let error as SettingsError {
            return .fail("notproton-settings: \(error)", status: { if case .usage = error { 2 } else { 1 } }())
        } catch {
            return .fail("notproton-settings: \(error.localizedDescription)")
        }
    }

    func dispatch(_ arguments: [String]) throws -> Result {
        guard let command = arguments.first else { throw SettingsError.usage(Self.usage) }
        var rest = Array(arguments.dropFirst())
        if command != "catalog" { try service.upgradeIfNeeded() }
        switch command {
        case "catalog":
            return .ok(service.catalogJSON().text)
        case "state":
            let app = try option("--app", &rest).map(appID)
            if let app { try service.prepare(appID: app) }
            return .ok(service.stateJSON(appID: app).text)
        case "set":
            let app = try option("--app", &rest).map(appID)
            guard rest.count == 2 else { throw SettingsError.usage("set [--app ID] SETTING VALUE") }
            let value = try JSONValue.parse(rest[1])
            try service.set(rest[0], value == .null ? nil : value, appID: app)
            return .ok(service.stateJSON(appID: app).text)
        case "reset":
            let app = try option("--app", &rest).map(appID)
            try service.reset(appID: app)
            return .ok(service.stateJSON(appID: app).text)
        case "launch":
            guard let app = try option("--app", &rest).map(appID) else {
                throw SettingsError.usage("launch --app ID --exe PROGRAM [--install DIR] [--prefix PFX]")
            }
            let exe = try option("--exe", &rest)
            let install = try option("--install", &rest).map { URL(filePath: $0) }
            let prefix = try option("--prefix", &rest).map { URL(filePath: $0) }
            try service.record(appID: app, exe: exe, installDirectory: install)
            if let prefix {
                try service.materialize(appID: app, prefix: prefix)
            } else {
                try service.materialize(appID: app)
            }
            return .ok()
        case "materialize":
            let app = try option("--app", &rest).map(appID)
            try service.materialize(appID: app)
            return .ok()
        case "migrate":
            let migrated = try service.migrateAll()
            return .ok(migrated.map(String.init).joined(separator: "\n"))
        case "panel":
            guard rest.count == 1 else { throw SettingsError.usage("panel JSON") }
            return .ok(panel(rest[0]).text)
        case "app":
            return try sevoAppConfig(rest)
        case "toolkit":
            return try toolkit(rest)
        default:
            throw SettingsError.usage(Self.usage)
        }
    }

    // MARK: - The Steam panel

    /// One request of the panel: `{"op": "catalog" | "state" | "set" | "reset",
    /// "app": ID?, "id": SETTING, "value": JSON}`. Always answers an object with "ok".
    public func panel(_ request: String) -> JSONValue {
        do {
            guard let object = try JSONValue.parse(request).object, let op = object["op"]?.string else {
                throw SettingsError.usage("a request is an object with op")
            }
            let app: Int? = try object["app"].flatMap { value in
                if value == .null { return nil }
                guard let n = value.number ?? value.string.flatMap({ Int($0) }), n > 0 else {
                    throw SettingsError.usage("app is an app id")
                }
                return n
            }
            if op != "catalog" { try service.upgradeIfNeeded() }
            switch op {
            case "catalog":
                return .object(["ok": .bool(true), "catalog": service.catalogJSON()])
            case "state":
                if let app { try service.prepare(appID: app) }
            case "set":
                guard let id = object["id"]?.string else { throw SettingsError.usage("set needs id") }
                let value = object["value"].flatMap { $0 == .null ? nil : $0 }
                try service.set(id, value, appID: app)
            case "reset":
                try service.reset(appID: app)
            default:
                throw SettingsError.usage("unknown op \(op)")
            }
            return .object(["ok": .bool(true), "state": service.stateJSON(appID: app)])
        } catch {
            return .object(["ok": .bool(false), "error": .string("\(error)")])
        }
    }

    // MARK: - D3DMetal

    func toolkit(_ arguments: [String]) throws -> Result {
        let store = service.d3dmetal
        switch arguments.first {
        case "add":
            guard arguments.count == 2 else { throw SettingsError.usage("toolkit add PATH") }
            return .ok(try install(URL(filePath: arguments[1])).text)
        case "list":
            return .ok(store.stateJSON().text)
        default:
            throw SettingsError.usage("toolkit add PATH | list")
        }
    }

    /// Installs, records the outcome for the panel, and rewrites every prefix so bottle.env
    /// names the version games get.
    func install(_ source: URL) throws -> JSONValue {
        let store = service.d3dmetal
        store.setStatus(.object(["state": .string("installing"), "source": .string(source.lastPathComponent)]))
        do {
            let toolkit = try store.install(from: source)
            service.log("d3dmetal: installed \(toolkit.version) from \(source.path(percentEncoded: false))")
            var status: [String: JSONValue] = ["state": .string("installed"), "version": .string(toolkit.version)]
            if toolkit.requiredMacOS > store.macOS { status["requires"] = .number(toolkit.requiredMacOS) }
            store.setStatus(.object(status))
            try service.materialize(appID: nil)
            return store.stateJSON()
        } catch {
            store.setStatus(.object(["state": .string("failed"), "error": .string("\(error)")]))
            service.log("d3dmetal: install from \(source.path(percentEncoded: false)) failed: \(error)")
            throw error
        }
    }

    // MARK: - Dormison's View menu

    /// `app config <appid> <key> <value>`, as winemac.drv's `sevoStoreSetting:` runs it:
    /// upscaler and filter by name, windows by level name. fps and fps-graph switch
    /// Dormison's own counter, which is no NotProton setting since Amendment 09.10 (the
    /// panel's counter is the Metal HUD): the switch lasts the session and is not kept.
    func sevoAppConfig(_ arguments: [String]) throws -> Result {
        guard arguments.count == 4, arguments[0] == "config" else {
            throw SettingsError.usage("app config APPID KEY VALUE")
        }
        let app = try appID(arguments[1])
        let value = arguments[3].lowercased()
        let onOff: (String) throws -> JSONValue = { word in
            switch word {
            case "on", "1", "true": return .bool(true)
            case "off", "0", "false": return .bool(false)
            default: throw SettingsError.invalidValue(arguments[2], word)
            }
        }
        switch arguments[2] {
        case "upscaler":
            // A shader package this engine does not ship cannot be stored.
            guard UpscalerChoice(rawValue: value) != nil else { throw SettingsError.invalidValue("upscaler", value) }
            try service.set("upscaler", .string(value), appID: app)
        case "filter": try service.set("filter", .string(value), appID: app)
        case "fps", "fps-graph":
            _ = try onOff(value)
            service.log("app \(app): View menu \(arguments[2])=\(value) not kept (Dormison's counter)")
        case "windows": try service.set("windows", .string(WindowTreatment(option: value).rawValue), appID: app)
        default: throw SettingsError.unknownSetting(arguments[2])
        }
        return .ok()
    }

    // MARK: - Arguments

    func appID(_ text: String) throws -> Int {
        guard let id = Int(text), id > 0 else { throw SettingsError.usage("\(text) is not an app id") }
        return id
    }

    /// Removes `--name VALUE` from `arguments`, answering VALUE.
    func option(_ name: String, _ arguments: inout [String]) throws -> String? {
        guard let index = arguments.firstIndex(of: name) else { return nil }
        guard index + 1 < arguments.count else { throw SettingsError.usage("\(name) needs a value") }
        let value = arguments[index + 1]
        arguments.removeSubrange(index...(index + 1))
        return value
    }

    static let usage = """
        usage: notproton-settings catalog | state [--app ID] | set [--app ID] SETTING JSON | reset [--app ID]
               | launch --app ID --exe PROGRAM [--install DIR] [--prefix PFX] | materialize [--app ID]
               | migrate | panel JSON | app config APPID KEY VALUE | toolkit …
        """
}
