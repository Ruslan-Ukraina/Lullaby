import CryptoKit
import Foundation
import Synchronization
import Testing

@testable import NotProtonApp

/// Serves a fake Dormison release from memory. Can be taken offline, cut a
/// download short once, and records where each download started.
private final class FakeTransport: EngineTransport, Sendable {
    struct State {
        var files: [URL: Data] = [:]
        var offline = false
        var cutAfter: Int?
        var downloadStarts: [Int64] = []
        var downloads = 0
    }

    let state = Mutex(State())

    func fetch(_ url: URL, limit: Int) async throws -> Data {
        try state.withLock { state in
            if state.offline { throw URLError(.notConnectedToInternet) }
            guard let data = state.files[url] else { throw TransportFailure(detail: "404 \(url)") }
            return data
        }
    }

    func download(_ url: URL, to part: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let (data, cut): (Data, Int?) = try state.withLock { state in
            if state.offline { throw URLError(.notConnectedToInternet) }
            guard let data = state.files[url] else { throw TransportFailure(detail: "404 \(url)") }
            let cut = state.cutAfter
            state.cutAfter = nil
            state.downloads += 1
            return (data, cut)
        }
        let fm = FileManager.default
        if !fm.fileExists(atPath: part.path(percentEncoded: false)) {
            fm.createFile(atPath: part.path(percentEncoded: false), contents: nil)
        }
        let handle = try FileHandle(forWritingTo: part)
        defer { try? handle.close() }
        let offset = try handle.seekToEnd()
        state.withLock { $0.downloadStarts.append(Int64(offset)) }
        let rest = data.dropFirst(Int(offset))
        if let cut {
            try handle.write(contentsOf: rest.prefix(cut))
            throw URLError(.networkConnectionLost)
        }
        try handle.write(contentsOf: rest)
        progress(Int64(data.count))
    }
}

private final class Flags: Sendable {
    let game = Mutex(false)
    let steam = Mutex(false)
    let quits = Mutex(0)
    let smokeFails = Mutex(false)
    let quitFails = Mutex(false)
}

/// A temporary notproton tree, a signing key, and fake Dormison releases.
private struct Rig {
    let root = URL.temporaryDirectory.appending(path: "np-updater-\(UUID().uuidString)")
    var runners: URL { root.appending(path: "runners") }
    var cache: URL { root.appending(path: "cache") }
    var bridge: URL { root.appending(path: "bridge") }
    var bridges: URL { root.appending(path: "bridges") }
    var supportDir: URL { root.appending(path: "support") }
    var work: URL { root.appending(path: "work") }
    let key = Curve25519.Signing.PrivateKey()
    let transport = FakeTransport()
    let flags = Flags()

    static let commit = "52c2a4b918d6ec5f469ed4e5f58777598c9378ff"

    func cleanNtdll(_ arch: String, _ version: String) -> Data { Data("clean \(arch) ntdll of \(version)".utf8) }
    func b1Ntdll(_ arch: String, _ version: String) -> Data {
        Data("B1 \(arch) ntdll of \(version): exports lead to lsteamclient".utf8)
    }

    func assetURL(_ version: String) -> URL {
        let tag = version.replacingOccurrences(of: "dormison-", with: "")
        return URL(string: "https://github.com/kageroumado/dormison/releases/download/\(tag)/\(version).tar.xz")!
    }

    func sign(_ data: Data, with key: Curve25519.Signing.PrivateKey? = nil) throws -> Data {
        Data(try (key ?? self.key).signature(for: data).base64EncodedString().utf8)
    }

    var updater: EngineUpdater {
        let flags = flags
        let supportDir = supportDir
        return EngineUpdater(
            runners: runners, cache: cache, bridge: bridge, bridges: bridges, key: key.publicKey,
            transport: transport, feed: .off("test"),
            support: { BridgeCatalog(releases: BridgeCatalog.bundled(root: supportDir)) },
            refreshBridges: {},
            gameIsRunning: { flags.game.withLock { $0 } },
            steamIsRunning: { flags.steam.withLock { $0 } },
            quitSteam: {
                flags.quits.withLock { $0 += 1 }
                if flags.quitFails.withLock({ $0 }) { throw SteamBundle.StillRunning(seconds: 45) }
                flags.steam.withLock { $0 = false }
                return true
            },
            smokeTest: { engine in
                if flags.smokeFails.withLock({ $0 }) {
                    throw StepFailure(step: EngineSmokeTest.step, detail: "wineboot failed")
                }
                #expect(EngineSupport.carriesB1(engine.appending(path: "wine/lib/wine/x86_64-windows/ntdll.dll")))
                return "fake smoke"
            },
            freeSpace: { _ in nil })
    }

