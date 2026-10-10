import CryptoKit
import Foundation
import Testing
@testable import NotProtonSettings

@Suite("Mullion store")
struct MullionStoreTests {
    static func offered(_ state: JSONValue) -> Bool? {
        guard case let .object(object) = state, case let .bool(value)? = object["offered"] else { return nil }
        return value
    }

    /// A minimal PE file: "MZ", e_lfanew 64, "PE\0\0" and the machine.
    static func pe(_ machine: UInt16) -> Data {
        var data = Data(count: 64)
        data[0] = 0x4d; data[1] = 0x5a; data[60] = 64
        data += Data([0x50, 0x45, 0, 0, UInt8(machine & 0xff), UInt8(machine >> 8)])
        return data
    }

    /// An archive shaped like Mullion's release, and a store that "downloads" it.
    static func rig(_ root: URL, chip: String = "Apple M4 Pro", macOS: Int = 27, tamper: Bool = false) throws -> MullionStore {
        let fm = FileManager.default
        let work = root.appending(path: "work/mullion-vtest")
        for dir in ["x86_64-windows", "x86_64-unix"] {
            try fm.createDirectory(at: work.appending(path: dir), withIntermediateDirectories: true)
        }
        for name in MullionRelease.windowsFiles { try pe(0x8664).write(to: work.appending(path: "x86_64-windows/\(name)")) }
        try Data("unix".utf8).write(to: work.appending(path: "x86_64-unix/winemetal.so"))
        for name in ["LICENSE", "install.sh"] { try Data(name.utf8).write(to: work.appending(path: name)) }
        let archive = root.appending(path: "mullion-vtest.tar.gz")
        let tar = Process()
        tar.executableURL = URL(filePath: "/usr/bin/tar")
        tar.arguments = ["-czf", archive.path(percentEncoded: false), "-C", work.deletingLastPathComponent().path(percentEncoded: false), "mullion-vtest"]
        try tar.run(); tar.waitUntilExit()
        let bytes = try Data(contentsOf: archive)
        var store = MullionStore(
            root: root.appending(path: "mullion"), engineUnix: root.appending(path: "engine/x86_64-unix"),
            chip: chip, macOS: macOS)
        let sha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        store.release = MullionRelease(
            version: "vtest", url: archive, sha256: tamper ? String(repeating: "0", count: 64) : sha,
            sizeBytes: Int64(bytes.count), top: "mullion-vtest")
        store.download = { from, to in try FileManager.default.copyItem(at: from, to: to) }
        return store
    }

    @Test("Offered on an M3 or later with macOS 15 or later")
    func whichMacs() {
        #expect(MullionStore.generation(of: "Apple M4 Pro") == 4)
        #expect(MullionStore.generation(of: "Apple M10 Max") == 10)
        #expect(MullionStore.generation(of: "Intel(R) Core(TM) i9") == nil)
        let root = URL.temporaryDirectory
        #expect(MullionStore(root: root, engineUnix: root, chip: "Apple M3", macOS: 15).unsupportedReason == nil)
        #expect(MullionStore(root: root, engineUnix: root, chip: "Apple M2 Max", macOS: 27).unsupportedReason != nil)
        #expect(MullionStore(root: root, engineUnix: root, chip: "Apple M4 Pro", macOS: 14).unsupportedReason != nil)
    }

    @Test("Installed whole in its own folder, with its licence and a note of its source, never its install.sh")
    func install() throws {
        let root = URL.temporaryDirectory.appending(path: "np-mullion-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Self.rig(root)
        #expect(!store.installed)
        try store.install()
        #expect(store.installed)
        let dir = store.directory
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: dir.appending(path: "LICENSE").path(percentEncoded: false)))
        #expect(!fm.fileExists(atPath: dir.appending(path: "install.sh").path(percentEncoded: false)))
        let note = try String(contentsOf: dir.appending(path: "SOURCE.txt"), encoding: .utf8)
        #expect(note.contains("LGPL-2.1-or-later") && note.contains(store.release.sha256))
        #expect(try fm.destinationOfSymbolicLink(atPath: dir.appending(path: "x86_64-unix/ntdll.so").path(percentEncoded: false))
                .hasSuffix("engine/x86_64-unix/ntdll.so"))
        #expect(try fm.destinationOfSymbolicLink(atPath: store.current.path(percentEncoded: false)) == "vtest")
        // Again: nothing to download.
        var offline = store
        offline.download = { _, _ in throw URLError(.notConnectedToInternet) }
        try offline.install()
    }

    @Test("An archive that is not the pinned one is refused and leaves nothing")
    func tampered() throws {
        let root = URL.temporaryDirectory.appending(path: "np-mullion-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try Self.rig(root, tamper: true)
        #expect(throws: MullionStore.InstallError.self) { try store.install() }
        #expect(!store.installed)
        #expect(!FileManager.default.fileExists(atPath: store.current.path(percentEncoded: false)))
    }

    @Test("Not on an M1 or M2: refused before any download")
    func unsupportedMac() throws {
        let root = URL.temporaryDirectory.appending(path: "np-mullion-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var store = try Self.rig(root, chip: "Apple M2")
        store.download = { _, _ in Issue.record("downloaded on an M2") }
        #expect(throws: MullionStore.InstallError.self) { try store.install() }
    }

    @Test("A game's 32-bit executable keeps Mullion out of its list and refuses it")
    func thirtyTwoBit() throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanUp() }
        var service = fixture.service
        service.mullion = try Self.rig(fixture.root)
        let steamapps = fixture.steam.appending(path: "steamapps")
        try FileManager.default.createDirectory(at: steamapps.appending(path: "common/Old"), withIntermediateDirectories: true)
        try "\"AppState\"\n{\n\t\"name\"\t\t\"Old\"\n\t\"installdir\"\t\t\"Old\"\n}\n"
            .write(to: steamapps.appending(path: "appmanifest_630.acf"), atomically: true, encoding: .utf8)
        try Self.pe(0x14c).write(to: steamapps.appending(path: "common/Old/old.exe"))
        try service.record(appID: 630, exe: nil, installDirectory: nil)
        #expect(service.is32Bit(appID: 630))
        #expect(Self.offered(service.mullionState(appID: 630)) == false)
        #expect(throws: SettingsError.self) { try service.set("renderer", .string("mullion"), appID: 630) }
        #expect(PEMachine.of(steamapps.appending(path: "common/Old/old.exe")) == 0x14c)
    }

    @Test("A 64-bit game gets Mullion downloaded when it picks it, and its files name the renderer")
    func pick() throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanUp() }
        var service = fixture.service
        service.mullion = try Self.rig(fixture.root)
        try fixture.write("", ".sevo/bottle.env", in: 3527290)
        try service.record(appID: 3527290, exe: "peak.exe", installDirectory: nil)
        #expect(Self.offered(service.mullionState(appID: 3527290)) == true)
        try service.set("renderer", .string("mullion"), appID: 3527290)
        #expect(service.mullion.installed)
        #expect(fixture.read(".sevo/apps/peak.exe.env", in: 3527290)?.contains("NOTPROTON_RENDERER=mullion") == true)
    }
}
