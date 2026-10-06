// Per-game Dormison settings. Dormison reads <prefix>/.sevo/bottle.env and then
// <prefix>/.sevo/apps/<program>.env at every process start, so these two files
// are the only source of truth: the settings window edits the game's file, the
// View menu's stand-in (compat_run.sh) writes to the same one.

import Foundation

enum WindowMode: String, CaseIterable, Sendable {
    case off, fixed, window, all
}

enum UpscalerChoice: String, CaseIterable, Sendable {
    case off, lanczos, metalfx
}

enum FinalFilter: String, CaseIterable, Sendable {
    case nearest, bilinear, lanczos
}

/// One level of settings. A nil value is "not set here": the level above decides.
struct GameSettings: Equatable, Sendable {
    var windows: WindowMode?
    var upscaler: UpscalerChoice?
    var filter: FinalFilter?
    var fps: Bool?
    var fpsGraph: Bool?
    var linearMouse: Bool?
    var cursorConfine: Bool?
    /// 0 is every processor.
    var cpuCount: Int?

    static let empty = GameSettings()

    /// What NotProton writes into a new bottle.env.
    static let profile = GameSettings(
        windows: .fixed, upscaler: .off, filter: .lanczos, fps: false, fpsGraph: false,
        linearMouse: false, cursorConfine: false, cpuCount: nil)

    init(
        windows: WindowMode? = nil, upscaler: UpscalerChoice? = nil, filter: FinalFilter? = nil,
        fps: Bool? = nil, fpsGraph: Bool? = nil, linearMouse: Bool? = nil,
        cursorConfine: Bool? = nil, cpuCount: Int? = nil
    ) {
        self.windows = windows
        self.upscaler = upscaler
        self.filter = filter
        self.fps = fps
        self.fpsGraph = fpsGraph
        self.linearMouse = linearMouse
        self.cursorConfine = cursorConfine
        self.cpuCount = cpuCount
    }

    init(env: [String: String]) {
        func flag(_ key: String) -> Bool? {
            guard let value = env[key], !value.isEmpty else { return nil }
            return ["1", "true", "yes", "on"].contains(value.lowercased())
        }
        self.init()
        if let value = env["SEVO_RESIZABLE_WINDOWS"], !value.isEmpty {
            // The engine reads the first letter; any true value is "fixed".
            let lower = value.lowercased()
            switch lower.first {
            case "a": windows = .all
            case "w": windows = .window
            case "f": windows = .fixed
            default: windows = ["1", "true", "yes", "on"].contains(lower) ? .fixed : .off
            }
        }
        upscaler = env["SEVO_UPSCALER"].flatMap { UpscalerChoice(rawValue: $0.lowercased()) }
        filter = env["SEVO_FINAL_FILTER"].flatMap { FinalFilter(rawValue: $0.lowercased()) }
        fps = flag("SEVO_FPS")
        fpsGraph = flag("SEVO_FPS_GRAPH")
        linearMouse = flag("SEVO_LINEAR_MOUSE")
        cursorConfine = flag("SEVO_CURSOR_CONFINE")
        cpuCount = env["SEVO_CPU_COUNT"].flatMap { Int($0) }.map { max(0, $0) }
    }

    /// The key/value pairs this level sets; a nil setting is a key to remove.
    var entries: [(key: String, value: String?)] {
        func flag(_ value: Bool?) -> String? { value.map { $0 ? "1" : "0" } }
        return [
            ("SEVO_RESIZABLE_WINDOWS", windows?.rawValue),
            ("SEVO_UPSCALER", upscaler?.rawValue),
            ("SEVO_FINAL_FILTER", filter?.rawValue),
            ("SEVO_FPS", flag(fps)),
            ("SEVO_FPS_GRAPH", flag(fpsGraph)),
            ("SEVO_LINEAR_MOUSE", flag(linearMouse)),
            ("SEVO_CURSOR_CONFINE", flag(cursorConfine)),
            ("SEVO_CPU_COUNT", cpuCount.map(String.init)),
        ]
    }

    /// `self` on top of `base`: what the engine ends up with.
    func resolved(over base: GameSettings) -> GameSettings {
        GameSettings(
            windows: windows ?? base.windows, upscaler: upscaler ?? base.upscaler,
            filter: filter ?? base.filter, fps: fps ?? base.fps,
            fpsGraph: fpsGraph ?? base.fpsGraph, linearMouse: linearMouse ?? base.linearMouse,
            cursorConfine: cursorConfine ?? base.cursorConfine, cpuCount: cpuCount ?? base.cpuCount)
    }
}

/// KEY=VALUE files as Dormison reads them: comments and keys nobody here owns
/// are kept as they are.
enum EnvFile {

    static func parse(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
            values[String(line[..<equals])] = String(line[line.index(after: equals)...])
        }
        return values
    }

    /// Sets each key, or removes it when the value is nil. Order and unrelated
    /// lines stay.
    static func apply(_ entries: [(key: String, value: String?)], to text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        for (key, value) in entries {
            let index = lines.firstIndex {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix(key + "=")
            }
            switch (index, value) {
            case let (index?, value?): lines[index] = "\(key)=\(value)"
            case let (index?, nil): lines.remove(at: index)
            case let (nil, value?): lines.append("\(key)=\(value)")
            case (nil, nil): break
            }
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }
}

enum GameSettingsStore {

    struct Loaded: Equatable, Sendable {
        let program: String
        let bottle: GameSettings
        let game: GameSettings
        var effective: GameSettings { game.resolved(over: bottle) }
    }

    static func sevo(_ prefix: WinePrefix) -> URL { prefix.pfx.appending(path: ".sevo") }

    static func gameFile(_ prefix: WinePrefix, program: String) -> URL {
        sevo(prefix).appending(path: "apps/\(program).env")
    }

    /// The program the run script last launched in this prefix, lowercase.
    static func program(of prefix: WinePrefix) -> String? {
        let text = try? String(contentsOf: sevo(prefix).appending(path: "game-exe"), encoding: .utf8)
        guard let name = text?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
            !name.contains("/")
        else { return nil }
        return name
    }

    /// nil until the game has been launched once: before that there is no program name.
    static func load(_ prefix: WinePrefix) -> Loaded? {
        guard let program = program(of: prefix) else { return nil }
        func read(_ url: URL) -> GameSettings {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return GameSettings(env: EnvFile.parse(text))
        }
        return Loaded(
            program: program, bottle: read(sevo(prefix).appending(path: "bottle.env")),
            game: read(gameFile(prefix, program: program)))
    }

    static func save(_ settings: GameSettings, for prefix: WinePrefix, program: String) throws {
        let file = gameFile(prefix, program: program)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let old = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let new = EnvFile.apply(settings.entries, to: old)
        try new.write(to: file, atomically: true, encoding: .utf8)
    }

    // msync+ stays on. The one way off is a per-game debugging marker that the
    // run script reads when no launch option sets WINEMSYNC.
    static func msyncMarker(_ prefix: WinePrefix) -> URL { prefix.root.appending(path: "notproton-msync") }

    static func msyncEnabled(_ prefix: WinePrefix) -> Bool {
        let text = try? String(contentsOf: msyncMarker(prefix), encoding: .utf8)
        return text?.trimmingCharacters(in: .whitespacesAndNewlines) != "0"
    }

    static func setMsync(_ on: Bool, for prefix: WinePrefix) throws {
        try (on ? "1" : "0").write(to: msyncMarker(prefix), atomically: true, encoding: .utf8)
    }
}
