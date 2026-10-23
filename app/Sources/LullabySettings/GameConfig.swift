// The settings hierarchy Lullaby keeps for Dormison: one level for every game
// ("for all games") and one per Steam app id. A game is an app id, not an
// executable: the levels are stored by app id and written into the env file of
// every executable the game is known to run (ConfigMaterializer).
//
// The value types and the inheritance rules follow Sevoflurane's Core/GameConfig.swift
// (MIT, Copyright (c) 2026 kageroumado), adapted to Lullaby: one prefix per game,
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

/// Dormison's frame limiter (`SEVO_FPS_LIMIT`, winemac `sevo_limiter`): frames on the screen
/// per second, generated ones included.
public enum FrameLimit: String, Codable, CaseIterable, Sendable {
    case off
    case f30 = "30", f40 = "40", f45 = "45", f50 = "50", f60 = "60"
    case f80 = "80", f90 = "90", f100 = "100", f120 = "120"

    /// The env value: 0 is no limit.
    public var envValue: String { self == .off ? "0" : rawValue }
}

/// How much of GCMouse's raw device counts reach the game (LULLABY_GCMOUSE_SCALE): the counts are
/// several times larger than the engine's own mouse path, so the default is 30 % (calibrated on the
/// owner's mouse in RE9, 2026-10-19; it depends on the mouse's resolution and is not universal).
public enum RawMouseScale: String, Codable, CaseIterable, Sendable {
    case p10 = "0.1", p20 = "0.2", p30 = "0.3", p50 = "0.5", p75 = "0.75", p100 = "1"
}

/// Dormison's `Upscaler`. Anime4K and CuNNy come with shader packages, which this
/// engine build does not ship (SEVO_SHADER_DIR), so they are not offered yet.
public enum UpscalerChoice: String, Codable, CaseIterable, Sendable {
    case off, lanczos, metalfx
}

/// DXMT's MetalFX upscaler on the swapchain (`DXMT_METALFX_SPATIAL_SWAPCHAIN`,
/// `d3d11.metalSpatialUpscaleFactor`, dxmt `src/d3d11/d3d11_swapchain.cpp`): the game
/// draws at its own size and the window gets that picture enlarged by the factor.
public enum SwapchainUpscale: String, Codable, CaseIterable, Sendable {
    // NotProton's choices (steam/hook/feats/webpatch.c upstream, "MetalFX Upscaling").
    case off
    case x1_5 = "1.5"
    case x1_72 = "1.72"
    case x2 = "2"
    case x3 = "3"

    /// The factor in DXMT's config, nil when off.
    public var factor: String? {
        switch self {
        case .off: nil
        case .x1_5: "1.5"
        case .x1_72: "1.72"
        case .x2: "2.0"
        case .x3: "3.0"
        }
    }
}

/// Dormison's `FinalFilter`.
public enum FinalFilter: String, Codable, CaseIterable, Sendable {
    case nearest, bilinear, lanczos
}

/// The picture's last step as the player sees it (SettingCatalog.pictureFilterSetting): nothing
/// (macOS stretches the picture), a final filter of Dormison's presenter, or MetalFX Spatial.
public enum PictureFilter: String, Codable, CaseIterable, Sendable {
    case off, nearest, bilinear, lanczos, metalfx

    /// The pair of stored values a level holds; nil when neither is set.
    init?(upscaler: UpscalerChoice?, filter: FinalFilter?) {
        switch (upscaler, filter) {
        case (nil, _): return nil
        case (.off?, _): self = .off
        case (.metalfx?, _): self = .metalfx
        case let (.lanczos?, filter): self = filter.flatMap { PictureFilter(rawValue: $0.rawValue) } ?? .lanczos
        }
    }

    /// Dormison's `Upscaler` for this choice.
    public var upscaler: UpscalerChoice {
        switch self {
        case .off: .off
        case .metalfx: .metalfx
        case .nearest, .bilinear, .lanczos: .lanczos
        }
    }

    /// Dormison's `FinalFilter` for this choice; nil leaves the default (Lanczos).
    public var finalFilter: FinalFilter? { FinalFilter(rawValue: rawValue) }
}

/// What draws Direct3D. D3DMetal (Direct3D 11 and 12) is offered once the player has
/// added Apple's Game Porting Toolkit (D3DMetalStore).
public enum RendererChoice: String, Codable, CaseIterable, Sendable {
    case d3dmetal, dxmt, dxvk, wined3d
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

/// The graphics card a game is told it runs on, chosen by Lullaby rather than by the
/// player: an AMD card, and an NVIDIA one while DLSS → MetalFX is on, since games offer
/// DLSS only on NVIDIA. Both match an M4 Pro the way Sevoflurane's Core/GPUEquivalence.swift
/// does (MIT, Copyright (c) 2026 kageroumado), and both are in Dormison's tables
/// (`dlls/win32u/sysparams.c`, `dlls/wined3d/directx.c`). The driver strings are
/// Sevoflurane's too: a game that checks the driver reads the vendor's own shape.
public struct GPUIdentity: Codable, Equatable, Sendable {
    public var vendorID: Int
    public var deviceID: Int
    public var name: String
    public var memoryMB: Int
    public var driverVersion: String
    public var driverDate: String
    public var driverProvider: String

