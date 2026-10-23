// D3DMetal from a Game Porting Toolkit image (docs/ROADMAP.md section 6): the installer
// against disk images built here in Apple's layout (nothing of Apple's is in the repo),
// several versions, macOS 26 vs 27, and what a game on D3DMetal gets.

import Foundation
import Testing
@testable import LullabySettings

@Suite("D3DMetal store")
struct D3DMetalStoreTests {

    /// Apple's `redist/lib` shape with stand-in files: the framework, the bridge dylib, the
    /// `.so` links into `../../external/` and the Windows DLLs.
    static func makeRedist(at volume: URL) throws {
        let lib = volume.appending(path: "redist/lib")
        let manager = FileManager.default
        let framework = lib.appending(path: "external/D3DMetal.framework/Versions/A")
        try manager.createDirectory(at: framework, withIntermediateDirectories: true)
        try Data("framework".utf8).write(to: framework.appending(path: "D3DMetal"))
        try Data("bridge".utf8).write(to: lib.appending(path: "external/libd3dshared.dylib"))
        let unix = lib.appending(path: "wine/x86_64-unix")
        let windows = lib.appending(path: "wine/x86_64-windows")
        try manager.createDirectory(at: unix, withIntermediateDirectories: true)
        try manager.createDirectory(at: windows, withIntermediateDirectories: true)
        for name in ["d3d11", "d3d12", "dxgi"] {
            try manager.createSymbolicLink(
                atPath: unix.appending(path: "\(name).so").path(percentEncoded: false),
                withDestinationPath: "../../external/libd3dshared.dylib")
            try Data("MZ \(name)".utf8).write(to: windows.appending(path: "\(name).dll"))
        }
    }

