// Brings the settings NotProton kept before the catalog into the store, without
// losing a value the player chose (docs/ROADMAP.md §4, "Миграция").
//
// Before Phase 7A a prefix's files were the source of truth:
// - `.sevo/bottle.env`, written once by compat_run.sh with NotProton's profile, and
//   by the player's hand after that;
// - `.sevo/apps/<exe>.env`, written by the Game Settings window and the View menu's
//   stand-in, plus the run script's SEVO_LOADER;
// - `<compatdata>/notproton-msync`, the msync+ debugging marker.
// A prefix whose bottle.env lacks the catalog's header has not been migrated. Each
// one is per game, so everything it holds that differs from the old profile is that
// game's own choice. Values already in the store win: they are newer.

import Foundation

public enum ConfigMigration {
    /// What compat_run.sh wrote into a new bottle.env before the catalog.
    static let oldProfile: [String: String] = [
        "SEVO_RESIZABLE_WINDOWS": "1", "SEVO_UPSCALER": "off", "SEVO_FINAL_FILTER": "lanczos",
        "SEVO_FPS": "0", "SEVO_FPS_GRAPH": "0", "SEVO_LINEAR_MOUSE": "0", "SEVO_CURSOR_CONFINE": "0",
    ]

    /// Keys the run script owned, never the player's.
    static let scriptKeys: Set<String> = ["WINEMSYNC", "SEVO_CLI", "SEVO_LOADER"]

    public static func needsMigration(prefix: URL) -> Bool {
        let bottle = prefix.appending(path: ".sevo/bottle.env")
        guard let text = try? String(contentsOf: bottle, encoding: .utf8) else {
            // No bottle.env but program files: an old prefix all the same.
            let apps = prefix.appending(path: ".sevo/apps")
            return ((try? FileManager.default.contentsOfDirectory(atPath: apps.path(percentEncoded: false))) ?? [])
                .contains { $0.hasSuffix(".env") }
        }
        return !text.hasPrefix(ConfigMaterializer.header)
    }

    static let backupName = "pre-catalog-backup"

    /// Copies the old files next to them, once, before they are rewritten:
    /// `.sevo/pre-catalog-backup/` (Dormison reads no subdirectory but `apps`).
    public static func backUp(prefix: URL) {
        let sevo = prefix.appending(path: ".sevo")
        let backup = sevo.appending(path: backupName)
        let manager = FileManager.default
        guard !manager.fileExists(atPath: backup.path(percentEncoded: false)) else { return }
        try? manager.createDirectory(at: backup.appending(path: "apps"), withIntermediateDirectories: true)
        try? manager.copyItem(at: sevo.appending(path: "bottle.env"), to: backup.appending(path: "bottle.env"))
        let apps = sevo.appending(path: "apps")
        for name in (try? manager.contentsOfDirectory(atPath: apps.path(percentEncoded: false))) ?? []
        where name.hasSuffix(".env") {
            try? manager.copyItem(at: apps.appending(path: name), to: backup.appending(path: "apps/\(name)"))
        }
        let marker = prefix.deletingLastPathComponent().appending(path: "notproton-msync")
        try? manager.copyItem(at: marker, to: backup.appending(path: "notproton-msync"))
    }

