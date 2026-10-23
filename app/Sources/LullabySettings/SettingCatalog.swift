// The settings a player sets for every game and a game sets for itself: one Setting
// each, holding everything the Steam panel, the CLI and the tests need to know about
// it. The panel draws the catalog it is handed and names no key itself.
//
// Shaped after Sevoflurane's Core/SettingCatalog.swift (MIT, Copyright (c) 2026
// kageroumado); the list follows docs/ROADMAP.md §4.

import Foundation

public enum SettingID: String, CaseIterable, Sendable, Codable {
    case renderer, retina, fps
    case windows, filter
    case tuning, gameMode
    case unifiedMemory, rawMouse, forceVsync
}

/// The groups the Advanced dialog shows, in order. What a game's bitness or age decides
/// (4 GB for 32-bit games, display mode emulation) is no setting: compat_run.sh and the
/// materializer set it (ConfigMaterializer.fixedLines).
public enum SettingGroup: String, CaseIterable, Sendable, Codable {
    case picture, performance, diagnostics
}

public enum SettingLevel: String, CaseIterable, Sendable, Codable {
    /// Steam Settings › Compatibility: every game's `.sevo/bottle.env`.
    case global
    /// A game's Properties › Compatibility: `.sevo/apps/<exe>.env` of each of its executables.
    case game
}

public struct SettingChoice: Sendable, Equatable {
    public let value: JSONValue
    public let label: L10n
    /// A component this choice needs ("d3dmetal": added by the player first).
    public var requires: String?

    public init(_ value: JSONValue, _ label: L10n, requires: String? = nil) {
        self.value = value
        self.label = label
        self.requires = requires
    }
}

/// Which control draws a row.
public enum SettingControl: Sendable, Equatable {
    case toggle
    case choice([SettingChoice])
    /// Presets, plus three spin values under Custom.
    case tuning([SettingChoice])
}

/// What takes a value to a running game — what a test checks to see that a control
/// is connected to anything.
public enum SettingCarrier: Sendable, Equatable {
    /// Lines of the env files Dormison reads at every process start.
    case environment([String])
    /// Wine registry values. compat_run.sh writes them into the game's prefix at launch,
    /// reading `marker` from the env files (a prefix has no wineserver between launches).
    case registry(values: [String], marker: String)
    /// A Lullaby key compat_run.sh reads from the env files and acts on itself.
    case runScript(String)
    /// Keys only bottle.env may set (Dormison ignores them in a program's file), plus the
    /// prefix's `lullaby-msync` marker.
    case bottleOnly([String])

    /// Every key this carrier writes into an env file.
    public var envKeys: [String] {
        switch self {
        case let .environment(keys): keys
        case let .registry(_, marker): [marker]
        case let .runScript(key): [key]
        case let .bottleOnly(keys): keys
        }
    }
}

public struct Setting: Sendable {
    public let id: SettingID
    public let group: SettingGroup
    public let levels: Set<SettingLevel>
    /// The row's place among the quick settings on the Compatibility page, nil for a
    /// row of the Advanced dialog.
    public let quick: Int?
    public let experimental: Bool
    public let copy: SettingCopy
    public let control: SettingControl
    public let carrier: SettingCarrier
    /// This level's own value, nil where it inherits.
    public let read: @Sendable (ConfigValues) -> JSONValue?
    /// Stores a value at a level, nil to inherit. Throws for a value the setting cannot hold.
    public let write: @Sendable (inout ConfigValues, JSONValue?) throws -> Void
    /// What the hierarchy resolves to.
    public let resolved: @Sendable (ConfigStack) -> JSONValue
    /// The renderers a game's row is shown with; empty for every renderer.
    public var renderers: [RendererChoice] = []

    func shown(with renderers: [RendererChoice]) -> Setting {
        var setting = self
        setting.renderers = renderers
        return setting
    }

    /// The label of a value, for "For all games: …".
    public func label(of value: JSONValue) -> L10n {
        switch control {
        case .toggle:
            return value.bool == true ? Words.on : Words.off
        case let .choice(choices):
            if let choice = choices.first(where: { $0.value == value }) { return choice.label }
            return .same(value.string ?? value.text)
        case let .tuning(choices):
            let preset = value.object?["preset"] ?? value
            return choices.first { $0.value == preset }?.label ?? .same(preset.string ?? "")
        }
    }
}

// MARK: - Builders

extension Setting {
    static func flag(
        _ id: SettingID, in group: SettingGroup, levels: Set<SettingLevel> = [.global, .game],
        quick: Int? = nil, experimental: Bool = false,
        key: WritableKeyPath<ConfigValues, Bool?> & Sendable, copy: SettingCopy, carrier: SettingCarrier
    ) -> Setting {
        Setting(
            id: id, group: group, levels: levels, quick: quick, experimental: experimental, copy: copy,
            control: .toggle, carrier: carrier,
            read: { $0[keyPath: key].map(JSONValue.bool) },
            write: { values, value in
                guard let value, value != .null else { values[keyPath: key] = nil; return }
                guard let flag = value.bool else { throw SettingsError.invalidValue(id.rawValue, value.text) }
                values[keyPath: key] = flag
            },
            resolved: { .bool($0[key]) })
    }