    /// Builds <version>/ like a Dormison tarball, packs it, and serves it with its signature.
    /// Returns the release the manifest will carry.
    @discardableResult
    func publish(
        _ version: String, commit: String = commit, tamper: Bool = false,
        signer: Curve25519.Signing.PrivateKey? = nil, wrongSha: Bool = false
    ) throws -> Data {
        let fm = FileManager.default
        let tree = work.appending(path: UUID().uuidString)
        let engine = tree.appending(path: version)
        var components: [[String: String]] = []
        func put(_ path: String, _ data: Data, executable: Bool = false) throws {
            let url = engine.appending(path: path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            if executable {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path(percentEncoded: false))
            }
            components.append(["path": path, "sha256": Digest.sha256(of: data)])
        }
        try put("wine/bin/wine", Data("#!/bin/sh\necho \(version)\n".utf8), executable: true)
        try put("wine/bin/wineserver", Data("#!/bin/sh\n".utf8), executable: true)
        for arch in ["x86_64", "i386"] {
            try put("wine/lib/wine/\(arch)-windows/ntdll.dll", cleanNtdll(arch, version))
        }
        try put("dxmt/d3d11.dll", Data("dxmt".utf8))
        try fm.createSymbolicLink(
            atPath: engine.appending(path: "wine/bin/notepad").path(percentEncoded: false), withDestinationPath: "wine")
        components.append(["path": "wine/bin/notepad", "link": "wine"])
        let info = try JSONSerialization.data(withJSONObject: ["version": version, "commit": commit])
        try put("engine-info.json", info)
        let manifest = try JSONSerialization.data(withJSONObject: [
            "version": version, "source": ["head": commit, "dirty": false], "components": components,
        ] as [String: Any])
        try manifest.write(to: engine.appending(path: "engine-manifest.json"))
        if tamper {
            try Data("changed after packaging".utf8).write(to: engine.appending(path: "dxmt/d3d11.dll"))
        }

        let tarball = tree.appending(path: "\(version).tar.xz")
        try Shell.check("/usr/bin/tar", [
            "-cJf", tarball.path(percentEncoded: false), "-C", tree.path(percentEncoded: false), version,
        ])
        let bytes = try Data(contentsOf: tarball)
        let url = assetURL(version)
        try transport.state.withLock { state in
            state.files[url] = bytes
            state.files[EngineSignature.signatureURL(for: url)] = try sign(bytes, with: signer)
        }
        return Data(Digest.sha256(of: wrongSha ? Data("other".utf8) : bytes).utf8)
    }

    /// engine.json naming `version` on the beta channel, signed by `signer` (our key by default).
    func announce(_ version: String, sha: Data? = nil, signer: Curve25519.Signing.PrivateKey? = nil) throws {
        let url = assetURL(version)
        let bytes = try transport.state.withLock { $0.files[url] } ?? Data()
        let manifest = try JSONSerialization.data(withJSONObject: [
            "schema": 2,
            "channels": ["beta": [
                "version": version, "minAppVersion": "1.0.0-beta.1", "url": url.absoluteString,
                "sha256": sha.map { String(decoding: $0, as: UTF8.self) } ?? Digest.sha256(of: bytes),
                "sizeBytes": bytes.count, "notes": "test",
            ]],
        ] as [String: Any])
        try transport.state.withLock { state in
            state.files[EngineManifest.url] = manifest
            state.files[EngineSignature.signatureURL(for: EngineManifest.url)] = try sign(manifest, with: signer)
        }
    }

    /// The app's bundled bridge list: one bridge per version in `versions`, built
    /// against `commit`, with its B1 files (i386 left out with `missingB1`). Versions in
    /// `downloadable` also say where their engine comes from (publish them first).
    func supporting(
        _ versions: [String], commit: String = commit, missingB1: Bool = false, downloadable: Set<String> = []
    ) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: supportDir)
        var bridges: [[String: Any]] = []
        let files = BridgePayload.entries.map(\.resource)
        for name in files {
            let url = supportDir.appending(path: "bridge/\(name)")
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("bridge file \(name)".utf8).write(to: url)
        }
        for version in versions {
            var ntdll: [[String: String]] = []
            for arch in ["x86_64", "i386"] {
                let file = "\(EngineSupport.directoryName)/\(version)/\(arch)-ntdll.dll"
                let url = supportDir.appending(path: file)
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !(missingB1 && arch == "i386") { try b1Ntdll(arch, version).write(to: url) }
                ntdll.append([
                    "arch": arch, "path": "wine/lib/wine/\(arch)-windows/ntdll.dll", "file": file,
                    "clean": Digest.sha256(of: cleanNtdll(arch, version)),
                    "b1": Digest.sha256(of: b1Ntdll(arch, version)),
                ])
            }
            var entry: [String: Any] = [
                "id": "bridge-\(version)-1", "engine": version, "engineCommit": commit, "rev": 1,
                "files": files.map { ["name": $0, "path": "bridge/\($0)"] }, "ntdll": ntdll,
            ]
            if downloadable.contains(version) {
                let url = assetURL(version)
                let bytes = try #require(transport.state.withLock { $0.files[url] })
                entry["engineRelease"] = [
                    "url": url.absoluteString, "sha256": Digest.sha256(of: bytes), "sizeBytes": bytes.count,
                ] as [String: Any]
            }
            bridges.append(entry)
        }
        let table = try JSONSerialization.data(withJSONObject: [
            "schema": 1, "serial": 1, "bridges": bridges,
        ] as [String: Any])
        let dir = supportDir.appending(path: EngineSupport.directoryName)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try table.write(to: dir.appending(path: BridgeCatalog.manifestName))
    }

    func release(_ version: String) async throws -> EngineRelease {
        try #require(try await updater.fetchManifest().release(for: .beta))
    }

    func install(_ version: String, mayQuitSteam: Bool = false) async throws -> EngineUpdateOutcome {
        try await updater.install(try await release(version), mayQuitSteam: mayQuitSteam)
    }

    func current() -> String? { EngineStore.currentTag(runners: runners) }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: path).path(percentEncoded: false))
    }

    func entries() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: runners.path(percentEncoded: false))) ?? []).sorted()
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Suite("Engine updater", .serialized)
struct EngineUpdaterTests {

