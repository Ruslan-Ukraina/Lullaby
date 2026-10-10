import Foundation
import Testing

@testable import LullabyApp

@Suite("Engine store")
struct EngineStoreTests {

    private func runners(_ tags: [String], current: String?) throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "np-runners-\(UUID().uuidString)")
        for tag in tags {
            let bin = root.appending(path: "\(tag)/wine/bin")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            for name in ["wine", "wineserver"] {
                let file = bin.appending(path: name)
                try Data("#!/bin/sh\n".utf8).write(to: file)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: file.path(percentEncoded: false))
            }
            try "{\"version\": \"\(tag)\"}".write(
                to: root.appending(path: "\(tag)/engine-info.json"), atomically: true, encoding: .utf8)
        }
        if let current {
            try FileManager.default.createSymbolicLink(
                atPath: root.appending(path: "current").path(percentEncoded: false),
                withDestinationPath: current)
        }
        return root
    }

    @Test("No runners folder means no engine")
    func none() {
        let missing = URL.temporaryDirectory.appending(path: "np-missing-\(UUID().uuidString)")
        #expect(EngineStore.state(runners: missing) == .none)
        #expect(EngineStore.installed(in: missing).isEmpty)
    }

    @Test("A current link to a usable Dormison engine reads back its version")
    func engine() throws {
        let root = try runners(["dormison-b1"], current: "dormison-b1")
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(EngineStore.state(runners: root) == .engine(version: "dormison-b1"))
        #expect(EngineStore.currentTag(runners: root) == "dormison-b1")
    }

    @Test("A link at something that is not an engine is broken")
    func broken() throws {
        let root = try runners(["dormison-b1"], current: "dormison-b1")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appending(path: "dormison-b1/wine/bin/wine"))
        guard case .broken = EngineStore.state(runners: root) else {
            Issue.record("expected .broken"); return
        }
        let foreign = try runners(["foreign-1"], current: "foreign-1")
        defer { try? FileManager.default.removeItem(at: foreign) }
        guard case .broken = EngineStore.state(runners: foreign) else {
            Issue.record("expected .broken"); return
        }
    }

    @Test("Only complete engines are listed, in version order")
    func listing() throws {
        let root = try runners(["dormison-b10", "dormison-b2", "dormison-b1"], current: nil)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appending(path: ".dormison-b3.partial"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appending(path: "dormison-b4"), withIntermediateDirectories: true)
        #expect(EngineStore.installed(in: root).map(\.tag) == ["dormison-b1", "dormison-b2", "dormison-b10"])
    }

    @Test("Switching moves current and writes the engine's env file; refusing leaves it alone")
    func switching() throws {
        let root = try runners(["dormison-b1", "dormison-b2"], current: "dormison-b1")
        defer { try? FileManager.default.removeItem(at: root) }

        try EngineStore.switchTo("dormison-b2", runners: root, bridge: root.appending(path: "bridge"))
        #expect(EngineStore.currentTag(runners: root) == "dormison-b2")
        #expect(EngineUpdater(runners: root).previousTarget == "dormison-b1")
        #expect(FileManager.default.fileExists(
            atPath: root.appending(path: "dormison-b2/notproton-engine.env").path(percentEncoded: false)))

        #expect(throws: StepFailure.self) {
            try EngineStore.switchTo("dormison-b9", runners: root, bridge: root.appending(path: "bridge"))
        }
        #expect(throws: StepFailure.self) {
            try EngineStore.switchTo("../x", runners: root, bridge: root.appending(path: "bridge"))
        }
        #expect(EngineStore.currentTag(runners: root) == "dormison-b2")
    }

    @Test("The active engine cannot be removed, another one can")
    func removing() throws {
        let root = try runners(["dormison-b1", "dormison-b2"], current: "dormison-b2")
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: StepFailure.self) { try EngineStore.remove("dormison-b2", runners: root) }
        try EngineStore.remove("dormison-b1", runners: root)
        #expect(EngineStore.installed(in: root).map(\.tag) == ["dormison-b2"])
        #expect(throws: StepFailure.self) { try EngineStore.remove("dormison-b1", runners: root) }
    }

    @Test("Engines are named for people")
    func names() {
        #expect(EngineStore.displayName("dormison-b1") == "Dormison b1")
    }
}

@Suite("Signature database selection")
struct SignatureSelectionTests {

    @Test("The highest numbered database wins, not the first listed")
    func picksHighestBuild() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "np-signature-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        for name in ["1788400362.json", "999999999.json", "1788400363.json", "notes.txt"] {
            try Data().write(to: directory.appending(path: name))
        }

        #expect(PayloadInspector.newestSignatureDatabase(in: directory) == "1788400363.json")
    }

    @Test("An empty or absent directory reports nothing staged")
    func handlesEmptyDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "np-signature-empty-\(UUID().uuidString)")
        #expect(PayloadInspector.newestSignatureDatabase(in: directory) == nil)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(PayloadInspector.newestSignatureDatabase(in: directory) == nil)
    }
}

@Suite("Support paths")
struct SupportPathTests {

    // These strings are a contract with the dylib and RUN_SCRIPT rather than a
    // preference, so they are pinned here to make a rename visible.
    @Test("Paths match what the dylib and the run script use")
    func pathsAreStable() {
        let support = SupportPaths.support.path(percentEncoded: false)
        #expect(support.hasSuffix("/Library/Application Support/notproton"))

        #expect(SupportPaths.signatures.path(percentEncoded: false)
            .hasSuffix("/notproton/signatures/macos.arm64"))
        #expect(SupportPaths.overlayShim.path(percentEncoded: false)
            .hasSuffix("/notproton/overlay-shim.dylib"))
        #expect(SupportPaths.currentRunner.path(percentEncoded: false)
            .hasSuffix("/notproton/runners/current"))
        #expect(SupportPaths.Steam.deployedDylib.path(percentEncoded: false)
            == "/Applications/Steam.app/Contents/MacOS/notproton.dylib")
        #expect(SupportPaths.Steam.infoPlist.path(percentEncoded: false)
            == "/Applications/Steam.app/Contents/Info.plist")
    }
}
