// The catalog against the lines it writes: every setting reaches an env or registry
// key, "inherit" writes nothing, a game's own switch is explicit, and the engine ends
// up with what the levels say (docs/ROADMAP.md §5.5).

import Foundation
import Testing
@testable import NotProtonSettings

@Suite("Setting catalog")
struct SettingCatalogTests {

    @Test("every setting is in the catalog once, with a carrier and a level")
    func catalogIsComplete() {
        let ids = SettingCatalog.all.map(\.id)
        #expect(Set(ids) == Set(SettingID.allCases))
        #expect(ids.count == SettingID.allCases.count)
        for setting in SettingCatalog.all {
            #expect(!setting.levels.isEmpty, "\(setting.id)")
            if setting.id != .environment {
                #expect(!setting.carrier.envKeys.isEmpty, "\(setting.id) reaches no key")
            }
        }
    }

    @Test("the five quick settings, in order")
    func quickSettings() {
        #expect(SettingCatalog.quick.map(\.id) == [.renderer, .retina, .upscaler, .fps, .fpsLimit])
        #expect(SettingCatalog.setting(.renderer).levels == [.game])
        #expect(SettingCatalog.setting(.msync).levels == [.game])
    }

    /// A value other than the default for each setting, and a key it must reach.
    static let samples: [(SettingID, JSONValue, String)] = [
        (.renderer, .string("dxvk"), "NOTPROTON_RENDERER=dxvk"),
        (.retina, .bool(true), "NOTPROTON_RETINA=1"),
        (.upscaler, .string("metalfx"), "SEVO_UPSCALER=metalfx"),
        (.fps, .bool(true), "SEVO_FPS=1"),
        (.fpsLimit, .number(60), "DXVK_FRAME_RATE=60"),
        (.windows, .string("all"), "SEVO_RESIZABLE_WINDOWS=all"),
        (.filter, .string("nearest"), "SEVO_FINAL_FILTER=nearest"),
        (.emulateModeset, .bool(true), "NOTPROTON_EMULATE_MODESET=1"),
        (.fpsGraph, .bool(true), "SEVO_FPS_GRAPH=1"),
        (.hud, .bool(true), "MTL_HUD_ENABLED=1"),
        (.dlss, .bool(true), "DXMT_ENABLE_NVEXT=1"),
        (.mouse, .string("linear"), "SEVO_LINEAR_MOUSE=1"),
        (.cursorConfine, .bool(true), "SEVO_CURSOR_CONFINE=1"),
        (.tuning, .string("experimental"), "SEVO_WAIT_SPIN=5200"),
        (.processors, .number(4), "SEVO_CPU_COUNT=4"),
        (.unifiedMemory, .bool(true), "SEVO_FORCE_UMA=1"),
        (.largeAddressAware, .bool(true), "SEVO_LARGE_ADDRESS_AWARE=1"),
        (.avx, .bool(true), "ROSETTA_ADVERTISE_AVX=1"),
        (.gpu, .string("intel-arc-a750"), "SEVO_GPU_DEVICE_ID=0x56a1"),
        (.dllOverrides, .object(["d3dcompiler_47": .string("n,b")]), "NOTPROTON_DLL_OVERRIDES=d3dcompiler_47=n,b"),
        (.environment, .array([.string("DXVK_HUD=1")]), "DXVK_HUD=1"),
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
        global.processors = 6
        var game = ConfigValues()
        game.fps = true
        game.hud = false
        game.processors = 0
        let lines = ConfigMaterializer.gameLines(appID: 1, stack: ConfigStack(global: global, game: game))
        #expect(lines.contains("SEVO_FPS=1"))
        #expect(lines.contains("MTL_HUD_ENABLED=0"))
        #expect(lines.contains("SEVO_CPU_COUNT=0"), "every processor is an explicit 0")
        #expect(!lines.contains { $0.hasPrefix("SEVO_FPS_GRAPH=") }, "an inherited switch is not written")

        let bottle = ConfigMaterializer.bottleLines(global: global, msync: true, cli: "/x/sevo")
        #expect(bottle.contains("SEVO_FPS=1"))
        #expect(bottle.contains("SEVO_CPU_COUNT=6"))
        #expect(bottle.contains("SEVO_CLI=/x/sevo"))
        #expect(bottle.contains("NOTPROTON_MSYNC=1"))
        let env = ConfigMaterializer.effectiveEnvironment(bottle: bottle, program: lines)
        #expect(env["SEVO_CPU_COUNT"] == "0")
        #expect(env["MTL_HUD_ENABLED"] == "0")
    }