    static func choice<C: RawRepresentable & CaseIterable & Sendable>(
        _ id: SettingID, in group: SettingGroup, levels: Set<SettingLevel> = [.global, .game],
        quick: Int? = nil, key: WritableKeyPath<ConfigValues, C?> & Sendable,
        labels: [(C, L10n)], copy: SettingCopy, carrier: SettingCarrier
    ) -> Setting where C.RawValue == String {
        Setting(
            id: id, group: group, levels: levels, quick: quick, experimental: false, copy: copy,
            control: .choice(labels.map {
                SettingChoice(.string($0.0.rawValue), $0.1,
                              requires: $0.0.rawValue == "d3dmetal" ? "d3dmetal" : nil)
            }), carrier: carrier,
            read: { $0[keyPath: key].map { .string($0.rawValue) } },
            write: { values, value in
                guard let value, value != .null else { values[keyPath: key] = nil; return }
                guard let raw = value.string, let choice = C(rawValue: raw.lowercased()) else {
                    throw SettingsError.invalidValue(id.rawValue, value.text)
                }
                values[keyPath: key] = choice
            },
            resolved: { .string($0[key].rawValue) })
    }
}

// MARK: - The catalog

public enum SettingCatalog {
    /// Every setting, in the order the Advanced dialog shows them within a group.
    public static let all: [Setting] = [
        .choice(
            .renderer, in: .picture, levels: [.game], quick: 1, key: \.renderer,
            labels: [(.d3dmetal, .same("D3DMetal")), (.dxmt, .same("DXMT")), (.dxvk, .same("DXVK")),
                     (.wined3d, .same("WineD3D"))],
            copy: .renderer, carrier: .runScript("LULLABY_RENDERER")),
        .flag(.retina, in: .picture, quick: 2, key: \.retina, copy: .retina,
              carrier: .registry(values: ["RetinaMode"], marker: "LULLABY_RETINA")),
        .flag(.fps, in: .picture, quick: 3, key: \.fps, copy: .fps, carrier: .environment(["MTL_HUD_ENABLED"])),
        .choice(
            .windows, in: .picture, key: \.windows,
            labels: [
                (.off, L10n("Never", uk: "Ніколи", ru: "Никогда")),
                (.fixed, L10n("Fixed-size windows", uk: "Вікна фіксованого розміру", ru: "Окна фиксированного размера")),
                (.window, L10n("Fixed-size and full-screen games", uk: "Фіксовані й повноекранні ігри",
                               ru: "Фиксированные и полноэкранные игры")),
                (.all, L10n("Every window with a title bar", uk: "Кожне вікно із заголовком", ru: "Каждое окно с заголовком")),
            ],
            copy: .windows, carrier: .environment(["SEVO_RESIZABLE_WINDOWS"])),
        pictureFilterSetting,
        tuningSetting,
        .flag(.unifiedMemory, in: .diagnostics, key: \.unifiedMemory, copy: .unifiedMemory,
              carrier: .environment(["SEVO_FORCE_UMA"])),
        // Raw GameController input (winemac patches 0004 and 0005): on for every game; this switch
        // is for finding out whether it is the cause of a problem.
        .flag(.rawMouse, in: .diagnostics, key: \.rawMouse, copy: .rawMouse,
              carrier: .environment(["LULLABY_GCMOUSE"])),
        // The run script writes the game's bundle (compat_run.sh): LSSupportsGameMode.
        .flag(.gameMode, in: .performance, key: \.gameMode, copy: .gameMode, carrier: .environment(["LULLABY_GAME_MODE"])),
        // Lullaby's winemac.so fix 0003 (WineMetalLayer): the D3DMetal layer's sync, and the
        // present feed Lullaby's nvapi64.dll paces NVIDIA Reflex with (patches/inject/lby-rainbowdash-reflex/).
        .flag(.forceVsync, in: .diagnostics, experimental: true, key: \.forceVsync, copy: .forceVsync,
              carrier: .environment(["LULLABY_FORCE_VSYNC"])),
    ]

    public static func setting(_ id: SettingID) -> Setting {
        all.first { $0.id == id }!
    }

    public static func setting(named name: String) -> Setting? {
        all.first { $0.id.rawValue.lowercased() == name.lowercased() }
    }

    public static var quick: [Setting] {
        all.filter { $0.quick != nil }.sorted { $0.quick! < $1.quick! }
    }

    public static func settings(in group: SettingGroup, at level: SettingLevel) -> [Setting] {
        all.filter { $0.group == group && $0.levels.contains(level) }
    }

