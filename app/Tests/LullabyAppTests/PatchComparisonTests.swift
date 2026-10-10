import Foundation
import Testing

@testable import LullabyApp

@Suite("Patch comparison")
struct PatchComparisonTests {

    private struct Fixture {
        let root: URL
        let payload: InstallPayload.Located
        let bridgePayload: BridgePayload.Located
        let installed: PatchComparison.Installed
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(text.utf8).write(to: url)
    }

    // Shipped files, and an installed copy of every one of them: a current install.
    private func fixture() throws -> Fixture {
        let root = URL.temporaryDirectory.appending(path: "np-patch-\(UUID().uuidString)")
        let shipped = root.appending(path: "payload")
        try write("dylib", to: shipped.appending(path: SupportPaths.dylibName))
        try write("shim", to: shipped.appending(path: "overlay-shim.dylib"))
        try write("iconmaker", to: shipped.appending(path: "iconmaker"))
        try write("appinfo", to: shipped.appending(path: "appinfo"))
        try write("settings", to: shipped.appending(path: SupportPaths.settingsCLIName))
        try write("#!/bin/sh\n", to: shipped.appending(path: InstallPayload.runScriptName))
        try write("{}", to: shipped.appending(path: "signatures/macos.arm64/1788652215.json"))
        for entry in BridgePayload.entries {
            try write(entry.resource, to: shipped.appending(path: "bridge/\(entry.resource)"))
        }

        let support = root.appending(path: "support")
        let installed = PatchComparison.Installed(
            dylib: root.appending(path: "Steam.app/Contents/MacOS/\(SupportPaths.dylibName)"),
            runScript: root.appending(path: "compatibilitytools.d/lullaby/run"),
            bridge: support.appending(path: "bridge"),
            overlayShim: support.appending(path: "overlay-shim.dylib"),
            iconmaker: support.appending(path: "iconmaker"),
            appinfo: support.appending(path: "appinfo"),
            settingsCLI: support.appending(path: SupportPaths.settingsCLIName),
            signatures: support.appending(path: "signatures/macos.arm64")
        )
        try write("dylib", to: installed.dylib)
        try write("#!/bin/sh\n", to: installed.runScript)
        try write("shim", to: installed.overlayShim)
        try write("iconmaker", to: installed.iconmaker)
        try write("appinfo", to: installed.appinfo)
        try write("settings", to: installed.settingsCLI)
        try write("{}", to: installed.signatures.appending(path: "1788652215.json"))
        for entry in BridgePayload.entries {
            for path in entry.bridgePaths {
                try write(entry.resource, to: installed.bridge.appending(path: path))
            }
        }

        return Fixture(
            root: root,
            payload: try InstallPayload.locate(root: shipped),
            bridgePayload: try BridgePayload.locate(root: shipped.appending(path: "bridge")),
            installed: installed
        )
    }

    private func compare(_ fixture: Fixture) -> InstalledPatch {
        PatchComparison.compare(
            payload: fixture.payload, bridgePayload: fixture.bridgePayload,
            installed: fixture.installed
        )
    }

    @Test("Everything matching the shipped files is current")
    func current() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let patch = compare(fixture)
        #expect(patch.stale.isEmpty)
        #expect(patch.isCurrent)
        #expect(patch.installedAt != nil)
    }

    @Test("A different dylib in Steam is stale even though the version did not change")
    func dylibDiffers() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try write("older build", to: fixture.installed.dylib)

        #expect(compare(fixture).stale == [.dylib])
    }

    @Test("No dylib in Steam is stale")
    func dylibMissing() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try FileManager.default.removeItem(at: fixture.installed.dylib)

        let patch = compare(fixture)
        #expect(patch.stale == [.dylib])
        #expect(patch.installedAt == nil)
        #expect(patch.build == nil)
    }

    @Test("A run script written by an older dylib is stale, a missing one is not")
    func runScript() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try write("#!/bin/sh\necho older\n", to: fixture.installed.runScript)
        #expect(compare(fixture).stale == [.runScript])

        try FileManager.default.removeItem(at: fixture.installed.runScript)
        #expect(compare(fixture).stale.isEmpty, "no game has launched yet, nothing to replace")
    }

    @Test("One bridge copy out of date, or missing, makes the bridge stale")
    func bridge() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let i386 = fixture.installed.bridge.appending(path: "i386-windows/lsteamclient.dll")

        try write("older lsteamclient", to: i386)
        #expect(compare(fixture).stale == [.bridge])

        try FileManager.default.removeItem(at: i386)
        #expect(compare(fixture).stale == [.bridge])
    }

    @Test("A changed helper or a missing signature database makes the components stale")
    func components() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try write("older shim", to: fixture.installed.overlayShim)
        #expect(compare(fixture).stale == [.components])

        try write("shim", to: fixture.installed.overlayShim)
        try FileManager.default.removeItem(
            at: fixture.installed.signatures.appending(path: "1788652215.json")
        )
        #expect(compare(fixture).stale == [.components])
    }

    @Test("Stale parts are listed in a fixed order")
    func order() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try write("x", to: fixture.installed.appinfo)
        try write("x", to: fixture.installed.bridge.appending(path: "steam.exe"))
        try write("x", to: fixture.installed.runScript)
        try write("x", to: fixture.installed.dylib)

        #expect(compare(fixture).stale == [.dylib, .runScript, .bridge, .components])
    }

    // Install signs the dylib inside Steam.app, which changes its bytes but not its LC_UUID.
    @Test("A signed copy of the same build is the same build, a rebuilt one is not")
    func machOIdentity() throws {
        let work = URL.temporaryDirectory.appending(path: "np-patch-macho-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        func build(_ name: String, body: String) throws -> URL {
            let source = work.appending(path: "\(name).c")
            try Data("int np_probe(void) { return \(body); }\n".utf8).write(to: source)
            let out = work.appending(path: "\(name).dylib")
            try Shell.check("/usr/bin/clang", [
                "-dynamiclib", "-arch", "arm64", "-arch", "x86_64",
                "-o", out.path(percentEncoded: false), source.path(percentEncoded: false),
            ])
            return out
        }

        let shipped = try build("shipped", body: "1")
        let signed = work.appending(path: "signed.dylib")
        try FileManager.default.copyItem(at: shipped, to: signed)
        try Shell.check("/usr/bin/codesign", ["-f", "-s", "-", signed.path(percentEncoded: false)])
        let rebuilt = try build("rebuilt", body: "2")

        #expect(try Data(contentsOf: signed) != Data(contentsOf: shipped))
        #expect(PatchComparison.sameBuild(signed, shipped))
        #expect(!PatchComparison.sameBuild(rebuilt, shipped))

        let short = try #require(MachOBuild.shortBuild(of: signed))
        #expect(short.count == 8)
        #expect(short == MachOBuild.shortBuild(of: shipped))
        #expect(short != MachOBuild.shortBuild(of: rebuilt))
    }
}
