import Foundation
import Testing

@testable import NotProtonApp

@Suite("Game settings")
struct GameSettingsTests {

    private func prefix(in root: URL) -> WinePrefix {
        WinePrefix(
            appID: "42", name: nil, library: SteamLibrary(root: root, volume: nil), lastUsed: nil)
    }

    private func scratch() throws -> URL {
        let dir = URL.temporaryDirectory.appending(path: "np-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("A bottle.env written by the run script reads back")
    func readsTheDefaultProfile() {
        let text = """
            # comment
            SEVO_RESIZABLE_WINDOWS=1
            SEVO_UPSCALER=off
            SEVO_FINAL_FILTER=lanczos
            SEVO_FPS=0
            SEVO_LINEAR_MOUSE=0
            WINEMSYNC=1
            """
        let settings = GameSettings(env: EnvFile.parse(text))
        #expect(settings.windows == .fixed)
        #expect(settings.upscaler == UpscalerChoice.off)
        #expect(settings.filter == .lanczos)
        #expect(settings.fps == false)
        #expect(settings.cursorConfine == nil)
    }

    @Test("Window modes follow the engine's first-letter rule")
    func windowModes() {
        func mode(_ value: String) -> WindowMode? {
            GameSettings(env: ["SEVO_RESIZABLE_WINDOWS": value]).windows
        }
        #expect(mode("all") == .all)
        #expect(mode("window") == .window)
        #expect(mode("fixed") == .fixed)
        #expect(mode("1") == .fixed)
        #expect(mode("off") == WindowMode.off)
        #expect(mode("0") == WindowMode.off)
    }

    @Test("Applying settings keeps other lines and removes inherited keys")
    func applyKeepsTheRest() {
        let old = "SEVO_LOADER=/x/wine\nSEVO_FPS=1\n# note\n"
        let new = EnvFile.apply(
            GameSettings(upscaler: .metalfx, fps: nil).entries, to: old)
        #expect(new == "SEVO_LOADER=/x/wine\n# note\nSEVO_UPSCALER=metalfx\n")
        #expect(EnvFile.apply(GameSettings().entries, to: "") == "")
    }

    @Test("Saving writes the game's file and the next load sees it over the bottle")
    func saveAndLoad() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let prefix = prefix(in: root)
        let sevo = GameSettingsStore.sevo(prefix)
        try FileManager.default.createDirectory(
            at: sevo.appending(path: "apps"), withIntermediateDirectories: true)

        #expect(GameSettingsStore.load(prefix) == nil)

        try "game.exe\n".write(to: sevo.appending(path: "game-exe"), atomically: true, encoding: .utf8)
        try "SEVO_FPS=0\nSEVO_UPSCALER=off\n".write(
            to: sevo.appending(path: "bottle.env"), atomically: true, encoding: .utf8)
        try "SEVO_LOADER=/x/wine\n".write(
            to: GameSettingsStore.gameFile(prefix, program: "game.exe"), atomically: true,
            encoding: .utf8)

        try GameSettingsStore.save(
            GameSettings(windows: .all, fps: true, cpuCount: 8), for: prefix, program: "game.exe")
        let loaded = try #require(GameSettingsStore.load(prefix))
        #expect(loaded.program == "game.exe")
        #expect(loaded.game.fps == true)
        #expect(loaded.effective.fps == true)
        #expect(loaded.effective.upscaler == UpscalerChoice.off)
        #expect(loaded.effective.cpuCount == 8)
        let file = try String(
            contentsOf: GameSettingsStore.gameFile(prefix, program: "game.exe"), encoding: .utf8)
        #expect(file.hasPrefix("SEVO_LOADER=/x/wine\n"))
    }

    @Test("msync is on unless the debugging marker says 0")
    func msyncMarker() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let prefix = prefix(in: root)
        try FileManager.default.createDirectory(at: prefix.root, withIntermediateDirectories: true)
        #expect(GameSettingsStore.msyncEnabled(prefix))
        try GameSettingsStore.setMsync(false, for: prefix)
        #expect(GameSettingsStore.msyncEnabled(prefix) == false)
        try GameSettingsStore.setMsync(true, for: prefix)
        #expect(GameSettingsStore.msyncEnabled(prefix))
    }
}
