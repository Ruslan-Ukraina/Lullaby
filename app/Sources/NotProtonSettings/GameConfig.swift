// The settings hierarchy NotProton keeps for Dormison: one level for every game
// ("for all games") and one per Steam app id. A game is an app id, not an
// executable: the levels are stored by app id and written into the env file of
// every executable the game is known to run (ConfigMaterializer).
//
// The value types and the inheritance rules follow Sevoflurane's Core/GameConfig.swift
// (MIT, Copyright (c) 2026 kageroumado), adapted to NotProton: one prefix per game,
// so the "for all games" level is what every prefix's bottle.env carries.

import Foundation

/// Dormison's `ResizableWindows` (`SEVO_RESIZABLE_WINDOWS`). The driver reads the
/// first character, so the raw values stay distinct in it; `1` reads as `fixed`.
public enum WindowTreatment: String, Codable, CaseIterable, Sendable {
    case off, fixed, window, all

    /// What an env file or the View menu wrote, by the driver's own rule.
    public init(option: String) {
        switch option.lowercased().first {
        case "a": self = .all
        case "w": self = .window
        case "f", "1", "t", "y": self = .fixed
        default: self = .off
        }
    }
}

/// Dormison's `Upscaler`. Anime4K and CuNNy come with shader packages, which this
/// engine build does not ship (SEVO_SHADER_DIR), so they are not offered yet.
public enum UpscalerChoice: String, Codable, CaseIterable, Sendable {
    case off, lanczos, metalfx
}

/// Dormison's `FinalFilter`.
public enum FinalFilter: String, Codable, CaseIterable, Sendable {
    case nearest, bilinear, lanczos
}

/// What draws Direct3D 10/11. D3DMetal joins once the player adds Apple's toolkit
/// (Phase 7B), Mullion as an experiment (Phase 7C).
public enum RendererChoice: String, Codable, CaseIterable, Sendable {
    case dxmt, dxvk, wined3d
}

/// Dormison's `LinearMouse`.
public enum MouseCurve: String, Codable, CaseIterable, Sendable {
    case system, linear
}

/// How the engine's threads wait for each other (Sevoflurane's PerformanceTuning).
public enum PerformanceTuning: String, Codable, CaseIterable, Sendable {
    case standard, experimental, custom

    public func parameters(custom: TuningParameters?) -> TuningParameters {
        switch self {
        case .standard: .standard
        case .experimental: .experimental
        case .custom: custom ?? .experimental
        }
    }
}

/// The three spin budgets behind PerformanceTuning. One iteration is about 0.4 ns,
/// so 5200 is two microseconds; the engine caps a spin at 1 000 000.
public struct TuningParameters: Codable, Equatable, Sendable {
    public var waitSpin: Int
    public var adaptive: Bool
    public var objectSpin: Int

    public init(waitSpin: Int, adaptive: Bool, objectSpin: Int) {
        self.waitSpin = waitSpin
        self.adaptive = adaptive
        self.objectSpin = objectSpin
    }

    public static let standard = TuningParameters(waitSpin: 0, adaptive: false, objectSpin: 0)
    public static let experimental = TuningParameters(waitSpin: 5200, adaptive: true, objectSpin: 5200)
    public static let spinRange = 0...1_000_000

    private static func clamped(_ spin: Int) -> Int {
        min(max(spin, spinRange.lowerBound), spinRange.upperBound)
    }

    /// Every key, always: a game's file is read over the bottle's, and an absent
    /// key would leave the bottle's value standing.
    public var environment: [(key: String, value: String)] {
        [
            ("SEVO_WAIT_SPIN", "\(Self.clamped(waitSpin))"),
            ("SEVO_WAIT_SPIN_ADAPT", adaptive ? "1" : "0"),
            ("SEVO_OBJECT_SPIN", "\(Self.clamped(objectSpin))"),
        ]
    }
}

/// The graphics card a game is told it runs on. Dormison names it to the game through
/// `SEVO_GPU_*` (win32u, wined3d); DXMT reports its own adapter, so the same ids go to
/// its `dxgi.customVendorId`/`customDeviceId`. Presets match cards in Dormison's
/// wined3d table (`dlls/wined3d/directx.c`).
public enum GPUPreset: String, Codable, CaseIterable, Sendable {
    case asIs = "as-is"
    case amd
    case nvidia
    case intelArc = "intel-arc-a750"
    case custom

    public var identity: GPUIdentity? {
        switch self {
        case .asIs, .custom: nil
        case .amd: GPUIdentity(vendorID: 0x1002, deviceID: 0x744c, name: "AMD Radeon RX 7900 XT", memoryMB: 20480)
        case .nvidia: GPUIdentity(vendorID: 0x10de, deviceID: 0x2c02, name: "NVIDIA GeForce RTX 5080", memoryMB: 16384)
        case .intelArc: GPUIdentity(vendorID: 0x8086, deviceID: 0x56a1, name: "Intel(R) Arc(TM) A750 Graphics", memoryMB: 8192)
        }
    }
}