    /// The values a prefix's old files hold, as one game level.
    public static func values(fromPrefix prefix: URL) -> ConfigValues {
        let sevo = prefix.appending(path: ".sevo")
        var values = ConfigValues()
        var extra: [String] = []

        // The prefix's bottle.env: only what differs from the old profile was chosen.
        if let text = try? String(contentsOf: sevo.appending(path: "bottle.env"), encoding: .utf8),
            !text.hasPrefix(ConfigMaterializer.header)
        {
            let pairs = ConfigMaterializer.parse(text).filter { oldProfile[$0.key] != $0.value }
            extra += apply(pairs, to: &values)
        }

        // Program files, the game's own executables only.
        var exes: [String] = []
        let apps = sevo.appending(path: "apps")
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: apps.path(percentEncoded: false))) ?? [])
            .filter { $0.hasSuffix(".env") }.sorted()
        for file in files {
            guard let exe = GameExecutables.recordable(String(file.dropLast(4))) else { continue }
            exes.append(exe)
            guard let text = try? String(contentsOf: apps.appending(path: file), encoding: .utf8),
                !text.hasPrefix(ConfigMaterializer.header)
            else { continue }
            extra += apply(ConfigMaterializer.parse(text), to: &values)
        }
        if let text = try? String(contentsOf: sevo.appending(path: "game-exe"), encoding: .utf8),
            let exe = GameExecutables.recordable(text.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            exes.append(exe)
        }
        if !exes.isEmpty { values.exes = Array(NSOrderedSet(array: exes)) as? [String] }

        // msync+ was switched off for debugging.
        let marker = prefix.deletingLastPathComponent().appending(path: "notproton-msync")
        if let text = try? String(contentsOf: marker, encoding: .utf8),
            text.trimmingCharacters(in: .whitespacesAndNewlines) == "0"
        {
            values.msync = false
        }

        // Keys no setting owns stay the player's, as environment lines.
        let kept = extra.filter { line in
            guard let key = line.split(separator: "=").first.map(String.init) else { return false }
            return !SettingCatalog.variableIsReserved(key)
        }
        if !kept.isEmpty { values.environment = kept }
        return values
    }

    /// Sets each known key on `values`, a later pair winning; answers the lines no
    /// setting owns.
    static func apply(_ pairs: [(key: String, value: String)], to values: inout ConfigValues) -> [String] {
        func flag(_ v: String) -> Bool? {
            switch v.lowercased() {
            case "1", "true", "yes", "on", "y": true
            case "0", "false", "no", "off", "n", "": false
            default: nil
            }
        }
        var extra: [String] = []
        for (key, value) in pairs {
            switch key {
            case "SEVO_RESIZABLE_WINDOWS": values.windows = WindowTreatment(option: value)
            case "SEVO_UPSCALER": values.upscaler = UpscalerChoice(rawValue: value.lowercased()) ?? values.upscaler
            case "SEVO_FINAL_FILTER": values.filter = FinalFilter(rawValue: value.lowercased()) ?? values.filter
            case "SEVO_FPS": values.fps = flag(value)
            case "SEVO_FPS_GRAPH": values.fpsGraph = flag(value)
            case "SEVO_LINEAR_MOUSE": values.mouse = flag(value) == true ? .linear : .system
            case "SEVO_CURSOR_CONFINE": values.cursorConfine = flag(value)
            case "SEVO_CPU_COUNT": values.processors = Int(value).map { max(0, $0) }
            case "SEVO_FORCE_UMA": values.unifiedMemory = flag(value)
            case "SEVO_LARGE_ADDRESS_AWARE": values.largeAddressAware = flag(value)
            case "MTL_HUD_ENABLED": values.hud = flag(value)
            case "ROSETTA_ADVERTISE_AVX": values.avx = flag(value)
            case "NOTPROTON_RETINA": values.retina = flag(value)
            case "NOTPROTON_RENDERER": values.renderer = RendererChoice(rawValue: value.lowercased()) ?? values.renderer
            case "DXVK_FRAME_RATE":
                if let n = Int(value), n == 0 || SettingCatalog.fpsLimitRange.contains(n) { values.fpsLimit = n }
            default:
                if !scriptKeys.contains(key) { extra.append("\(key)=\(value)") }
            }
        }
        return extra
    }

    /// `own` with every field `old` sets and `own` does not.
    public static func merge(_ old: ConfigValues, under own: ConfigValues) -> ConfigValues {
        let oldJSON = JSONValue.encode(old).object ?? [:]
        var ownJSON = JSONValue.encode(own).object ?? [:]
        for (key, value) in oldJSON where ownJSON[key] == nil || ownJSON[key] == .null {
            ownJSON[key] = value
        }
        if let oldExes = old.exes {
            let merged = (own.exes ?? []) + oldExes.filter { !(own.exes ?? []).contains($0) }
            ownJSON["exes"] = .array(merged.map(JSONValue.string))
        }
        guard let data = try? JSONEncoder().encode(JSONValue.object(ownJSON)),
            let values = try? JSONDecoder().decode(ConfigValues.self, from: data)
        else { return own }
        return values
    }
}