    static func makeImage(_ volumeName: String, in dir: URL, nested: Bool) throws -> URL {
        let src = dir.appending(path: "src-\(UUID().uuidString)")
        let inner = dir.appending(path: "inner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try makeRedist(at: inner)
        // makehybrid writes the same HFS+ volume (name, links) in hundredths of a second;
        // hdiutil create spent about five seconds on each image (docs/OPTIMIZATION.md).
        func create(_ folder: URL, _ name: String, _ out: URL) throws {
            try D3DMetalStore.run("/usr/bin/hdiutil", [
                "makehybrid", "-quiet", "-hfs", "-hfs-volume-name", name,
                "-o", out.path(percentEncoded: false), folder.path(percentEncoded: false),
            ])
        }
        guard nested else {
            let image = dir.appending(path: "\(UUID().uuidString).dmg")
            try create(inner, volumeName, image)
            return image
        }
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try create(inner, volumeName, src.appending(path: "\(volumeName).dmg"))
        let outer = dir.appending(path: "Game_Porting_Toolkit-\(UUID().uuidString).dmg")
        try create(src, "Game Porting Toolkit", outer)
        return outer
    }

    func scratch() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "np-d3dm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("a nested toolkit image installs whole, with Apple's links kept")
    func installsFromNestedImage() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let image = try Self.makeImage("Evaluation environment for Windows games 4.0 beta 9", in: dir, nested: true)
        let store = D3DMetalStore(root: dir.appending(path: "d3dmetal"), macOS: 27)
        let mountedBefore = try FileManager.default.contentsOfDirectory(atPath: "/Volumes")

        let toolkit = try store.install(from: image)
        #expect(toolkit.version == "4.0 beta 9")
        let link = toolkit.unix.appending(path: "d3d12.so").path(percentEncoded: false)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link) == "../../external/libd3dshared.dylib")
        #expect(URL(filePath: link).resolvingSymlinksInPath().path(percentEncoded: false)
            == toolkit.external.appending(path: "libd3dshared.dylib").resolvingSymlinksInPath().path(percentEncoded: false))
        #expect(FileManager.default.fileExists(atPath: toolkit.windows.appending(path: "d3d12.dll").path(percentEncoded: false)))
        #expect(store.installed().map(\.version) == ["4.0 beta 9"])
        #expect(store.active()?.version == toolkit.version)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: "/Volumes")) == Set(mountedBefore),
                "every image the installer mounted is unmounted")
    }

    @Test("a mounted volume or a folder works, and anything else is refused")
    func installsFromFolder() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let volume = dir.appending(path: "Evaluation environment for Windows games 3.0")
        try Self.makeRedist(at: volume)
        let store = D3DMetalStore(root: dir.appending(path: "d3dmetal"), macOS: 26)
        #expect(try store.install(from: volume).version == "3.0")
        #expect(throws: D3DMetalStore.InstallError.self) {
            try store.install(from: dir.appending(path: "nothing"))
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "d3dmetal/.3.0.installing").path(percentEncoded: false)))
    }

    @Test("several versions: the newest the Mac can run is the one games get")
    func versionsAndMacOS() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["3.0", "4.0 beta 2", "4.0"] {
            try Self.makeRedist(at: dir.appending(path: "Evaluation environment for Windows games \(name)"))
        }
        let on27 = D3DMetalStore(root: dir.appending(path: "d3dmetal"), macOS: 27)
        for name in ["4.0", "3.0", "4.0 beta 2"] {
            try on27.install(from: dir.appending(path: "Evaluation environment for Windows games \(name)"))
        }
        #expect(on27.installed().map(\.version) == ["3.0", "4.0", "4.0 beta 2"])
        #expect(on27.active()?.version == "4.0 beta 2", "a beta sorts after its release")

        let on26 = D3DMetalStore(root: on27.root, macOS: 26)
        #expect(on26.active()?.version == "3.0", "D3DMetal 4 needs macOS 27")
        #expect(on26.unusable().map(\.version) == ["4.0", "4.0 beta 2"])
        let state = on26.stateJSON().object
        #expect(state?["active"] == .string("3.0"))
        #expect(state?["unusable"]?.array?.count == 2)
    }

    @Test("a new toolkit replaces the old ones, unless this Mac cannot run it")
    func newToolkitReplaces() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        func folder(_ name: String) throws -> URL {
            let url = dir.appending(path: "Evaluation environment for Windows games \(name)")
            try Self.makeRedist(at: url)
            return url
        }
        let on26 = D3DMetalStore(root: dir.appending(path: "d3dmetal"), macOS: 26)
        let three = try on26.install(from: try folder("3.0"))
        #expect(on26.removeOthers(than: three).isEmpty)
        let four = try on26.install(from: try folder("4.0 beta 2"))
        #expect(on26.removeOthers(than: four).isEmpty, "a toolkit this Mac cannot run replaces nothing")
        #expect(on26.installed().map(\.version) == ["3.0", "4.0 beta 2"])

        let on27 = D3DMetalStore(root: on26.root, macOS: 27)
        let beta3 = try on27.install(from: try folder("4.0 beta 3"))
        #expect(on27.removeOthers(than: beta3) == ["3.0", "4.0 beta 2"])
        #expect(on27.installed().map(\.version) == ["4.0 beta 3"])
        #expect(on27.active()?.version == "4.0 beta 3")
    }

    @Test("the version comes from the volume's name")
    func versionNames() {
        #expect(D3DMetalStore.version(ofVolume: URL(filePath: "/Volumes/Evaluation environment for Windows games 4.0 beta 2 1")) == "4.0 beta 2")
        #expect(D3DMetalStore.version(ofVolume: URL(filePath: "/Volumes/Evaluation environment for Windows games 3.0")) == "3.0")
    }

    @Test("D3DMetal is a renderer only once installed, and its game gets D3DMetal's variables")
    func rendererAndEnvironment() throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanUp() }
        var service = fixture.service
        service.d3dmetal = D3DMetalStore(root: fixture.root.appending(path: "d3dmetal"), macOS: 27)
        try FileManager.default.createDirectory(at: fixture.prefix(4022369388), withIntermediateDirectories: true)
        #expect(throws: SettingsError.d3dmetalMissing) {
            try service.set("renderer", .string("d3dmetal"), appID: 4022369388)
        }
        let volume = fixture.root.appending(path: "Evaluation environment for Windows games 4.0 beta 2")
        try Self.makeRedist(at: volume)
        let toolkit = try service.d3dmetal.install(from: volume)
        try service.set("renderer", .string("d3dmetal"), appID: 4022369388)
        try service.set("dlss", .bool(true), appID: 4022369388)

        let bottle = try #require(fixture.read(".sevo/bottle.env", in: 4022369388))
        #expect(bottle.contains("LULLABY_D3DMETAL=") && bottle.contains("/d3dmetal/\(toolkit.version)\n"), "\(bottle)")
        try service.store.updateGame(4022369388) { $0.exes = ["re9.exe"] }
        try service.materialize(appID: 4022369388)
        let game = try #require(fixture.read(".sevo/apps/re9.exe.env", in: 4022369388))
        #expect(game.contains("LULLABY_RENDERER=d3dmetal"))
        // The card follows DLSS (Amendment 09.10): with it on, D3DMetal names the NVIDIA card
        // and answers DLSS through MetalFX.
        #expect(game.contains("D3DM_VENDOR_ID=0x10DE"))
        #expect(game.contains("D3DM_DEVICE_ID=0x2D04"))
        #expect(game.contains("D3DM_DEVICE_DESCRIPTION=NVIDIA GeForce RTX 5060 Ti"))
        #expect(game.contains("D3DM_ENABLE_METALFX=1"))
        #expect(bottle.contains("D3DM_VENDOR_ID=0x1002"), "AMD for the games without DLSS")

        let catalog = service.catalogJSON().object?["settings"]?.array?.first { $0.object?["id"] == .string("renderer") }
        let choices = catalog?.object?["control"]?.object?["choices"]?.array ?? []
        #expect(choices.contains { $0.object?["requires"] == .string("d3dmetal") }, "the panel learns what to hide")
        #expect(service.stateJSON(appID: 4022369388).object?["d3dmetal"]?.object?["active"] == .string("4.0 beta 2"))
    }
}