public struct GPUIdentity: Codable, Equatable, Sendable {
    public var vendorID: Int
    public var deviceID: Int
    public var name: String
    public var memoryMB: Int?

    public init(vendorID: Int, deviceID: Int, name: String, memoryMB: Int? = nil) {
        self.vendorID = vendorID
        self.deviceID = deviceID
        self.name = name
        self.memoryMB = memoryMB
    }

    var isValid: Bool {
        (0...0xffff).contains(vendorID) && (0...0xffff).contains(deviceID)
            && !name.contains("\n") && !name.contains(";") && name.count <= 128
            && (memoryMB.map { (0...262_144).contains($0) } ?? true)
    }
}

/// One level of the hierarchy. A nil field inherits from the level above.
public struct ConfigValues: Codable, Equatable, Sendable {
    public var renderer: RendererChoice?
    public var retina: Bool?
    public var upscaler: UpscalerChoice?
    public var fps: Bool?
    /// Frames per second the renderer holds the game to; 0 is no limit.
    public var fpsLimit: Int?
    public var windows: WindowTreatment?
    public var filter: FinalFilter?
    public var emulateModeset: Bool?
    public var fpsGraph: Bool?
    public var hud: Bool?
    public var dlss: Bool?
    public var mouse: MouseCurve?
    public var cursorConfine: Bool?
    public var tuning: PerformanceTuning?
    public var tuningParameters: TuningParameters?
    /// 0 is every processor.
    public var processors: Int?
    public var unifiedMemory: Bool?
    public var largeAddressAware: Bool?
    public var avx: Bool?
    public var gpu: GPUPreset?
    public var gpuCustom: GPUIdentity?
    /// Per DLL, Wine's load order: `n,b`, `b,n`, `n`, `b`, or "" for disabled.
    public var dllOverrides: [String: String]?
    /// Extra `KEY=VALUE` lines, in order.
    public var environment: [String]?
    public var commandIsControl: Bool?
    public var optionIsAlt: Bool?
    /// Game level only, a debugging switch: msync+ stays on otherwise.
    public var msync: Bool?

    /// Game level only: the lowercase executables the game is known to run.
    public var exes: [String]?
    /// Game level only: the name, for logs and the panel.
    public var name: String?

    public init() {}

    public static let empty = ConfigValues()

    /// Whether any setting is set at this level (exes and name are bookkeeping).
    public var hasSettings: Bool {
        var copy = self
        copy.exes = nil
        copy.name = nil
        return copy != .empty
    }
}

/// What every level inherits when nothing is set anywhere: NotProton's profile
/// (DECISIONS P7A-3). Sevoflurane defaults differ where noted there.
public enum ConfigDefaults {
    public static let values: ConfigValues = {
        var v = ConfigValues()
        v.renderer = .dxmt
        v.retina = false
        v.upscaler = .off
        v.fps = false
        v.fpsLimit = 0
        v.windows = .fixed
        v.filter = .lanczos
        v.emulateModeset = false
        v.fpsGraph = false
        v.hud = false
        v.dlss = false
        v.mouse = .system
        v.cursorConfine = false
        v.tuning = .standard
        v.processors = 0
        v.unifiedMemory = false
        v.largeAddressAware = false
        v.avx = false
        v.gpu = .asIs
        v.dllOverrides = [:]
        v.environment = []
        v.commandIsControl = false
        v.optionIsAlt = false
        v.msync = true
        return v
    }()
}

/// A setting's value together with the level that supplied it.
public enum ConfigLevel: String, Codable, Sendable {
    case defaults, global, game
}

/// The two levels a game resolves through, read once.
public struct ConfigStack: Sendable, Equatable {
    public var global: ConfigValues
    public var game: ConfigValues

    public init(global: ConfigValues, game: ConfigValues = .empty) {
        self.global = global
        self.game = game
    }

    public func value<T>(_ key: KeyPath<ConfigValues, T?>) -> (value: T, level: ConfigLevel) {
        if let own = game[keyPath: key] { return (own, .game) }
        if let shared = global[keyPath: key] { return (shared, .global) }
        return (ConfigDefaults.values[keyPath: key]!, .defaults)
    }

    public subscript<T>(_ key: KeyPath<ConfigValues, T?>) -> T { value(key).value }

    /// The global level alone, as bottle.env carries it.
    public var globalOnly: ConfigStack { ConfigStack(global: global) }
}