    /// `values` at `level` without the values equal to what the level inherits: such a
    /// value is no choice of the level's own, and the panel shows no line for it
    /// (Amendment 09.10, §13.3 и). A game inherits from `global`, the global level and a
    /// game-only setting from Lullaby's defaults.
    public static func withoutInherited(
        _ values: ConfigValues, level: SettingLevel, global: ConfigValues, recipe: ConfigValues = .empty
    ) -> ConfigValues {
        var result = values
        for setting in all where setting.levels.contains(level) {
            guard let own = setting.read(result) else { continue }
            let parent = level == .game
                ? ConfigStack(global: setting.levels.contains(.global) ? global : .empty, recipe: recipe)
                : ConfigStack(global: .empty)
            if own == setting.resolved(parent) { try? setting.write(&result, nil) }
        }
        return result
    }

    // MARK: Compound settings

    /// The picture's last step: nothing, one of Dormison's final filters, or MetalFX Spatial. One
    /// row over two stored values (`upscaler`, `filter`): the engine's filter acts only while its
    /// presenter runs, which an upscaler other than "off" starts, so a filter is "upscaler lanczos
    /// (the final filter alone) + that filter" and MetalFX Spatial is "upscaler metalfx".
    static let pictureFilterChoices = [
        SettingChoice(.string(PictureFilter.off.rawValue), Words.off),
        SettingChoice(.string(PictureFilter.bilinear.rawValue), .same("Bilinear")),
        SettingChoice(.string(PictureFilter.lanczos.rawValue), .same("Lanczos")),
        SettingChoice(.string(PictureFilter.metalfx.rawValue), .same("MetalFX Spatial")),
    ]

    static let pictureFilterSetting = Setting(
        id: .filter, group: .picture, levels: [.global, .game], quick: nil, experimental: false,
        copy: .filter, control: .choice(pictureFilterChoices),
        carrier: .environment(["SEVO_UPSCALER", "SEVO_FINAL_FILTER"]),
        read: { values in PictureFilter(upscaler: values.upscaler, filter: values.filter).map { .string($0.rawValue) } },
        write: { values, value in
            guard let value, value != .null else {
                values.upscaler = nil
                values.filter = nil
                return
            }
            guard let raw = value.string, let choice = PictureFilter(rawValue: raw.lowercased()) else {
                throw SettingsError.invalidValue("filter", value.text)
            }
            values.upscaler = choice.upscaler
            values.filter = choice.finalFilter
        },
        resolved: { stack in
            .string((PictureFilter(upscaler: stack[\.upscaler], filter: stack[\.filter]) ?? .off).rawValue)
        })

    static let tuningChoices = [
        SettingChoice(.string("standard"), L10n("Standard", uk: "Стандарт", ru: "Стандарт")),
        SettingChoice(.string("experimental"), L10n("Experimental", uk: "Експериментально", ru: "Экспериментально")),
        SettingChoice(.string("custom"), Words.custom),
    ]

    static func tuningJSON(_ preset: PerformanceTuning, _ parameters: TuningParameters) -> JSONValue {
        .object([
            "preset": .string(preset.rawValue), "waitSpin": .number(parameters.waitSpin),
            "adaptive": .bool(parameters.adaptive), "objectSpin": .number(parameters.objectSpin),
        ])
    }

    static let tuningSetting = Setting(
        id: .tuning, group: .performance, levels: [.global, .game], quick: nil, experimental: true,
        copy: .tuning, control: .tuning(tuningChoices),
        carrier: .environment(["SEVO_WAIT_SPIN", "SEVO_WAIT_SPIN_ADAPT", "SEVO_OBJECT_SPIN"]),
        read: { values in
            values.tuning.map { tuningJSON($0, $0.parameters(custom: values.tuningParameters)) }
        },
        write: { values, value in
            guard let value, value != .null else {
                values.tuning = nil
                values.tuningParameters = nil
                return
            }
            let object = value.object ?? ["preset": value]
            guard let raw = object["preset"]?.string, let preset = PerformanceTuning(rawValue: raw) else {
                throw SettingsError.invalidValue("tuning", value.text)
            }
            guard preset == .custom else {
                values.tuning = preset
                values.tuningParameters = nil
                return
            }
            let base = values.tuningParameters ?? .experimental
            let wait = object["waitSpin"]?.number ?? base.waitSpin
            let spin = object["objectSpin"]?.number ?? base.objectSpin
            guard TuningParameters.spinRange.contains(wait), TuningParameters.spinRange.contains(spin) else {
                throw SettingsError.invalidValue("tuning", value.text)
            }
            values.tuning = preset
            values.tuningParameters = TuningParameters(
                waitSpin: wait, adaptive: object["adaptive"]?.bool ?? base.adaptive, objectSpin: spin)
        },
        resolved: { stack in
            let preset = stack[\.tuning]
            let custom = stack.game.tuning != nil ? stack.game.tuningParameters : stack.global.tuningParameters
            return tuningJSON(preset, preset.parameters(custom: custom))
        })
}
