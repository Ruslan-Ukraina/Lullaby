// The catalog against the lines it writes: every setting reaches an env or registry
// key, "inherit" writes nothing, a game's own switch is explicit, and the engine ends
// up with what the levels say (docs/ROADMAP.md §5.5).

import Foundation
import Testing
@testable import LullabySettings

@Suite("Setting catalog")
struct SettingCatalogTests {

    @Test("every setting is in the catalog once, with a carrier and a level")
    func catalogIsComplete() {
        let ids = SettingCatalog.all.map(\.id)
        #expect(Set(ids) == Set(SettingID.allCases))
        #expect(ids.count == SettingID.allCases.count)
        for setting in SettingCatalog.all {
            #expect(!setting.levels.isEmpty, "\(setting.id)")
            #expect(!setting.carrier.envKeys.isEmpty, "\(setting.id) reaches no key")
        }
    }

    @Test("the four quick settings, in order; the Advanced groups: what is automatic has no row")
    func quickSettings() {
        #expect(SettingCatalog.quick.map(\.id) == [.renderer, .retina, .fps])
        #expect(SettingCatalog.setting(.renderer).levels == [.game])
        func advanced(_ group: SettingGroup) -> [SettingID] {
            SettingCatalog.settings(in: group, at: .game).filter { $0.quick == nil }.map(\.id)
        }
        #expect(advanced(.picture) == [.filter])
        #expect(advanced(.performance) == [.tuning, .gameMode])
        #expect(advanced(.diagnostics) == [.unifiedMemory, .rawMouse, .forceVsync])
        #expect(SettingGroup.allCases == [.picture, .performance, .diagnostics])
    }

    /// A value other than the default for each setting, and a key it must reach.
    static let samples: [(SettingID, JSONValue, String)] = [
        (.renderer, .string("dxvk"), "LULLABY_RENDERER=dxvk"),
        (.retina, .bool(true), "LULLABY_RETINA=1"),
        (.filter, .string("metalfx"), "SEVO_UPSCALER=metalfx"),
        (.fps, .bool(true), "MTL_HUD_ENABLED=1"),
        (.filter, .string("bilinear"), "SEVO_FINAL_FILTER=bilinear"),
        (.rawMouse, .bool(false), "LULLABY_GCMOUSE=0"),
        (.tuning, .string("experimental"), "SEVO_WAIT_SPIN=5200"),
        (.unifiedMemory, .bool(false), "SEVO_FORCE_UMA=0"),
        (.gameMode, .bool(false), "LULLABY_GAME_MODE=0"),
        (.forceVsync, .bool(true), "LULLABY_FORCE_VSYNC=1"),
    ]

    @Test("every game setting reaches its key, and inherit writes none")
    func gameLinesPerSetting() throws {
        #expect(Set(Self.samples.map(\.0)) == Set(SettingID.allCases))
        for (id, value, line) in Self.samples {
            var game = ConfigValues()
            try SettingCatalog.setting(id).write(&game, value)
            let lines = ConfigMaterializer.gameLines(appID: 1, stack: ConfigStack(global: .empty, game: game))
            #expect(lines.contains(line), "\(id): \(lines)")
            #expect(SettingCatalog.setting(id).read(game) != nil, "\(id) reads back")

            try SettingCatalog.setting(id).write(&game, nil)
            #expect(game == .empty, "\(id) inherits again")
            let inherited = ConfigMaterializer.gameLines(appID: 1, stack: ConfigStack(global: .empty, game: game))
            #expect(inherited == ["# app 1"], "\(id): \(inherited)")
        }
    }

    @Test("every global setting reaches bottle.env")
    func bottleLinesPerSetting() throws {
        for (id, value, line) in Self.samples where SettingCatalog.setting(id).levels.contains(.global) {
            var global = ConfigValues()
            try SettingCatalog.setting(id).write(&global, value)
            let lines = ConfigMaterializer.bottleLines(global: global, msync: true, cli: nil)
            #expect(lines.contains(line), "\(id): \(lines)")
        }
    }

    @Test("a game's switch equal to the shared value is still written, =0 included")
    func explicitSwitches() throws {
        var global = ConfigValues()
        global.fps = true
        var game = ConfigValues()
        game.fps = true
        game.gameMode = false
        let lines = ConfigMaterializer.gameLines(appID: 1, stack: ConfigStack(global: global, game: game))
        #expect(lines.contains("MTL_HUD_ENABLED=1"))
        #expect(lines.contains("LULLABY_GAME_MODE=0"))
        #expect(!lines.contains { $0.hasPrefix("ROSETTA_ADVERTISE_AVX=") }, "an inherited switch is not written")

        let bottle = ConfigMaterializer.bottleLines(global: global, msync: true, cli: "/x/sevo")
        #expect(bottle.contains("MTL_HUD_ENABLED=1"))
        #expect(bottle.contains("SEVO_FPS=0"), "Dormison's own counter stays off")
        #expect(bottle.contains("SEVO_FPS_GRAPH=0"))
        #expect(bottle.contains("SEVO_CLI=/x/sevo"))
        #expect(bottle.contains("LULLABY_MSYNC=1"))
        let env = ConfigMaterializer.effectiveEnvironment(bottle: bottle, program: lines)
        #expect(env["LULLABY_GAME_MODE"] == "0")
        #expect(env["MTL_HUD_ENABLED"] == "1")
    }

