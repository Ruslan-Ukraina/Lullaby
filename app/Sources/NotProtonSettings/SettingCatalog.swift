// The settings a player sets for every game and a game sets for itself: one Setting
// each, holding everything the Steam panel, the CLI and the tests need to know about
// it. The panel draws the catalog it is handed and names no key itself.
//
// Shaped after Sevoflurane's Core/SettingCatalog.swift (MIT, Copyright (c) 2026
// kageroumado); the list follows docs/ROADMAP.md §4.

import Foundation

public enum SettingID: String, CaseIterable, Sendable, Codable {
    case renderer, retina, upscaler, fps
    case windows, filter, dlss
    case mouse
    case tuning, unifiedMemory, avx
    case emulateModeset, largeAddressAware
    case msync
}

/// The groups the Advanced dialog shows, in order. `oldGames` holds what only older games
/// need (Amendment 09.10, docs/ROADMAP.md §13).
public enum SettingGroup: String, CaseIterable, Sendable, Codable {
    case picture, mouse, performance, oldGames, diagnostics
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
    /// A component the player adds before this choice is offered ("d3dmetal").
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
    /// A NotProton key compat_run.sh reads from the env files and acts on itself.
    case runScript(String)
    /// Keys only bottle.env may set (Dormison ignores them in a program's file), plus the
    /// prefix's `notproton-msync` marker.
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
                SettingChoice(.string($0.0.rawValue), $0.1, requires: $0.0.rawValue == "d3dmetal" ? "d3dmetal" : nil)
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
            labels: [(.dxmt, .same("DXMT")), (.dxvk, .same("DXVK")), (.wined3d, .same("WineD3D")),
                     (.d3dmetal, .same("D3DMetal"))],
            copy: .renderer, carrier: .runScript("NOTPROTON_RENDERER")),
        .flag(.retina, in: .picture, quick: 2, key: \.retina, copy: .retina,
              carrier: .registry(values: ["RetinaMode"], marker: "NOTPROTON_RETINA")),
        .choice(
            .upscaler, in: .picture, quick: 3, key: \.upscaler,
            labels: [
                (.off, Words.off),
                (.lanczos, L10n("Final filter only", uk: "Лише фінальний фільтр", ru: "Только финальный фильтр")),
                (.metalfx, .same("MetalFX Spatial")),
            ],
            copy: .upscaler, carrier: .environment(["SEVO_UPSCALER"])),
        .flag(.fps, in: .picture, quick: 4, key: \.fps, copy: .fps, carrier: .environment(["MTL_HUD_ENABLED"])),
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
        .choice(
            .filter, in: .picture, key: \.filter,
            labels: [
                (.nearest, L10n("Nearest", uk: "Найближчий", ru: "Ближайший")),
                (.bilinear, L10n("Bilinear", uk: "Білінійний", ru: "Билинейный")),
                (.lanczos, .same("Lanczos")),
            ],
            copy: .filter, carrier: .environment(["SEVO_FINAL_FILTER"])),
        // The card a game is told of follows this switch (GPUIdentity.forGame).
        .flag(.dlss, in: .picture, experimental: true, key: \.dlss, copy: .dlss,
              carrier: .environment(["DXMT_ENABLE_NVEXT", "D3DM_ENABLE_METALFX", "NOTPROTON_DLSS"] + ConfigMaterializer.gpuKeys)),
        .choice(
            .mouse, in: .mouse, key: \.mouse,
            labels: [
                (.system, L10n("macOS acceleration", uk: "Прискорення macOS", ru: "Ускорение macOS")),
                (.linear, L10n("Linear (no acceleration)", uk: "Лінійний (без прискорення)", ru: "Линейное (без ускорения)")),
            ],
            copy: .mouse, carrier: .environment(["SEVO_LINEAR_MOUSE"])),
        tuningSetting,
        .flag(.unifiedMemory, in: .performance, experimental: true, key: \.unifiedMemory, copy: .unifiedMemory,
              carrier: .environment(["SEVO_FORCE_UMA"])),
        .flag(.avx, in: .performance, key: \.avx, copy: .avx, carrier: .environment(["ROSETTA_ADVERTISE_AVX"])),
        .flag(.emulateModeset, in: .oldGames, key: \.emulateModeset, copy: .emulateModeset,
              carrier: .registry(values: ["EmulateModeset"], marker: "NOTPROTON_EMULATE_MODESET")),
        .flag(.largeAddressAware, in: .oldGames, key: \.largeAddressAware, copy: .largeAddressAware,
              carrier: .environment(["SEVO_LARGE_ADDRESS_AWARE"])),
        .flag(.msync, in: .diagnostics, levels: [.game], key: \.msync, copy: .msync,
              carrier: .bottleOnly(["WINEMSYNC"])),
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
    /// game-only setting from NotProton's defaults.
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
        id: .tuning, group: .performance, levels: [.global, .game], quick: nil, experimental: false,
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