    private func failure(_ body: () async throws -> Void) async -> String {
        do {
            try await body()
            return "no error"
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: Manifest

    @Test("The published Dormison manifest verifies with the pinned key, one changed byte does not")
    func realManifest() throws {
        // engine.json and engine.json.sig as published for dormison-b1.
        let body = try #require(Data(base64Encoded: Self.publishedManifest))
        let signature = Data("gdGun2XR6gI/EEaXUtWz9EahQVmfuyv3nMXmsY/P7xGCKULFxXni6/N8yWV/melE7WJ0fmjxjR96CD1KtbCtCQ==".utf8)
        let manifest = try EngineManifest.verified(body, signatureFile: signature)
        #expect(manifest.release(for: .beta)?.version == "dormison-b1")
        #expect(manifest.release(for: .beta)?.sizeBytes == 232_989_872)
        #expect(manifest.release(for: .stable) == nil)

        var forged = body
        forged[forged.count - 3] ^= 1
        #expect(throws: StepFailure.self) { try EngineManifest.verified(forged, signatureFile: signature) }
    }

    @Test("A fake manifest signed by another key is refused")
    func fakeManifest() async throws {
        let rig = Rig()
        defer { rig.remove() }
        try rig.supporting(["dormison-b1"])
        try rig.publish("dormison-b1")
        try rig.announce("dormison-b1", signer: Curve25519.Signing.PrivateKey())

        let message = await failure { _ = try await rig.updater.check(channel: .beta) }
        #expect(message.contains("signature"))
        #expect(rig.entries().isEmpty)
    }

    @Test("A release outside Dormison's GitHub releases is refused even when signed")
    func foreignAsset() throws {
        let body = Data("""
            {"schema": 2, "channels": {"beta": {"version": "dormison-b2", "url": "https://example.com/dormison-b2.tar.xz",
             "sha256": "\(String(repeating: "a", count: 64))", "sizeBytes": 1}}}
            """.utf8)
        #expect(throws: StepFailure.self) { try EngineManifest.decode(body) }
        let traversal = Data("""
            {"schema": 2, "channels": {"beta": {"version": "../dormison-b2",
             "url": "https://github.com/kageroumado/dormison/releases/download/b2/dormison-b2.tar.xz",
             "sha256": "\(String(repeating: "a", count: 64))", "sizeBytes": 1}}}
            """.utf8)
        #expect(throws: StepFailure.self) { try EngineManifest.decode(traversal) }
    }

    @Test("Channels: stable takes stable only, beta the newer of the two; versions order like Sevoflurane")
    func channels() {
        func release(_ channel: EngineChannel, _ version: String) -> EngineRelease {
            EngineRelease(
                channel: channel, version: version, url: URL(string: "https://github.com/x")!, sha256: "",
                sizeBytes: 1, notes: nil, minAppVersion: nil)
        }
        let betaOnly = EngineManifest(releases: [.beta: release(.beta, "dormison-b2")])
        #expect(betaOnly.release(for: .stable) == nil)
        #expect(betaOnly.release(for: .beta)?.version == "dormison-b2")
        let overtaken = EngineManifest(releases: [
            .beta: release(.beta, "dormison-b2"), .stable: release(.stable, "dormison-r2"),
        ])
        #expect(overtaken.release(for: .beta)?.version == "dormison-r2")
        #expect(EngineManifest.isOlder("dormison-b9", than: "dormison-b10"))
        #expect(EngineManifest.isOlder("dormison-b11", than: "dormison-r11"))
        #expect(!EngineManifest.isOlder("dormison-b2", than: "dormison-b1"))
    }

    // MARK: Check

    @Test("Check: available, up to date, waiting for support, nothing on the channel")
    func checking() async throws {
        let rig = Rig()
        defer { rig.remove() }
        try rig.supporting(["dormison-b1"])
        try rig.publish("dormison-b1")
        try rig.announce("dormison-b1")

        guard case .available(let release) = try await rig.updater.check(channel: .beta) else {
            Issue.record("expected an available release")
            return
        }
        #expect(release.version == "dormison-b1")
        #expect(try await rig.updater.check(channel: .stable) == .nothingOnChannel(.stable))

        _ = try await rig.install("dormison-b1")
        guard case .upToDate(_, let supported) = try await rig.updater.check(channel: .beta) else {
            Issue.record("expected up to date")
            return
        }
        #expect(supported)

        try rig.publish("dormison-b2")
        try rig.announce("dormison-b2")
        guard case .waiting(let newer, let reason) = try await rig.updater.check(channel: .beta) else {
            Issue.record("expected waiting for support")
            return
        }
        #expect(newer.version == "dormison-b2")
        #expect(reason.contains("bridge"))
    }

    @Test("Dormison's newest has no bridge: the newest engine that has one is installed, then the check waits")
    func newestWithBridge() async throws {
        let rig = Rig()
        defer { rig.remove() }
        try rig.publish("dormison-b1")
        try rig.publish("dormison-b2")
        try rig.publish("dormison-b3")
        try rig.announce("dormison-b3")
        try rig.supporting(["dormison-b1", "dormison-b2"], downloadable: ["dormison-b1", "dormison-b2"])

        guard case .available(let release) = try await rig.updater.check(channel: .beta) else {
            Issue.record("expected the newest engine with a bridge")
            return
        }
        #expect(release.version == "dormison-b2")
        #expect(release.url == rig.assetURL("dormison-b2"))
        let outcome = try await rig.updater.install(release, mayQuitSteam: false)
        #expect(outcome.version == "dormison-b2")
        #expect(rig.current() == "dormison-b2")

        // Installed is the newest with a bridge: nothing to take, b3 waits for its bridge.
        guard case .waiting(let newer, _) = try await rig.updater.check(channel: .beta) else {
            Issue.record("expected waiting for b3")
            return
        }
        #expect(newer.version == "dormison-b3")

        // A bridge that does not say where its engine comes from is not a way back to it.
        let empty = Rig()
        defer { empty.remove() }
        try empty.publish("dormison-b3")
        try empty.announce("dormison-b3")
        try empty.supporting(["dormison-b2"])
        guard case .waiting = try await empty.updater.check(channel: .beta) else {
            Issue.record("expected waiting without a known download")
            return
        }
    }

    @Test("An older installed engine moves up to the newest with a bridge; a bad tarball is still refused")
    func fallbackIsChecked() async throws {
        let rig = Rig()
        defer { rig.remove() }
        try rig.publish("dormison-b1")
        try rig.announce("dormison-b1")
        try rig.supporting(["dormison-b1"])
        _ = try await rig.install("dormison-b1")

        try rig.publish("dormison-b2", signer: Curve25519.Signing.PrivateKey())
        try rig.publish("dormison-b3")
        try rig.announce("dormison-b3")
        try rig.supporting(["dormison-b1", "dormison-b2"], downloadable: ["dormison-b2"])
        guard case .available(let release) = try await rig.updater.check(channel: .beta) else {
            Issue.record("expected b2")
            return
        }
        #expect(release.version == "dormison-b2")
        // b2's tarball carries another key's signature: refused, b1 stays.
        let message = await failure { _ = try await rig.updater.install(release, mayQuitSteam: false) }
        #expect(message != "no error")
        #expect(rig.current() == "dormison-b1")
    }

    @Test("A bridge's engine download must be Dormison's own release asset")
    func engineReleaseIsDormisons() throws {
        let base: [String: Any] = [
            "id": "bridge-dormison-b2-1", "engine": "dormison-b2",
            "engineCommit": String(repeating: "a", count: 40), "rev": 1,
            "files": BridgePayload.entries.map { ["name": $0.resource, "path": "bridge/\($0.resource)"] },
            "ntdll": ["x86_64", "i386"].map {
                ["arch": $0, "path": "wine/lib/wine/\($0)-windows/ntdll.dll", "file": "n/\($0).dll",
                 "clean": String(repeating: "1", count: 64), "b1": String(repeating: "2", count: 64)]
            },
        ]
        func parse(_ url: String) -> BridgeRelease? {
            var item = base
            item["engineRelease"] = ["url": url, "sha256": String(repeating: "3", count: 64), "sizeBytes": 10]
            return try? BridgeRelease.parse(item, remote: nil, root: URL(filePath: "/tmp"), bundled: true)
        }
        let good = parse("https://github.com/kageroumado/dormison/releases/download/b2/dormison-b2.tar.xz")
        #expect(good?.engineRelease?.sizeBytes == 10)
        #expect(parse("https://example.com/kageroumado/dormison/releases/download/b2/dormison-b2.tar.xz") == nil)
        #expect(parse("https://github.com/someone/dormison/releases/download/b2/dormison-b2.tar.xz") == nil)
        #expect(parse("https://github.com/kageroumado/dormison/releases/download/b3/dormison-b3.tar.xz") == nil)
    }

    // MARK: Install

    @Test("Install from nothing: verified, B1 in place, current set, bridge copy synced, download removed")
    func freshInstall() async throws {
        let rig = Rig()
        defer { rig.remove() }
        try rig.supporting(["dormison-b1"])
        try rig.publish("dormison-b1")
        try rig.announce("dormison-b1")

        let outcome = try await rig.install("dormison-b1")
        #expect(outcome.version == "dormison-b1")
        #expect(outcome.previous == nil)
        #expect(outcome.smoke == "fake smoke")
        #expect(rig.current() == "dormison-b1")
        let ntdll = rig.runners.appending(path: "dormison-b1/wine/lib/wine/x86_64-windows/ntdll.dll")
        #expect(try Data(contentsOf: ntdll) == rig.b1Ntdll("x86_64", "dormison-b1"))
        #expect(try Data(contentsOf: rig.runners.appending(
            path: "dormison-b1/wine/lib/wine/i386-windows/ntdll.dll.notproton-orig")) == rig.cleanNtdll("i386", "dormison-b1"))
        #expect(try Data(contentsOf: rig.bridge.appending(path: "wine/i386-windows/ntdll.dll"))
            == rig.b1Ntdll("i386", "dormison-b1"))
        #expect(rig.exists("runners/dormison-b1/notproton-engine.env"))
        #expect(rig.entries() == ["current", "dormison-b1"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: rig.cache.path(percentEncoded: false)).isEmpty)
    }

    @Test("A fake tarball (signed by another key) is refused and deleted; nothing is installed")
    func fakeTarball() async throws {
        let rig = Rig()
        defer { rig.remove() }
        try rig.supporting(["dormison-b1"])
        try rig.publish("dormison-b1", signer: Curve25519.Signing.PrivateKey())
        try rig.announce("dormison-b1")

        let message = await failure { _ = try await rig.install("dormison-b1") }
        #expect(message.contains("signature"))
        #expect(rig.entries().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: rig.cache.path(percentEncoded: false)).isEmpty)
    }

    @Test("A sha256 that does not match the manifest is refused and the download deleted")
    func shaMismatch() async throws {
        let rig = Rig()
        defer { rig.remove() }
        try rig.supporting(["dormison-b1"])
        let wrong = try rig.publish("dormison-b1", wrongSha: true)
        try rig.announce("dormison-b1", sha: wrong)

        let message = await failure { _ = try await rig.install("dormison-b1") }
        #expect(message.contains("sha256"))
        #expect(rig.entries().isEmpty)
        #expect(!rig.exists("cache/dormison-b1.tar.xz.part"))
    }

    @Test("A file changed after packaging fails the engine-manifest.json check")
    func tamperedFile() async throws {
        let rig = Rig()
        defer { rig.remove() }
        try rig.supporting(["dormison-b1"])
        try rig.publish("dormison-b1", tamper: true)
        try rig.announce("dormison-b1")

        let message = await failure { _ = try await rig.install("dormison-b1") }
        #expect(message.contains("do not match"))
        #expect(rig.current() == nil)
        #expect(!rig.exists("runners/.dormison-b1.partial"))
    }

    @Test("No network: a clear message and nothing changes")
    func offline() async throws {
        let rig = Rig()
        defer { rig.remove() }
        try rig.supporting(["dormison-b1"])
        try rig.publish("dormison-b1")
        try rig.announce("dormison-b1")
        _ = try await rig.install("dormison-b1")
        let release = try await rig.release("dormison-b1")
        rig.transport.state.withLock { $0.offline = true }

        let check = await failure { _ = try await rig.updater.check(channel: .beta) }
        #expect(check.contains("could not reach GitHub"))
        let install = await failure { _ = try await rig.updater.install(release, mayQuitSteam: false) }
        #expect(install.contains("could not reach GitHub"))
        #expect(rig.current() == "dormison-b1")
        #expect(rig.entries() == ["current", "dormison-b1"])
    }

    @Test("An interrupted download keeps what arrived and the next try continues from there")
    func resume() async throws {
        let rig = Rig()
        defer { rig.remove() }
        try rig.supporting(["dormison-b1"])
        try rig.publish("dormison-b1")
        try rig.announce("dormison-b1")
        let release = try await rig.release("dormison-b1")
        rig.transport.state.withLock { $0.cutAfter = 100 }

        let message = await failure { _ = try await rig.updater.install(release, mayQuitSteam: false) }
        #expect(message.contains("next try continues"))
        let part = rig.cache.appending(path: "dormison-b1.tar.xz.part")
        #expect((try FileManager.default.attributesOfItem(atPath: part.path(percentEncoded: false))[.size] as? Int) == 100)
        #expect(rig.current() == nil)

        _ = try await rig.updater.install(release, mayQuitSteam: false)
        #expect(rig.transport.state.withLock { $0.downloadStarts } == [0, 100])
        #expect(rig.current() == "dormison-b1")
    }

    @Test("A failed smoke test leaves the current engine as it was")
    func smokeFailure() async throws {
        let rig = Rig()
        defer { rig.remove() }
        try rig.supporting(["dormison-b1", "dormison-b2"])
        try rig.publish("dormison-b1")
        try rig.announce("dormison-b1")
        _ = try await rig.install("dormison-b1")
        try rig.publish("dormison-b2")
        try rig.announce("dormison-b2")
        rig.flags.smokeFails.withLock { $0 = true }

        let message = await failure { _ = try await rig.install("dormison-b2") }
        #expect(message.contains("wineboot failed"))
        #expect(rig.current() == "dormison-b1")
        #expect(rig.entries() == ["current", "dormison-b1"])
    }

    // MARK: Guards

    @Test("No update while a game runs; Steam is closed only with consent")
    func runningGameAndSteam() async throws {
        let rig = Rig()
        defer { rig.remove() }
        try rig.supporting(["dormison-b1"])
        try rig.publish("dormison-b1")
        try rig.announce("dormison-b1")

        rig.flags.game.withLock { $0 = true }
        let game = await failure { _ = try await rig.install("dormison-b1") }
        #expect(game.contains("A game is running"))
        #expect(rig.transport.state.withLock { $0.downloads } == 0)

        rig.flags.game.withLock { $0 = false }
        rig.flags.steam.withLock { $0 = true }
        let steam = await failure { _ = try await rig.install("dormison-b1") }
        #expect(steam.contains("Steam is running"))
        #expect(rig.transport.state.withLock { $0.downloads } == 0)

        let outcome = try await rig.install("dormison-b1", mayQuitSteam: true)
        #expect(outcome.stoppedSteam)
        #expect(rig.flags.quits.withLock { $0 } == 1)
        #expect(rig.current() == "dormison-b1")

        rig.flags.game.withLock { $0 = true }
        #expect(throws: StepFailure.self) { try rig.updater.rollback(mayQuitSteam: true) }
    }

    @Test("No compatible bridge or B1 ntdll: the check says so and install refuses")
    func noBridge() async throws {
        let rig = Rig()
        defer { rig.remove() }
        try rig.publish("dormison-b1")
        try rig.announce("dormison-b1")

        try rig.supporting(["dormison-b2"])
        guard case .waiting(_, let reason) = try await rig.updater.check(channel: .beta) else {
            Issue.record("expected waiting")
            return
        }
        #expect(reason.contains("bridge"))
        let message = await failure { _ = try await rig.install("dormison-b1") }
        #expect(message.contains("does not support it yet"))
        #expect(rig.transport.state.withLock { $0.downloads } == 0)

        try rig.supporting(["dormison-b1"], missingB1: true)
        guard case .waiting(_, let missing) = try await rig.updater.check(channel: .beta) else {
            Issue.record("expected waiting")
            return
        }
        #expect(missing.contains("missing"))

        try rig.supporting([])
        guard case .waiting = try await rig.updater.check(channel: .beta) else {
            Issue.record("expected waiting")
            return
        }
        #expect(rig.entries().isEmpty)
    }

    @Test("A release built from another commit than the bridge is refused after unpacking")
    func commitMismatch() async throws {
        let rig = Rig()
        defer { rig.remove() }
        try rig.supporting(["dormison-b1"])
        try rig.publish("dormison-b1", commit: "1111111111111111111111111111111111111111")
        try rig.announce("dormison-b1")

        let message = await failure { _ = try await rig.install("dormison-b1") }
        #expect(message.contains("bridge is for"))
        #expect(rig.entries().isEmpty)
    }

    @Test("The UI path: prepare with Steam open, then the switch closes Steam; Retry after Steam stayed")
    func prepareThenSwitch() async throws {
        let rig = Rig()
        defer { rig.remove() }
        try rig.supporting(["dormison-b1", "dormison-b2"])
        try rig.publish("dormison-b1")
        try rig.announce("dormison-b1")
        _ = try await rig.install("dormison-b1")
        try rig.publish("dormison-b2")
        try rig.announce("dormison-b2")
        rig.flags.steam.withLock { $0 = true }

        // Steam stays open through the download and the checks.
        let prepared = try await rig.updater.prepare(try await rig.release("dormison-b2"))
        #expect(rig.flags.quits.withLock { $0 } == 0)
        #expect(rig.current() == "dormison-b1")
        #expect(rig.exists("runners/.dormison-b2.partial/wine/bin/wine"))

        // Without the person's yes the switch refuses and leaves everything.
        #expect(throws: StepFailure.self) { try rig.updater.activatePrepared(prepared, mayQuitSteam: false) }
        #expect(rig.current() == "dormison-b1")

        // Steam will not quit: the prepared tree stays for Retry.
        rig.flags.quitFails.withLock { $0 = true }
        #expect(throws: SteamBundle.StillRunning.self) {
            try rig.updater.activatePrepared(prepared, mayQuitSteam: true)
        }
        #expect(rig.exists("runners/.dormison-b2.partial/wine/bin/wine"))
        #expect(rig.current() == "dormison-b1")

        // Retry: Steam quits now and the switch happens without a new download.
        rig.flags.quitFails.withLock { $0 = false }
        let downloads = rig.transport.state.withLock { $0.downloads }
        let outcome = try rig.updater.activatePrepared(prepared, mayQuitSteam: true)
        #expect(outcome.stoppedSteam)
        #expect(rig.current() == "dormison-b2")
        #expect(rig.transport.state.withLock { $0.downloads } == downloads)
        #expect(!rig.exists("runners/.dormison-b2.partial"))
    }

    @Test("A prepared engine that is not wanted is dropped")
    func discardPrepared() async throws {
        let rig = Rig()
        defer { rig.remove() }
        try rig.supporting(["dormison-b1"])
        try rig.publish("dormison-b1")
        try rig.announce("dormison-b1")
        let prepared = try await rig.updater.prepare(try await rig.release("dormison-b1"))
        #expect(rig.exists("runners/.dormison-b1.partial"))
        rig.updater.discard(prepared)
        #expect(!rig.exists("runners/.dormison-b1.partial"))
        #expect(rig.current() == nil)
    }

    // MARK: Rollback

    @Test("Update keeps one previous engine; Rollback goes back and forth")
    func updateAndRollback() async throws {
        let rig = Rig()
        defer { rig.remove() }
        try rig.supporting(["dormison-b1", "dormison-b2", "dormison-b3"])
        for version in ["dormison-b1", "dormison-b2", "dormison-b3"] {
            try rig.publish(version)
            try rig.announce(version)
            _ = try await rig.install(version)
        }
        #expect(rig.entries() == ["current", "dormison-b2", "dormison-b3", "previous"])
        #expect(rig.updater.rollbackTarget == "dormison-b2")

        let back = try rig.updater.rollback(mayQuitSteam: false)
        #expect(back == EngineRollbackOutcome(from: "dormison-b3", to: "dormison-b2", stoppedSteam: false))
        #expect(rig.current() == "dormison-b2")
        #expect(rig.updater.rollbackTarget == "dormison-b3")
        #expect(try Data(contentsOf: rig.bridge.appending(path: "wine/x86_64-windows/ntdll.dll"))
            == rig.b1Ntdll("x86_64", "dormison-b2"))

        _ = try rig.updater.rollback(mayQuitSteam: false)
        #expect(rig.current() == "dormison-b3")
    }

    @Test("Reinstalling the active version keeps the old tree; Rollback swaps them")
    func reinstallAndRollback() async throws {
        let rig = Rig()
        defer { rig.remove() }
        try rig.supporting(["dormison-b1"])
        try rig.publish("dormison-b1")
        try rig.announce("dormison-b1")
        _ = try await rig.install("dormison-b1")
        let marker = "runners/dormison-b1/old-tree"
        try Data().write(to: rig.root.appending(path: marker))

        let outcome = try await rig.install("dormison-b1")
        #expect(outcome.reinstalled)
        #expect(outcome.previous == ".previous-dormison-b1")
        #expect(rig.current() == "dormison-b1")
        #expect(!rig.exists(marker))
        #expect(rig.exists("runners/.previous-dormison-b1/old-tree"))
        #expect(rig.updater.rollbackTarget == "dormison-b1")

        let back = try rig.updater.rollback(mayQuitSteam: false)
        #expect(back.from == "dormison-b1")
        #expect(rig.exists(marker))
        #expect(rig.current() == "dormison-b1")
        _ = try rig.updater.rollback(mayQuitSteam: false)
        #expect(!rig.exists(marker))
    }

    @Test("Nothing to roll back to is said plainly")
    func nothingToRollBack() async throws {
        let rig = Rig()
        defer { rig.remove() }
        try rig.supporting(["dormison-b1"])
        try rig.publish("dormison-b1")
        try rig.announce("dormison-b1")
        _ = try await rig.install("dormison-b1")
        #expect(rig.updater.rollbackTarget == nil)
        let message = await failure { _ = try rig.updater.rollback(mayQuitSteam: false) }
        #expect(message.contains("no previous engine"))
    }

    @Test("A new engine brings its bridge from NotProton's releases; Roll Back brings the old engine's bridge back")
    func engineFetchesBridge() async throws {
        let rig = Rig()
        defer { rig.remove() }
        try rig.supporting(["dormison-b1"])
        try rig.publish("dormison-b1")
        try rig.announce("dormison-b1")
        _ = try await rig.install("dormison-b1")
        #expect(try Data(contentsOf: rig.bridge.appending(path: "steam.exe")) == Data("bridge file steam.exe".utf8))

        // dormison-b2's bridge is only in the signed list of the release feed.
        let feedRig = BridgeRig()
        defer { feedRig.remove() }
        let entry = try feedRig.artifact("dormison-b2", rev: 1, commit: Rig.commit)
        rig.transport.state.withLock { state in
            for (url, data) in feedRig.feed.transport.files.withLock({ $0 }) { state.files[url] = data }
        }
        let remote = BridgeRelease.list(["bridges": [entry]], remote: feedRig.feed.feed, root: nil, bundled: false)
        #expect(remote.count == 1)
        var updater = rig.updater
        updater.feed = feedRig.feed.setup
        let supportDir = rig.supportDir, bridges = rig.bridges
        updater.support = {
            BridgeCatalog(releases: BridgeCatalog.bundled(root: supportDir)
                + BridgeStore.installedReleases(in: bridges) + remote)
        }

        try rig.publish("dormison-b2")
        try rig.announce("dormison-b2")
        guard case .available(let release) = try await updater.check(channel: .beta) else {
            Issue.record("dormison-b2 should be installable: its bridge is on the feed")
            return
        }
        _ = try await updater.install(release, mayQuitSteam: false)
        #expect(rig.current() == "dormison-b2")
        #expect(BridgeStore.installedReleases(in: rig.bridges).map(\.id) == ["bridge-dormison-b2-1"])
        let b2 = rig.runners.appending(path: "dormison-b2/wine/lib/wine")
        #expect(try Data(contentsOf: b2.appending(path: "x86_64-windows/ntdll.dll"))
            == BridgeRig.b1("x86_64", "dormison-b2", rev: 1))
        #expect(try Data(contentsOf: rig.bridge.appending(path: "steam.exe")) == BridgeRig.file("steam.exe", rev: 1))
        #expect(try Data(contentsOf: rig.bridge.appending(path: "wine/i386-windows/ntdll.dll"))
            == BridgeRig.b1("i386", "dormison-b2", rev: 1))
        let store = updater.bridgeStore
        #expect(store.state == .init(current: "bridge-dormison-b2-1", previous: "bridge-dormison-b1-1"))

        _ = try updater.rollback(mayQuitSteam: false)
        #expect(rig.current() == "dormison-b1")
        #expect(try Data(contentsOf: rig.bridge.appending(path: "steam.exe")) == Data("bridge file steam.exe".utf8))
        #expect(try Data(contentsOf: rig.bridge.appending(path: "wine/x86_64-windows/ntdll.dll"))
            == rig.b1Ntdll("x86_64", "dormison-b1"))
        #expect(store.state == .init(current: "bridge-dormison-b1-1", previous: "bridge-dormison-b2-1"))
    }

    @Test("The shipped bridge list names dormison-b2 with its commit, both B1 files and its Dormison download")
    func shippedTable() throws {
        let repo = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../..").standardizedFileURL
        let data = try Data(contentsOf: repo.appending(path: "bridge/bridge-manifest.json"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let releases = BridgeRelease.list(json, remote: nil, root: repo, bundled: true)
        let entry = try #require(releases.first { $0.engine == "dormison-b2" })
        #expect(entry.engineCommit == "768e85ab0393025b463f5f371810a12a34d0466d")
        // Any revision: a release bundles the one dormison-bridge published (DECISIONS P6-2).
        #expect(entry.id == "bridge-dormison-b2-\(entry.rev)")
        // Install falls back to it while Dormison's newest has no bridge (DECISIONS P8-17).
        let download = try #require(entry.engineRelease)
        #expect(download.url.absoluteString == "https://github.com/kageroumado/dormison/releases/download/b2/dormison-b2.tar.xz")
        #expect(download.sizeBytes == 232_970_284)
        #expect(Set(entry.ntdll.map(\.arch)) == ["x86_64", "i386"])
        #expect(Set(entry.files.map(\.name)) == BridgeRelease.fileNames)
        _ = EngineSignature.dormisonKey
    }

    static let publishedManifest = """
        ewogICJzY2hlbWEiOiAyLAogICJjaGFubmVscyI6IHsKICAgICJiZXRhIjogewogICAgICAidmVyc2lvbiI6ICJkb3JtaXNvbi1iMSIsCiAgICAgICJtaW5BcHBWZXJzaW9uIjogIjEuMC4wLWJldGEuMSIsCiAgICAgICJ1cmwiOiAiaHR0cHM6Ly9naXRodWIuY29tL2thZ2Vyb3VtYWRvL2Rvcm1pc29uL3JlbGVhc2VzL2Rvd25sb2FkL2IxL2Rvcm1pc29uLWIxLnRhci54eiIsCiAgICAgICJzaGEyNTYiOiAiMjNlMjVhYTQ2MjkwZmQyZmE0NmFhNzViN2NkYTUzMmUzZGIzNmZjZjk5NWYzMjRiODQ1MGE3MGY1NTcyMzVkZSIsCiAgICAgICJzaXplQnl0ZXMiOiAyMzI5ODk4NzIsCiAgICAgICJub3RlcyI6ICJ3aW5lIDExLjE2ICsgd2luZS1zdGFnaW5nIDExLjE2OyBjb21taXQgNTJjMmE0YjkxOGQ2IgogICAgfQogIH0sCiAgImNvbXBvbmVudHMiOiB7CiAgICAiZHhtdCI6IFsKICAgICAgewogICAgICAgICJ2ZXJzaW9uIjogIjAuODAiLAogICAgICAgICJ1cmwiOiAiaHR0cHM6Ly9naXRodWIuY29tLzNTaGFpbi9keG10L3JlbGVhc2VzL2Rvd25sb2FkL3YwLjgwL2R4bXQtdjAuODAtYnVpbHRpbi50YXIuZ3oiLAogICAgICAgICJzaGEyNTYiOiAiOGYyNjBlMzZiNTczOWU2OGYzYmFkNjEzMzgxNDQxMzg1YzRkYzdiODViNzhiYThkZTY1M2Q1YTZhMjY0NTI5ZCIsCiAgICAgICAgIm5vdGVzIjogInJ1biB3aXRoIGRvcm1pc29uLWIxIgogICAgICB9CiAgICBdLAogICAgImR4dmsiOiBbCiAgICAgIHsKICAgICAgICAidmVyc2lvbiI6ICIxLjEwLjMtMjAyMzA1MDctcmVwYWNrIiwKICAgICAgICAidXJsIjogImh0dHBzOi8vZ2l0aHViLmNvbS9HY2VueC9EWFZLLW1hY09TL3JlbGVhc2VzL2Rvd25sb2FkL3YxLjEwLjMtMjAyMzA1MDctcmVwYWNrL2R4dmstbWFjT1MtYXN5bmMtdjEuMTAuMy0yMDIzMDUwNy1yZXBhY2stYnVpbHRpbi50YXIuZ3oiLAogICAgICAgICJzaGEyNTYiOiAiODEwYjFlNWNhZjhjZTk3NWI3ODRmYWU4NjZhMTMwYWQyM2ZhMGVhMjMzYjBlNTYwOWNiYzRhNDVmM2VmNmYwMCIsCiAgICAgICAgIm5vdGVzIjogInJ1biB3aXRoIGRvcm1pc29uLWIxIgogICAgICB9CiAgICBdCiAgfQp9Cg==
        """
}