    @Test("the engine ends up with what the levels resolve to")
    func effectiveEnvironmentFollowsTheLevels() throws {
        var global = ConfigValues()
        try SettingCatalog.setting(.fps).write(&global, .bool(true))
        try SettingCatalog.setting(.gpu).write(&global, .string("nvidia"))
        try SettingCatalog.setting(.fpsLimit).write(&global, .number(30))
        try SettingCatalog.setting(.mouse).write(&global, .string("linear"))
        var game = ConfigValues()
        try SettingCatalog.setting(.fps).write(&game, .bool(false))
        try SettingCatalog.setting(.gpu).write(&game, .string("as-is"))
        try SettingCatalog.setting(.mouse).write(&game, .string("system"))

        let stack = ConfigStack(global: global, game: game)
        let env = ConfigMaterializer.effectiveEnvironment(
            bottle: ConfigMaterializer.bottleLines(global: global, msync: true, cli: nil),
            program: ConfigMaterializer.gameLines(appID: 7, stack: stack))
        #expect(env["SEVO_FPS"] == "0")
        #expect(env["SEVO_LINEAR_MOUSE"] == "0")
        #expect(env["SEVO_GPU_VENDOR_ID"] == nil, "as is over a shared preset removes the variable")
        #expect(env["DXMT_CONFIG"] == "d3d11.preferredMaxFrameRate=30;", "the shared limit stays in DXMT's value")
        #expect(env["DXVK_FRAME_RATE"] == "30")

        // The game's own limit replaces the shared one in DXMT's composite value.
        try SettingCatalog.setting(.fpsLimit).write(&game, .number(0))
        let own = ConfigMaterializer.effectiveEnvironment(
            bottle: ConfigMaterializer.bottleLines(global: global, msync: true, cli: nil),
            program: ConfigMaterializer.gameLines(appID: 7, stack: ConfigStack(global: global, game: game)))
        #expect(own["DXVK_FRAME_RATE"] == nil)
        #expect(own["DXMT_CONFIG"] == nil)
    }

    @Test("DXMT's options join into one value")
    func dxmtConfig() throws {
        var game = ConfigValues()
        try SettingCatalog.setting(.fpsLimit).write(&game, .number(60))
        try SettingCatalog.setting(.gpu).write(&game, .object([
            "preset": .string("custom"), "vendorID": .string("10DE"), "deviceID": .string("0x2c02"),
            "name": .string("My Card"),
        ]))
        let stack = ConfigStack(global: .empty, game: game)
        #expect(ConfigMaterializer.dxmtConfig(stack)
            == "d3d11.preferredMaxFrameRate=60;dxgi.customVendorId=10de;dxgi.customDeviceId=2c02;")
        let lines = ConfigMaterializer.gameLines(appID: 1, stack: stack)
        #expect(lines.contains("SEVO_GPU_NAME=My Card"))
        #expect(lines.contains("SEVO_GPU_MEMORY_MB="))
    }

    @Test("values outside a setting are refused")
    func invalidValues() {
        var values = ConfigValues()
        let bad: [(SettingID, JSONValue)] = [
            (.fps, .string("yes")), (.renderer, .string("d3dmetal")), (.fpsLimit, .number(5)),
            (.fpsLimit, .number(5000)), (.processors, .number(-1)), (.windows, .number(1)),
            (.tuning, .object(["preset": .string("custom"), "waitSpin": .number(2_000_000)])),
            (.gpu, .object(["preset": .string("custom"), "vendorID": .string("zz")])),
            (.dllOverrides, .object(["steamclient64": .string("n")])),
            (.dllOverrides, .object(["d3dx9_43": .string("x")])),
            (.dllOverrides, .object(["../evil": .string("n")])),
            (.environment, .array([.string("WINEDLLOVERRIDES=x=n")])),
            (.environment, .array([.string("DYLD_INSERT_LIBRARIES=/tmp/x")])),
            (.environment, .array([.string("SEVO_FPS=1")])),
            (.environment, .array([.string("1BAD=x")])),
            (.environment, .array([.string("NOEQUALS")])),
        ]
        for (id, value) in bad {
            #expect(throws: SettingsError.self, "\(id) \(value.text)") {
                try SettingCatalog.setting(id).write(&values, value)
            }
        }
        #expect(values == .empty)
    }

    @Test("environment lines from Steam launch options")
    func environmentFromLaunchOptions() throws {
        #expect(try SettingCatalog.environmentLines(from: ["DXVK_HUD=1 FOO=\"a\" %command% -novid VAR=2"])
            == ["DXVK_HUD=1", "FOO=a"])
        #expect(try SettingCatalog.environmentLines(from: ["A=1\nB=\n# note\nA=3"]) == ["B=", "A=3"])
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
        let old = #"{"commandIsControl":true,"optionIsAlt":false,"fps":true,"exes":["a.exe"]}"#
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
        for (key, value) in ConfigMigration.oldProfile where key != "SEVO_RESIZABLE_WINDOWS" {
            #expect(env[key] == value, "\(key)")
        }
        #expect(env["SEVO_CPU_COUNT"] == nil)
        #expect(env["DXMT_CONFIG"] == nil)
        #expect(env["SEVO_GPU_VENDOR_ID"] == nil)
    }
}
