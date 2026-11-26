// The components a setting downloads (FSR 4, ANR): fetched from a local archive here, checked, unpacked and moved
// into place; a wrong checksum installs nothing; ANR brings FSR 4 first.

import CryptoKit
import Foundation
import Testing
@testable import LullabySettings

@Suite("Component downloads")
struct ComponentStoreTests {

    struct Fixture {
        let dir: URL
        let store: ComponentStore

        init() throws {
            dir = FileManager.default.temporaryDirectory.appending(path: "lb-components-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let fsr4 = try Self.archive(in: dir, top: "fsr4", files: ["dist/crossover/libfsr4hook.dylib": "hook",
                                                                      "build/variant.metallib": "kernels"])
            let anr = try Self.archive(in: dir, top: "anr_runtime_v20", files: ["manifest.json": "{}", "weights.bin": "w"])
            var store = ComponentStore(root: dir.appending(path: "components"))
            store.specs = [
                ComponentSpec(id: "fsr4", url: fsr4.url, sha256: fsr4.sha, bytes: fsr4.size, top: "fsr4",
                              destination: "fsr4", marker: "dist/crossover/libfsr4hook.dylib", requires: nil),
                ComponentSpec(id: "anr", url: anr.url, sha256: anr.sha, bytes: anr.size, top: "anr_runtime_v20",
                              destination: "fsr4/build/anr_runtime_v20", marker: "manifest.json", requires: "fsr4"),
            ]
            self.store = store
        }

        func cleanUp() { try? FileManager.default.removeItem(at: dir) }

        static func archive(in dir: URL, top: String, files: [String: String]) throws -> (url: URL, sha: String, size: Int64) {
            let stage = dir.appending(path: "stage-\(top)")
            for (path, text) in files {
                let file = stage.appending(path: top).appending(path: path)
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.utf8).write(to: file)
            }
            let out = dir.appending(path: "\(top).tar.xz")
            let tar = Process()
            tar.executableURL = URL(filePath: "/usr/bin/tar")
            tar.arguments = ["-cJf", out.path(percentEncoded: false), "-C", stage.path(percentEncoded: false), top]
            try tar.run(); tar.waitUntilExit()
            let data = try Data(contentsOf: out)
            let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return (out, sha, Int64(data.count))
        }
    }

    @Test("a component downloads, is checked and lands in place; its state says installed")
    func installs() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        #expect(try f.store.status("fsr4").object?["state"] == .string("idle"))
        try f.store.download("fsr4")
        #expect(try f.store.status("fsr4").object?["state"] == .string("installed"))
        let hook = f.store.root.appending(path: "fsr4/dist/crossover/libfsr4hook.dylib")
        #expect(try String(contentsOf: hook, encoding: .utf8) == "hook")
        #expect(!FileManager.default.fileExists(atPath: f.store.root.appending(path: ".downloads/fsr4.json").path))
    }

    @Test("ANR brings FSR 4 first and goes inside it")
    func anrNeedsFSR4() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        try f.store.download("anr")
        #expect(try f.store.status("fsr4").object?["state"] == .string("installed"))
        #expect(try f.store.status("anr").object?["state"] == .string("installed"))
        #expect(FileManager.default.fileExists(atPath:
            f.store.root.appending(path: "fsr4/build/anr_runtime_v20/weights.bin").path))
    }

    @Test("a wrong checksum installs nothing and the state says why")
    func wrongChecksum() throws {
        var f = try Fixture()
        defer { f.cleanUp() }
        var store = f.store
        let s = store.specs[0]
        store.specs[0] = ComponentSpec(id: s.id, url: s.url, sha256: String(repeating: "0", count: 64), bytes: s.bytes,
                                       top: s.top, destination: s.destination, marker: s.marker, requires: nil)
        f = Fixture(dir: f.dir, store: store)
        #expect(throws: (any Error).self) { try f.store.download("fsr4") }
        let state = try f.store.status("fsr4").object
        #expect(state?["state"] == .string("failed"))
        #expect(state?["error"]?.string?.contains("checksum") == true)
        #expect(!FileManager.default.fileExists(atPath: f.store.root.appending(path: "fsr4").path))
    }

    @Test("an older copy is replaced whole, never mixed")
    func replacesOldCopy() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let stale = f.store.root.appending(path: "fsr4/stale.txt")
        try FileManager.default.createDirectory(at: stale.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: stale)
        try f.store.download("fsr4")
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(try f.store.status("fsr4").object?["state"] == .string("installed"))
    }

    @Test("the catalog names the component of FSR 4 and ANR, and the state lists the components")
    func panelSeesComponents() throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanUp() }
        let service = fixture.service
        let settings = try #require(service.catalogJSON().object?["settings"]?.array)
        let byID = Dictionary(uniqueKeysWithValues: settings.compactMap { s -> (String, JSONValue)? in
            guard let id = s.object?["id"]?.string else { return nil }; return (id, s)
        })
        #expect(byID["fsr4"]?.object?["component"] == .string("fsr4"))
        #expect(byID["anr"]?.object?["component"] == .string("anr"))
        #expect(byID["retina"]?.object?["component"] == nil)
        let components = try #require(service.stateJSON(appID: nil).object?["components"]?.object)
        #expect(Set(components.keys) == ["fsr4", "anr"])
    }
}

extension ComponentStoreTests.Fixture {
    init(dir: URL, store: ComponentStore) { self.dir = dir; self.store = store }
}
