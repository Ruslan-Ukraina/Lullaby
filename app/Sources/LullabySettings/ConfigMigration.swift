// Brings the settings NotProton kept before the catalog into the store, without
// losing a value the player chose (docs/ROADMAP.md §4, "Миграция").
//
// Before Phase 7A a prefix's files were the source of truth:
// - `.sevo/bottle.env`, written once by compat_run.sh with NotProton's profile, and
//   by the player's hand after that;
// - `.sevo/apps/<exe>.env`, written by the Game Settings window and the View menu's
//   stand-in, plus the run script's SEVO_LOADER;
// - `<compatdata>/lullaby-msync`, the msync+ debugging marker.
// A prefix whose bottle.env lacks the catalog's header has not been migrated. Each
// one is per game, so everything it holds that differs from the old profile is that
// game's own choice. Values already in the store win: they are newer.
//
// The store itself changed shape with Amendment 09.10 (docs/ROADMAP.md §13): see
// upgradeStore at the end.

import Foundation

public enum ConfigMigration {
    /// What compat_run.sh wrote into a new bottle.env before the catalog.
    static let oldProfile: [String: String] = [
        "SEVO_RESIZABLE_WINDOWS": "1", "SEVO_UPSCALER": "off", "SEVO_FINAL_FILTER": "lanczos",
        "SEVO_FPS": "0", "SEVO_FPS_GRAPH": "0", "SEVO_LINEAR_MOUSE": "0", "SEVO_CURSOR_CONFINE": "0",
    ]

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
        let marker = prefix.deletingLastPathComponent().appending(path: "lullaby-msync")
        try? manager.copyItem(at: marker, to: backup.appending(path: "lullaby-msync"))
    }

    /// The values a prefix's old files hold, as one game level. Keys no setting owns any
    /// more stay only in the backup.
    public static func values(fromPrefix prefix: URL) -> ConfigValues {
        let sevo = prefix.appending(path: ".sevo")
        var values = ConfigValues()

        // The prefix's bottle.env: only what differs from the old profile was chosen.
        if let text = try? String(contentsOf: sevo.appending(path: "bottle.env"), encoding: .utf8),
            !text.hasPrefix(ConfigMaterializer.header)
        {
            let pairs = ConfigMaterializer.parse(text).filter { oldProfile[$0.key] != $0.value }
            apply(pairs, to: &values)
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
            apply(ConfigMaterializer.parse(text), to: &values)
        }
        if let text = try? String(contentsOf: sevo.appending(path: "game-exe"), encoding: .utf8),
            let exe = GameExecutables.recordable(text.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            exes.append(exe)
        }
        if !exes.isEmpty { values.exes = Array(NSOrderedSet(array: exes)) as? [String] }

        // msync+ was switched off for debugging.
        let marker = prefix.deletingLastPathComponent().appending(path: "lullaby-msync")
        if let text = try? String(contentsOf: marker, encoding: .utf8),
            text.trimmingCharacters(in: .whitespacesAndNewlines) == "0"
        {
            values.msync = false
        }
        return values
    }

    /// Sets each known key on `values`, a later pair winning. Dormison's counter and the
    /// Metal HUD are one counter now: either one on turns it on.
    static func apply(_ pairs: [(key: String, value: String)], to values: inout ConfigValues) {
        func flag(_ v: String) -> Bool? {
            switch v.lowercased() {
            case "1", "true", "yes", "on", "y": true
            case "0", "false", "no", "off", "n", "": false
            default: nil
            }
        }
        for (key, value) in pairs {
            switch key {
            case "SEVO_RESIZABLE_WINDOWS": values.windows = WindowTreatment(option: value)
            case "SEVO_UPSCALER": values.upscaler = UpscalerChoice(rawValue: value.lowercased()) ?? values.upscaler
            case "SEVO_FINAL_FILTER": values.filter = FinalFilter(rawValue: value.lowercased()) ?? values.filter
            case "SEVO_FPS", "MTL_HUD_ENABLED":
                if let on = flag(value) { values.fps = (values.fps ?? false) || on }
            case "SEVO_LINEAR_MOUSE": values.mouse = flag(value) == true ? .linear : .system
            case "SEVO_FORCE_UMA": values.unifiedMemory = flag(value)
            case "SEVO_LARGE_ADDRESS_AWARE": values.largeAddressAware = flag(value)
            case "ROSETTA_ADVERTISE_AVX": values.avx = flag(value)
            // Files from before the catalog carry the project's old name (NotProton until
            // 10.10.2026, docs/RENAME_LULLABY.md).
            case "LULLABY_RETINA", "NOTPROTON_RETINA": values.retina = flag(value)
            case "LULLABY_RENDERER", "NOTPROTON_RENDERER": values.renderer = RendererChoice(rawValue: value.lowercased()) ?? values.renderer
            default: break
            }
        }
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

    // MARK: - The store before Amendment 09.10

    /// Settings the amendment took out of the catalog (docs/ROADMAP.md §13.3 б, в, г): the
    /// frame-rate limit, Dormison's graph, the pointer confinement, the processor count, the
    /// graphics card (now automatic), DLL overrides and environment lines (Steam's launch
    /// options do that). `hud` is folded into `fps` first.
    static let retiredKeys = [
        "fpsLimit", "fpsGraph", "hud", "cursorConfine", "processors", "gpu", "gpuCustom",
        "dllOverrides", "environment",
    ]

    static let storeBackupName = "backup-before-schema-2"

    /// One level's file brought to schema 2: the counter is the Metal HUD, so it is on
    /// where Dormison's counter or the HUD was; the retired keys go.
    static func upgradeLevel(_ old: [String: JSONValue]) -> ConfigValues {
        var object = old
        let counters = [old["fps"], old["hud"]].compactMap { $0?.bool }
        if !counters.isEmpty { object["fps"] = .bool(counters.contains(true)) }
        for key in retiredKeys { object.removeValue(forKey: key) }
        guard let data = try? JSONEncoder().encode(JSONValue.object(object)),
            let values = try? JSONDecoder().decode(ConfigValues.self, from: data)
        else { return .empty }
        return values
    }

    /// Brings a store written before the amendment to schema 2, once, with a copy of its
    /// files kept in `settings/backup-before-schema-2`. A value equal to what its level
    /// inherits stops being the level's own (§13.3 и). Answers whether a level changed;
    /// the caller then rewrites every prefix.
    public static func upgradeStore(_ store: SettingsStore) throws -> Bool {
        guard store.schema < SettingsStore.schema else { return false }
        return try store.locked {
            guard store.schema < SettingsStore.schema else { return false }
            var changed = false
            let gameFiles = ((try? FileManager.default.contentsOfDirectory(
                at: store.gamesRoot, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "json" }
            if store.rawObject(store.globalURL) != nil || !gameFiles.isEmpty {
                try store.backUp(into: storeBackupName)
            }
            var global = ConfigValues.empty
            if let old = store.rawObject(store.globalURL) {
                global = SettingCatalog.withoutInherited(upgradeLevel(old), level: .global, global: .empty)
                if JSONValue.encode(global).object != old { changed = true }
                try store.setGlobal(global)
            }
            for url in gameFiles {
                guard let id = Int(url.deletingPathExtension().lastPathComponent), id > 0,
                    let old = store.rawObject(url)
                else { continue }
                let game = SettingCatalog.withoutInherited(upgradeLevel(old), level: .game, global: global)
                if JSONValue.encode(game).object != old { changed = true }
                try store.setGame(id, game)
            }
            try store.setSchema(SettingsStore.schema)
            return changed
        }
    }
}
