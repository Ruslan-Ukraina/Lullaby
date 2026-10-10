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

    @Test("the four quick settings, in order; the Advanced groups, old games apart")
    func quickSettings() {
        #expect(SettingCatalog.quick.map(\.id) == [.renderer, .retina, .upscaler, .fps])
        #expect(SettingCatalog.setting(.renderer).levels == [.game])
        #expect(SettingCatalog.setting(.msync).levels == [.game])
        func advanced(_ group: SettingGroup) -> [SettingID] {
            SettingCatalog.settings(in: group, at: .game).filter { $0.quick == nil }.map(\.id)
        }
        #expect(advanced(.picture) == [.windows, .filter, .dlss])
        #expect(advanced(.mouse) == [.mouse])
        #expect(advanced(.performance) == [.tuning, .unifiedMemory, .avx])
        #expect(advanced(.oldGames) == [.emulateModeset, .largeAddressAware])
        #expect(advanced(.diagnostics) == [.msync])
    }

    /// A value other than the default for each setting, and a key it must reach.
    static let samples: [(SettingID, JSONValue, String)] = [
        (.renderer, .string("dxvk"), "LULLABY_RENDERER=dxvk"),
        (.retina, .bool(true), "LULLABY_RETINA=1"),
        (.upscaler, .string("metalfx"), "SEVO_UPSCALER=metalfx"),
        (.fps, .bool(true), "MTL_HUD_ENABLED=1"),
        (.windows, .string("all"), "SEVO_RESIZABLE_WINDOWS=all"),
        (.filter, .string("nearest"), "SEVO_FINAL_FILTER=nearest"),
        (.dlss, .bool(true), "DXMT_ENABLE_NVEXT=1"),
        (.mouse, .string("linear"), "SEVO_LINEAR_MOUSE=1"),
        (.tuning, .string("experimental"), "SEVO_WAIT_SPIN=5200"),
        (.unifiedMemory, .bool(true), "SEVO_FORCE_UMA=1"),
        (.avx, .bool(true), "ROSETTA_ADVERTISE_AVX=1"),
        (.emulateModeset, .bool(true), "LULLABY_EMULATE_MODESET=1"),
        (.largeAddressAware, .bool(true), "SEVO_LARGE_ADDRESS_AWARE=1"),
    ]

    @Test("every game setting reaches its key, and inherit writes none")
    func gameLinesPerSetting() throws {
        #expect(Set(Self.samples.map(\.0)).union([.msync]) == Set(SettingID.allCases))
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
        game.largeAddressAware = false
        let lines = ConfigMaterializer.gameLines(appID: 1, stack: ConfigStack(global: global, game: game))
        #expect(lines.contains("MTL_HUD_ENABLED=1"))
        #expect(lines.contains("SEVO_LARGE_ADDRESS_AWARE=0"))
        #expect(!lines.contains { $0.hasPrefix("ROSETTA_ADVERTISE_AVX=") }, "an inherited switch is not written")

        let bottle = ConfigMaterializer.bottleLines(global: global, msync: true, cli: "/x/sevo")
        #expect(bottle.contains("MTL_HUD_ENABLED=1"))
        #expect(bottle.contains("SEVO_FPS=0"), "Dormison's own counter stays off")
        #expect(bottle.contains("SEVO_FPS_GRAPH=0"))
        #expect(bottle.contains("SEVO_CLI=/x/sevo"))
        #expect(bottle.contains("LULLABY_MSYNC=1"))
        let env = ConfigMaterializer.effectiveEnvironment(bottle: bottle, program: lines)
        #expect(env["SEVO_LARGE_ADDRESS_AWARE"] == "0")
        #expect(env["MTL_HUD_ENABLED"] == "1")
    }

    @Test("the card follows DLSS: AMD by default, NVIDIA with DLSS, in every layer")
    func graphicsCardFollowsDLSS() throws {
        var global = ConfigValues()
        try SettingCatalog.setting(.dlss).write(&global, .bool(true))
        var game = ConfigValues()
        let shared = ConfigMaterializer.effectiveEnvironment(
            bottle: ConfigMaterializer.bottleLines(global: global, msync: true, cli: nil),
            program: ConfigMaterializer.gameLines(appID: 7, stack: ConfigStack(global: global, game: game)))
        #expect(shared["SEVO_GPU_VENDOR_ID"] == "0x10DE")
        #expect(shared["SEVO_GPU_DEVICE_ID"] == "0x2D04")
        #expect(shared["SEVO_GPU_NAME"] == "NVIDIA GeForce RTX 5060 Ti")
        #expect(shared["SEVO_GPU_DRIVER_VERSION"] == "32.0.16.1088")
        #expect(shared["D3DM_DEVICE_ID"] == "0x2D04")
        #expect(shared["DXMT_ENABLE_NVEXT"] == "1")
        #expect(shared["DXMT_CONFIG"]?.contains("dxgi.customDeviceId = 2d04") == true)

        // The game turns DLSS off: its own file names the AMD card over the shared NVIDIA.
        try SettingCatalog.setting(.dlss).write(&game, .bool(false))
        let own = ConfigMaterializer.effectiveEnvironment(
            bottle: ConfigMaterializer.bottleLines(global: global, msync: true, cli: nil),
            program: ConfigMaterializer.gameLines(appID: 7, stack: ConfigStack(global: global, game: game)))
        #expect(own["SEVO_GPU_VENDOR_ID"] == "0x1002")
        #expect(own["SEVO_GPU_DEVICE_ID"] == "0x7590")
        #expect(own["SEVO_GPU_NAME"] == "AMD Radeon RX 9060 XT")
        #expect(own["SEVO_GPU_DRIVER_PROVIDER"] == "Advanced Micro Devices, Inc.")
        #expect(own["D3DM_DEVICE_DESCRIPTION"] == "AMD Radeon RX 9060 XT")
        #expect(own["DXMT_ENABLE_NVEXT"] == nil)
        #expect(own["DXVK_CONFIG_FILE"] == #"C:\windows\dxvk.conf"#)
        #expect(ConfigMaterializer.dxgiConfig(.amd)
            == #"dxgi.customVendorId = 1002; dxgi.customDeviceId = 7590; dxgi.customDeviceDesc = "AMD Radeon RX 9060 XT"; dxgi.maxDeviceMemory = 16384"#)
    }

    @Test("values outside a setting are refused")
    func invalidValues() {
        var values = ConfigValues()
        let bad: [(SettingID, JSONValue)] = [
            (.fps, .string("yes")), (.renderer, .string("vulkan")), (.windows, .number(1)),
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
        game.renderer = .dxmt
        game.avx = true
        game.exes = ["a.exe"]
        let kept = SettingCatalog.withoutInherited(game, level: .game, global: global)
        #expect(kept.retina == nil, "the shared value")
        #expect(kept.renderer == nil, "NotProton's default renderer")
        #expect(kept.avx == true)
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

    @Test("defaults reproduce NotProton's profile, as the engine reads it")
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
        #expect(env["SEVO_GPU_VENDOR_ID"] == "0x1002", "games see the AMD card by default")
        #expect(env["MTL_HUD_ENABLED"] == "0")
    }
}