    /// AMD Radeon RX 9060 XT, AMD Software: Adrenalin Edition 26.8.1.
    public static let amd = GPUIdentity(
        vendorID: 0x1002, deviceID: 0x7590, name: "AMD Radeon RX 9060 XT", memoryMB: 16384,
        driverVersion: "32.0.26081.1001", driverDate: "8-12-2026", driverProvider: "Advanced Micro Devices, Inc.")

    /// NVIDIA GeForce RTX 5060 Ti, GeForce Game Ready 610.88.
    public static let nvidia = GPUIdentity(
        vendorID: 0x10de, deviceID: 0x2d04, name: "NVIDIA GeForce RTX 5060 Ti", memoryMB: 16384,
        driverVersion: "32.0.16.1088", driverDate: "8-3-2026", driverProvider: "NVIDIA")

    /// The card for a game with DLSS → MetalFX on or off.
    public static func forGame(dlss: Bool) -> GPUIdentity { dlss ? .nvidia : .amd }
}

/// One level of the hierarchy. A nil field inherits from the level above.
public struct ConfigValues: Codable, Equatable, Sendable {
    public var renderer: RendererChoice?
    public var retina: Bool?
    public var upscaler: UpscalerChoice?
    /// DXMT's MetalFX on the swapchain; DXMT only.
    public var metalfx: SwapchainUpscale?
    /// Apple's Metal HUD (MTL_HUD_ENABLED), the panel's frame rate counter.
    public var fps: Bool?
    public var windows: WindowTreatment?
    public var filter: FinalFilter?
    public var emulateModeset: Bool?
    public var dlss: Bool?
    public var mouse: MouseCurve?
    /// Mouse movement through GameController as raw input (winemac patch 0004; an experiment).
    public var rawMouse: Bool?
    public var rawMouseScale: RawMouseScale?
    public var tuning: PerformanceTuning?
    public var tuningParameters: TuningParameters?
    public var unifiedMemory: Bool?
    public var largeAddressAware: Bool?
    public var avx: Bool?
    /// macOS Game Mode for the game's bundle; off keeps streaming apps at full speed.
    public var gameMode: Bool?
    /// Frames on the screen per second at most (Dormison's limiter); off for none.
    public var frameLimit: FrameLimit?
    /// Game level only, a debugging switch: msync+ stays on otherwise.
    public var msync: Bool?
    /// The D3DMetal layer stays in step with the display (winemac.so fix 0003).
    public var forceVsync: Bool?
    /// NVIDIA Reflex by Lullaby's nvapi64.dll, fed by the D3DMetal layer (winemac.so fix 0003).
    public var lowLatency: Bool?

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

/// What every level inherits when nothing is set anywhere: Lullaby's profile
/// (DECISIONS P7A-3). Sevoflurane defaults differ where noted there.
public enum ConfigDefaults {
    public static let values: ConfigValues = {
        var v = ConfigValues()
        v.renderer = .dxmt
        v.retina = false
        v.upscaler = .off
        v.metalfx = .off
        v.fps = false
        v.windows = .fixed
        v.filter = .lanczos
        v.emulateModeset = false
        v.dlss = false
        v.mouse = .system
        v.rawMouse = true
        v.rawMouseScale = .p30
        v.tuning = .standard
        v.unifiedMemory = true
        v.largeAddressAware = true
        v.avx = false
        v.gameMode = true
        v.frameLimit = .off
        v.msync = true
        v.forceVsync = false
        v.lowLatency = false
        return v
    }()
}

/// A setting's value together with the level that supplied it.
public enum ConfigLevel: String, Codable, Sendable {
    case defaults, global, recipe, game
}

/// The two levels a game resolves through, read once.
public struct ConfigStack: Sendable, Equatable {
    public var global: ConfigValues
    /// Lullaby's recipe for the game (GameRecipes), between its own values and global.
    public var recipe: ConfigValues
    public var game: ConfigValues
    /// Extra lines of the catalog's fix (variables, DLL overrides) for the program's file.
    public var fixLines: [String]

    public init(global: ConfigValues, recipe: ConfigValues = .empty, game: ConfigValues = .empty,
                fixLines: [String] = []) {
        self.global = global
        self.recipe = recipe
        self.game = game
        self.fixLines = fixLines
    }

    public func value<T>(_ key: KeyPath<ConfigValues, T?>) -> (value: T, level: ConfigLevel) {
        if let own = game[keyPath: key] { return (own, .game) }
        if let suggested = recipe[keyPath: key] { return (suggested, .recipe) }
        if let shared = global[keyPath: key] { return (shared, .global) }
        return (ConfigDefaults.values[keyPath: key]!, .defaults)
    }

    public subscript<T>(_ key: KeyPath<ConfigValues, T?>) -> T { value(key).value }

    /// The global level alone, as bottle.env carries it.
    public var globalOnly: ConfigStack { ConfigStack(global: global) }

    /// What a game's own value is measured against: the recipe over global.
    public var inheritedByGame: ConfigStack { ConfigStack(global: global, recipe: recipe) }

    /// The game level as its programs' files carry it: its own values over the recipe's.
    public var gameWithRecipe: ConfigValues {
        var merged = game
        for setting in SettingCatalog.all where setting.read(merged) == nil {
            if let suggested = setting.read(recipe) { try? setting.write(&merged, suggested) }
        }
        if merged.tuningParameters == nil { merged.tuningParameters = recipe.tuningParameters }
        return merged
    }
}