    @Test("what is automatic is the same for every game, whatever an older version stored")
    func automaticSettings() throws {
        var global = ConfigValues()
        global.frameLimit = .f60
        global.mouse = .linear
        global.rawMouseScale = .p100
        global.largeAddressAware = false
        global.lowLatency = false
        global.emulateModeset = true
        var game = global
        game.name = "x"
        let bottle = ConfigMaterializer.bottleLines(global: global, msync: true, cli: nil)
        let program = ConfigMaterializer.gameLines(appID: 1, stack: ConfigStack(global: global, game: game))
        let env = ConfigMaterializer.effectiveEnvironment(bottle: bottle, program: program)
        #expect(env["SEVO_FPS_LIMIT"] == "0", "no frame limit")
        #expect(env["SEVO_LINEAR_MOUSE"] == "0")
        #expect(env["LULLABY_GCMOUSE_SCALE"] == "auto", "from the mouse's resolution")
        #expect(env["SEVO_RESIZABLE_WINDOWS"] == "fixed", "a fixed-size window is scaled; a game that covers the screen stays as it is (native full screen is postponed)")
        #expect(env["LULLABY_NATIVE_FULLSCREEN"] == "0", "native full screen of a covering game is postponed: off, no setting")
        #expect(env["SEVO_LARGE_ADDRESS_AWARE"] == "1", "4 GB for 32-bit games")
        #expect(env["LULLABY_LOW_LATENCY"] == "1", "Reflex is always answered (it no longer costs frames)")
        #expect(env["LULLABY_EMULATE_MODESET"] == nil, "compat_run.sh decides by the program's bitness")
        #expect(!program.contains { $0.hasPrefix("SEVO_FPS_LIMIT") || $0.hasPrefix("LULLABY_LOW_LATENCY") })
    }

    @Test("defaults: GameController mouse and unified memory on; Reflex and 4 GB are no choices")
    func automaticDefaults() {
        let stack = ConfigStack(global: .empty)
        #expect(stack[\.rawMouse] && stack[\.unifiedMemory])
        let env = ConfigMaterializer.effectiveEnvironment(
            bottle: ConfigMaterializer.bottleLines(global: .empty, msync: true, cli: nil), program: [])
        #expect(env["LULLABY_GCMOUSE"] == "1" && env["SEVO_FORCE_UMA"] == "1")
        #expect(env["SEVO_UPSCALER"] == "off", "the final filter stays off until chosen")
    }

    @Test("the final filter is one row over the upscaler and the filter")
    func finalFilterRow() throws {
        let setting = SettingCatalog.setting(.filter)
        #expect(setting.group == .picture)
        var values = ConfigValues()
        #expect(setting.read(values) == nil)
        for (choice, upscaler, filter): (String, String, String?) in [
            ("off", "off", nil), ("bilinear", "lanczos", "bilinear"),
            ("lanczos", "lanczos", "lanczos"), ("metalfx", "metalfx", nil),
        ] {
            try setting.write(&values, .string(choice))
            #expect(values.upscaler?.rawValue == upscaler, "\(choice)")
            #expect(values.filter?.rawValue == filter, "\(choice)")
            #expect(setting.read(values) == .string(choice), "\(choice) reads back")
        }
        try setting.write(&values, nil)
        #expect(values == .empty)
        #expect(throws: SettingsError.self) { try setting.write(&values, .string("anime4k")) }
        #expect(throws: SettingsError.self, "Nearest is not offered") { try setting.write(&values, .string("nearest")) }
        // A Nearest stored by an older version reads as Lanczos.
        values.upscaler = .lanczos
        values.filter = .nearest
        #expect(setting.read(values) == .string("lanczos"))
        if case let .choice(choices) = setting.control {
            #expect(choices.map { $0.label.en } == ["Off", "Bilinear", "Lanczos", "MetalFX Spatial"])
        }
    }

