// The settings a player sets for every game and a game sets for itself: one Setting
// each, holding everything the Steam panel, the CLI and the tests need to know about
// it. The panel draws the catalog it is handed and names no key itself.
//
// Shaped after Sevoflurane's Core/SettingCatalog.swift (MIT, Copyright (c) 2026
// kageroumado); the list follows docs/ROADMAP.md §4.

import Foundation

public enum SettingID: String, CaseIterable, Sendable, Codable {
    case renderer, retina, upscaler, fps, fpsLimit
    case windows, filter, emulateModeset, fpsGraph, hud, dlss
    case mouse, cursorConfine
    case tuning, processors, unifiedMemory, largeAddressAware, avx, gpu, dllOverrides, environment
    case commandIsControl, optionIsAlt
    case msync
}

/// The groups the Advanced dialog shows, in order.
public enum SettingGroup: String, CaseIterable, Sendable, Codable {
    case picture, mouse, performance, keyboard, diagnostics
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

    public init(_ value: JSONValue, _ label: L10n) {
        self.value = value
        self.label = label
    }
}

/// Which control draws a row.
public enum SettingControl: Sendable, Equatable {
    case toggle
    case choice([SettingChoice])
    /// Choices, plus a number of the player's own in `range`.
    case limit([SettingChoice], range: ClosedRange<Int>)
    /// Presets, plus three spin values under Custom.
    case tuning([SettingChoice])
    /// Presets, plus an identity of the player's own under Custom.
    case gpu([SettingChoice])
    /// A list of library → load order, the orders being these choices.
    case dllOverrides([SettingChoice])
    /// Free `KEY=VALUE` lines.
    case environment
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
        case let .choice(choices), let .limit(choices, _):
            if let choice = choices.first(where: { $0.value == value }) { return choice.label }
            if case let .number(n) = value { return .same(String(n)) }
            return .same(value.string ?? value.text)
        case let .tuning(choices), let .gpu(choices):
            let preset = value.object?["preset"] ?? value
            return choices.first { $0.value == preset }?.label ?? .same(preset.string ?? "")
        case .dllOverrides, .environment:
            let count = value.object?.count ?? value.array?.count ?? 0
            return count == 0 ? L10n("None", uk: "Немає", ru: "Нет") : .same(String(count))
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
            control: .choice(labels.map { SettingChoice(.string($0.0.rawValue), $0.1) }), carrier: carrier,
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
    public static let fpsLimitRange = 10...1000
    public static let dllModes = ["n,b", "b,n", "n", "b", ""]

