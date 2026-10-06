import Foundation
import Testing

@testable import NotProtonApp

@Suite("Engine provider")
struct EngineProviderTests {

    private func engine(version: String = "dormison-b9") throws -> (root: URL, dir: URL) {
        let root = URL.temporaryDirectory.appending(path: "np-engine-\(UUID().uuidString)")
        let dir = root.appending(path: version)
        let bin = dir.appending(path: "wine/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        for name in ["wine", "wineserver"] {
            let file = bin.appending(path: name)
            try Data("#!/bin/sh\n".utf8).write(to: file)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: file.path(percentEncoded: false))
        }
        try """
            {"version": "\(version)", "commit": "abc123", "wine": "11.16 + wine-staging 11.16",
             "sync": "msync (WINEMSYNC=1)", "renderers": ["auto", "dxmt"], "features": ["env-files"]}
            """.write(to: dir.appending(path: "engine-info.json"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "current"), withDestinationURL: dir)
        return (root, dir)
    }

    @Test("Paths and capabilities come from the engine's layout and engine-info.json")
    func layout() throws {
        let (root, dir) = try engine()
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = DormisonEngine(root: dir)

        #expect(engine.isUsable)
        #expect(engine.version == "dormison-b9")
        #expect(engine.wineloader.path(percentEncoded: false).hasSuffix("dormison-b9/wine/bin/wine"))
        #expect(engine.unixLoader.path(percentEncoded: false).hasSuffix("wine/lib/wine/x86_64-unix/wine"))
        #expect(engine.dllPaths(arch: .i386).map(\.lastPathComponent) == ["i386-windows"])
        #expect(engine.capabilities.commit == "abc123")
        #expect(engine.capabilities.renderers == ["auto", "dxmt"])
    }

    @Test("A folder without the executables is not usable")
    func notUsable() {
        let engine = DormisonEngine(root: URL.temporaryDirectory.appending(path: "np-none-\(UUID())"))
        #expect(engine.isUsable == false)
        #expect(engine.capabilities == EngineCapabilities())
    }

    @Test("The env file is written into the real directory with its own paths")
    func envFile() throws {
        let (root, dir) = try engine()
        defer { try? FileManager.default.removeItem(at: root) }

        let written = try DormisonEngine(root: root.appending(path: "current")).writeEnvironmentFile()
        #expect(written.standardizedFileURL.path == dir.appending(path: "notproton-engine.env").standardizedFileURL.path)
        let values = EnvFile.parse(try String(contentsOf: written, encoding: .utf8))
        #expect(values["NP_ENGINE_VERSION"] == "'dormison-b9'")
        #expect(values["NP_ENGINE_WINESERVER"]?.contains("dormison-b9/wine/bin/wineserver") == true)
        #expect(values["NP_ENGINE_DLLPATH_X86_64"]?.hasSuffix("x86_64-windows'") == true)
    }

    @Test("Quoting survives an apostrophe")
    func quoting() {
        #expect(DormisonEngine.quote("a'b") == "'a'\\''b'")
    }

    @Test("ensureEnvironmentFile writes once and repairs a stale file")
    func ensure() throws {
        let (root, dir) = try engine()
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = DormisonEngine(root: root.appending(path: "current"))
        let file = dir.appending(path: "notproton-engine.env")

        #expect(provider.ensureEnvironmentFile())
        let first = try String(contentsOf: file, encoding: .utf8)
        try "stale\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(provider.ensureEnvironmentFile())
        #expect(try String(contentsOf: file, encoding: .utf8) == first)
        #expect(DormisonEngine(root: root.appending(path: "nothing")).ensureEnvironmentFile() == false)
    }
}