    @Test("every game gets the same NVIDIA card under the Mac's chip name, in every layer")
    func graphicsCardIsOneNVIDIAUnderTheChipName() throws {
        let chip = GPUIdentity.chipName
        #expect(chip.hasPrefix("Apple"))
        var game = ConfigValues()
        game.dlss = false   // an older version's value changes nothing
        let env = ConfigMaterializer.effectiveEnvironment(
            bottle: ConfigMaterializer.bottleLines(global: .empty, msync: true, cli: nil),
            program: ConfigMaterializer.gameLines(appID: 7, stack: ConfigStack(global: .empty, game: game)))
        #expect(env["SEVO_GPU_VENDOR_ID"] == "0x10DE")
        #expect(env["SEVO_GPU_DEVICE_ID"] == "0x2D04")
        #expect(env["SEVO_GPU_NAME"] == chip)
        #expect(env["SEVO_GPU_DRIVER_VERSION"] == "32.0.16.1088")
        #expect(env["SEVO_GPU_DRIVER_PROVIDER"] == "NVIDIA")
        #expect(env["D3DM_VENDOR_ID"] == "0x10DE")
        #expect(env["D3DM_DEVICE_DESCRIPTION"] == chip)
        #expect(env["DXMT_ENABLE_NVEXT"] == "1")
        #expect(env["D3DM_ENABLE_METALFX"] == "1")
        #expect(env["LULLABY_DLSS"] == "1")
        #expect(env["ROSETTA_ADVERTISE_AVX"] == "1")
        #expect(env["DXMT_METALFX_SPATIAL_SWAPCHAIN"] == "0")
        #expect(env["WINEMSYNC"] == nil, "WINEMSYNC is the server's: written beside bottle.env by write()")
        #expect(env["DXMT_CONFIG"]?.contains("dxgi.customDeviceId = 2d04") == true)
        #expect(env["DXMT_CONFIG"]?.contains("dxgi.customDeviceDesc = \"\(chip)\"") == true)
        #expect(env["DXVK_CONFIG_FILE"] == #"C:\windows\dxvk.conf"#)
        #expect(ConfigMaterializer.dxgiConfig(.current)
            == "dxgi.customVendorId = 10de; dxgi.customDeviceId = 2d04; dxgi.customDeviceDesc = \"\(chip)\"; dxgi.maxDeviceMemory = 16384")
    }

    @Test("values outside a setting are refused")
    func invalidValues() {
        var values = ConfigValues()
        let bad: [(SettingID, JSONValue)] = [
            (.fps, .string("yes")), (.renderer, .string("vulkan")),
            (.tuning, .object(["preset": .string("custom"), "waitSpin": .number(2_000_000)])),
        ]
        for (id, value) in bad {
            #expect(throws: SettingsError.self, "\(id) \(value.text)") {
                try SettingCatalog.setting(id).write(&values, value)
            }
        }
        #expect(values == .empty)
    }

    @Test("a value equal to what the level inherits is no value of its own")
    func withoutInherited() throws {
        var global = ConfigValues()
        global.retina = true
        var game = ConfigValues()
        game.retina = true
        game.renderer = .auto
        game.gameMode = false
        game.exes = ["a.exe"]
        let kept = SettingCatalog.withoutInherited(game, level: .game, global: global)
        #expect(kept.retina == nil, "the shared value")
        #expect(kept.renderer == nil, "Lullaby's default renderer, Auto")
        #expect(kept.gameMode == false)
        #expect(kept.exes == ["a.exe"])
        #expect(SettingCatalog.withoutInherited(global, level: .global, global: .empty).retina == true)
    }
    @Test("tuning keeps its custom parameters per level")
    func tuning() throws {
        var game = ConfigValues()
        try SettingCatalog.setting(.tuning).write(&game, .object([
            "preset": .string("custom"), "waitSpin": .number(100), "adaptive": .bool(false), "objectSpin": .number(7),
        ]))
        let lines = ConfigMaterializer.gameLines(appID: 1, stack: ConfigStack(global: .empty, game: game))
        #expect(lines.contains("SEVO_WAIT_SPIN=100"))
        #expect(lines.contains("SEVO_WAIT_SPIN_ADAPT=0"))
        #expect(lines.contains("SEVO_OBJECT_SPIN=7"))
        try SettingCatalog.setting(.tuning).write(&game, .string("standard"))
        #expect(game.tuningParameters == nil)
    }

    @Test("a store written with settings since removed still reads")
    func removedSettingsDecode() throws {
        let old = #"{"commandIsControl":true,"optionIsAlt":false,"fps":true,"fpsLimit":60,"exes":["a.exe"]}"#
        let values = try JSONDecoder().decode(ConfigValues.self, from: Data(old.utf8))
        #expect(values.fps == true)
        #expect(values.exes == ["a.exe"])
        let lines = ConfigMaterializer.gameLines(appID: 1, stack: ConfigStack(global: .empty, game: values))
        #expect(!lines.contains { $0.contains("COMMAND") || $0.contains("OPTION") })
    }

    @Test("defaults reproduce Lullaby's profile, as the engine reads it")
    func defaultsMatchTheOldProfile() {
        let bottle = ConfigMaterializer.bottleLines(global: .empty, msync: true, cli: nil)
        let env = ConfigMaterializer.effectiveEnvironment(bottle: bottle, program: [])
        // "1" and "fixed" are one value to winemac.drv (resizable_windows_from_option).
        #expect(WindowTreatment(option: "1") == WindowTreatment(option: env["SEVO_RESIZABLE_WINDOWS"]!))
        // The pointer confinement left the catalog; the engine's default is off.
        for (key, value) in ConfigMigration.oldProfile where key != "SEVO_RESIZABLE_WINDOWS" && key != "SEVO_CURSOR_CONFINE" {
            #expect(env[key] == value, "\(key)")
        }
        #expect(env["SEVO_CPU_COUNT"] == nil)
        #expect(env["SEVO_GPU_VENDOR_ID"] == "0x10DE", "games see the NVIDIA card by default, under the chip's name")
        #expect(env["MTL_HUD_ENABLED"] == "0")
    }
}