    /// Every setting, in the order the Advanced dialog shows them within a group.
    public static let all: [Setting] = [
        .choice(
            .renderer, in: .picture, levels: [.game], quick: 1, key: \.renderer,
            labels: [(.dxmt, .same("DXMT")), (.dxvk, .same("DXVK")), (.wined3d, .same("WineD3D"))],
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
        .flag(.fps, in: .picture, quick: 4, key: \.fps, copy: .fps, carrier: .environment(["SEVO_FPS"])),
        Setting(
            id: .fpsLimit, group: .picture, levels: [.global, .game], quick: 5, experimental: false,
            copy: .fpsLimit,
            control: .limit(
                [SettingChoice(.number(0), Words.off)] + [30, 60, 90, 120].map { SettingChoice(.number($0), .same("\($0)")) },
                range: fpsLimitRange),
            carrier: .environment(["DXMT_CONFIG", "DXVK_FRAME_RATE"]),
            read: { $0.fpsLimit.map(JSONValue.number) },
            write: { values, value in
                guard let value, value != .null else { values.fpsLimit = nil; return }
                guard let n = value.number ?? value.string.flatMap({ Int($0) }),
                    n == 0 || fpsLimitRange.contains(n)
                else { throw SettingsError.invalidValue("fpsLimit", value.text) }
                values.fpsLimit = n
            },
            resolved: { .number($0[\.fpsLimit]) }),
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
        .flag(.emulateModeset, in: .picture, key: \.emulateModeset, copy: .emulateModeset,
              carrier: .registry(values: ["EmulateModeset"], marker: "NOTPROTON_EMULATE_MODESET")),
        .flag(.fpsGraph, in: .picture, key: \.fpsGraph, copy: .fpsGraph, carrier: .environment(["SEVO_FPS_GRAPH"])),
        .flag(.hud, in: .picture, key: \.hud, copy: .hud, carrier: .environment(["MTL_HUD_ENABLED"])),
        .flag(.dlss, in: .picture, experimental: true, key: \.dlss, copy: .dlss,
              carrier: .environment(["DXMT_ENABLE_NVEXT", "NOTPROTON_DLSS"])),
        .choice(
            .mouse, in: .mouse, key: \.mouse,
            labels: [
                (.system, L10n("macOS acceleration", uk: "Прискорення macOS", ru: "Ускорение macOS")),
                (.linear, L10n("Linear (no acceleration)", uk: "Лінійний (без прискорення)", ru: "Линейное (без ускорения)")),
            ],
            copy: .mouse, carrier: .environment(["SEVO_LINEAR_MOUSE"])),
        .flag(.cursorConfine, in: .mouse, key: \.cursorConfine, copy: .cursorConfine,
              carrier: .environment(["SEVO_CURSOR_CONFINE"])),
        tuningSetting,
        Setting(
            id: .processors, group: .performance, levels: [.global, .game], quick: nil, experimental: false,
            copy: .processors,
            control: .choice([SettingChoice(.number(0), L10n("All", uk: "Усі", ru: "Все"))]
                + [8, 6, 4].map { SettingChoice(.number($0), .same("\($0)")) }),
            carrier: .environment(["SEVO_CPU_COUNT"]),
            read: { $0.processors.map(JSONValue.number) },
            write: { values, value in
                guard let value, value != .null else { values.processors = nil; return }
                guard let n = value.number ?? value.string.flatMap({ Int($0) }), (0...1024).contains(n) else {
                    throw SettingsError.invalidValue("processors", value.text)
                }
                values.processors = n
            },
            resolved: { .number($0[\.processors]) }),
        .flag(.unifiedMemory, in: .performance, experimental: true, key: \.unifiedMemory, copy: .unifiedMemory,
              carrier: .environment(["SEVO_FORCE_UMA"])),
        .flag(.largeAddressAware, in: .performance, key: \.largeAddressAware, copy: .largeAddressAware,
              carrier: .environment(["SEVO_LARGE_ADDRESS_AWARE"])),
        .flag(.avx, in: .performance, key: \.avx, copy: .avx, carrier: .environment(["ROSETTA_ADVERTISE_AVX"])),
        gpuSetting,
        dllSetting,
        environmentSetting,
        .flag(.commandIsControl, in: .keyboard, key: \.commandIsControl, copy: .commandIsControl,
              carrier: .registry(values: ["LeftCommandIsCtrl", "RightCommandIsCtrl"], marker: "NOTPROTON_COMMAND_IS_CTRL")),
        .flag(.optionIsAlt, in: .keyboard, key: \.optionIsAlt, copy: .optionIsAlt,
              carrier: .registry(values: ["LeftOptionIsAlt", "RightOptionIsAlt"], marker: "NOTPROTON_OPTION_IS_ALT")),
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

    static let gpuChoices = [
        SettingChoice(.string(GPUPreset.asIs.rawValue), L10n("As is", uk: "Як є", ru: "Как есть")),
        SettingChoice(.string(GPUPreset.amd.rawValue), .same("AMD Radeon RX 7900 XT")),
        SettingChoice(.string(GPUPreset.nvidia.rawValue), .same("NVIDIA GeForce RTX 5080")),
        SettingChoice(.string(GPUPreset.intelArc.rawValue), .same("Intel Arc A750")),
        SettingChoice(.string(GPUPreset.custom.rawValue), Words.custom),
    ]

    static func gpuJSON(_ preset: GPUPreset, _ custom: GPUIdentity?) -> JSONValue {
        var object: [String: JSONValue] = ["preset": .string(preset.rawValue)]
        if let identity = preset == .custom ? custom : preset.identity {
            object["vendorID"] = .number(identity.vendorID)
            object["deviceID"] = .number(identity.deviceID)
            object["name"] = .string(identity.name)
            if let memory = identity.memoryMB { object["memoryMB"] = .number(memory) }
        }
        return .object(object)
    }

    static let gpuSetting = Setting(
        id: .gpu, group: .performance, levels: [.global, .game], quick: nil, experimental: false,
        copy: .gpu, control: .gpu(gpuChoices),
        carrier: .environment([
            "SEVO_GPU_VENDOR_ID", "SEVO_GPU_DEVICE_ID", "SEVO_GPU_NAME", "SEVO_GPU_MEMORY_MB", "DXMT_CONFIG",
        ]),
        read: { values in values.gpu.map { gpuJSON($0, values.gpuCustom) } },
        write: { values, value in
            guard let value, value != .null else {
                values.gpu = nil
                values.gpuCustom = nil
                return
            }
            let object = value.object ?? ["preset": value]
            guard let raw = object["preset"]?.string, let preset = GPUPreset(rawValue: raw) else {
                throw SettingsError.invalidValue("gpu", value.text)
            }
            guard preset == .custom else {
                values.gpu = preset
                values.gpuCustom = nil
                return
            }
            func id(_ key: String) -> Int? {
                if let n = object[key]?.number { return n }
                guard let text = object[key]?.string?.lowercased() else { return nil }
                return Int(text.hasPrefix("0x") ? String(text.dropFirst(2)) : text, radix: 16)
            }
            guard let vendor = id("vendorID"), let device = id("deviceID") else {
                throw SettingsError.invalidValue("gpu", value.text)
            }
            let identity = GPUIdentity(
                vendorID: vendor, deviceID: device,
                name: object["name"]?.string?.trimmingCharacters(in: .whitespaces) ?? "",
                memoryMB: object["memoryMB"]?.number)
            guard identity.isValid else { throw SettingsError.invalidValue("gpu", value.text) }
            values.gpu = .custom
            values.gpuCustom = identity
        },
        resolved: { stack in
            let preset = stack[\.gpu]
            let custom = stack.game.gpu != nil ? stack.game.gpuCustom : stack.global.gpuCustom
            return gpuJSON(preset, custom)
        })

    static let dllChoices = [
        SettingChoice(.string("n,b"), L10n("Native, then built-in", uk: "Рідна, потім вбудована", ru: "Родная, затем встроенная")),
        SettingChoice(.string("b,n"), L10n("Built-in, then native", uk: "Вбудована, потім рідна", ru: "Встроенная, затем родная")),
        SettingChoice(.string("n"), L10n("Native only", uk: "Лише рідна", ru: "Только родная")),
        SettingChoice(.string("b"), L10n("Built-in only", uk: "Лише вбудована", ru: "Только встроенная")),
        SettingChoice(.string(""), L10n("Disabled", uk: "Вимкнено", ru: "Отключено")),
    ]

    /// Libraries NotProton loads its own way: the Steam bridge and the renderers.
    public static let reservedDLLs: Set<String> = [
        "steamclient", "steamclient64", "lsteamclient", "steam_api", "steam_api64",
        "d3d9", "d3d10", "d3d10_1", "d3d10core", "d3d11", "d3d12", "d3d12core", "dxgi", "winemetal",
        "nvapi", "nvapi64", "nvngx", "ntdll", "kernel32", "kernelbase", "winemac.drv",
    ]

    /// A library name as Wine's overrides take it: lowercase, without `.dll`.
    public static func normalizedDLL(_ name: String) -> String? {
        var dll = name.trimmingCharacters(in: .whitespaces).lowercased()
        if dll.hasSuffix(".dll") { dll.removeLast(4) }
        guard !dll.isEmpty, dll.count <= 64,
            dll.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "_-.".contains($0)) })
        else { return nil }
        return dll
    }

    static let dllSetting = Setting(
        id: .dllOverrides, group: .performance, levels: [.global, .game], quick: nil, experimental: false,
        copy: .dllOverrides, control: .dllOverrides(dllChoices), carrier: .runScript("NOTPROTON_DLL_OVERRIDES"),
        read: { $0.dllOverrides.map { .object($0.mapValues(JSONValue.string)) } },
        write: { values, value in
            guard let value, value != .null else { values.dllOverrides = nil; return }
            guard let object = value.object else { throw SettingsError.invalidValue("dllOverrides", value.text) }
            var overrides: [String: String] = [:]
            for (name, mode) in object {
                guard let dll = normalizedDLL(name), !reservedDLLs.contains(dll),
                    let raw = mode.string?.replacingOccurrences(of: " ", with: ""), dllModes.contains(raw)
                else { throw SettingsError.invalidValue("dllOverrides", "\(name)=\(mode.text)") }
                overrides[dll] = raw
            }
            values.dllOverrides = overrides
        },
        resolved: { stack in
            let merged = (stack.global.dllOverrides ?? [:]).merging(stack.game.dllOverrides ?? [:]) { $1 }
            return .object(merged.mapValues(JSONValue.string))
        })

    /// Variables NotProton or the engine set themselves, and the ones a setting owns.
    public static var reservedVariables: Set<String> {
        var keys: Set<String> = [
            "WINEDLLOVERRIDES", "WINEDLLPATH", "WINEDLLPATH_PREPEND", "WINEPREFIX", "WINESERVER", "WINELOADER",
            "WINEARCH", "WINEMSYNC", "WINEESYNC", "WINEFSYNC", "SEVO_LOADER", "SEVO_LOADER_TREE", "SEVO_CLI",
            "SEVO_ENV_FILES", "SEVO_ENGINE_NAME", "HOME", "PATH", "USER",
        ]
        for setting in all { keys.formUnion(setting.carrier.envKeys) }
        return keys
    }

    static func variableIsReserved(_ key: String) -> Bool {
        reservedVariables.contains(key) || key.hasPrefix("DYLD_") || key.hasPrefix("NOTPROTON_")
            || key.hasPrefix("STEAM_COMPAT_")
    }

    /// `KEY=VALUE` lines out of what the player typed: one per line, or Steam launch
    /// options such as `DXVK_HUD=1 VAR=2 %command% -flag` (what follows %command% is not
    /// an environment variable and is dropped). Throws for a reserved or malformed key.
    public static func environmentLines(from input: [String]) throws -> [String] {
        var lines: [String] = []
        for entry in input {
            let tokens: [String]
            if entry.contains("%command%") {
                let head = entry.components(separatedBy: "%command%")[0]
                tokens = head.split(whereSeparator: \.isWhitespace).map(String.init)
            } else {
                tokens = entry.split(whereSeparator: \.isNewline).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
            }
            for token in tokens where !token.isEmpty && !token.hasPrefix("#") {
                guard let eq = token.firstIndex(of: "=") else {
                    throw SettingsError.invalidValue("environment", token)
                }
                let key = String(token[..<eq])
                var value = String(token[token.index(after: eq)...])
                if value.count >= 2, let q = value.first, q == "\"" || q == "'", value.last == q {
                    value = String(value.dropFirst().dropLast())
                }
                guard let first = key.first, first.isLetter || first == "_",
                    key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }),
                    !value.contains("\n"), !value.contains("\r"), value.count <= 4096
                else { throw SettingsError.invalidValue("environment", token) }
                guard !variableIsReserved(key) else { throw SettingsError.reservedVariable(key) }
                lines.removeAll { $0.hasPrefix(key + "=") }
                lines.append("\(key)=\(value)")
            }
        }
        return lines
    }

    static let environmentSetting = Setting(
        id: .environment, group: .performance, levels: [.global, .game], quick: nil, experimental: false,
        copy: .environment, control: .environment, carrier: .environment([]),
        read: { $0.environment.map { .array($0.map(JSONValue.string)) } },
        write: { values, value in
            guard let value, value != .null else { values.environment = nil; return }
            let input: [String]
            if let text = value.string {
                input = [text]
            } else if let array = value.array {
                input = try array.map {
                    guard let line = $0.string else { throw SettingsError.invalidValue("environment", $0.text) }
                    return line
                }
            } else {
                throw SettingsError.invalidValue("environment", value.text)
            }
            values.environment = try environmentLines(from: input)
        },
        resolved: { stack in
            .array(((stack.global.environment ?? []) + (stack.game.environment ?? [])).map(JSONValue.string))
        })
}
