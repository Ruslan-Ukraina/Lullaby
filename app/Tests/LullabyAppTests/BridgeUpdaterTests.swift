import CryptoKit
import Foundation
import Testing

@testable import LullabyApp

@Suite("Steam bridge updater", .serialized)
struct BridgeUpdaterTests {

    @Test("The bundled bridge fits the engine: follow() puts its files and B1 pair in place")
    func bundledFollows() throws {
        let rig = BridgeRig()
        defer { rig.remove() }
        try rig.engine()
        try rig.bundled()
        let updater = rig.updater
        let engineRoot = rig.runners.appending(path: "dormison-b1")
        let chosen = updater.store.follow(engine: engineRoot, catalog: updater.catalog())
        #expect(chosen?.id == "bridge-dormison-b1-1")
        #expect(chosen?.isBundled == true)
        #expect(rig.liveFile("steam.exe") == BridgeRig.file("steam.exe", rev: 1))
        #expect(rig.liveFile("x86_64-windows/lsteamclient.dll") == BridgeRig.file("x86_64-windows-lsteamclient.dll", rev: 1))
        #expect(rig.engineNtdll("x86_64") == BridgeRig.b1("x86_64", "dormison-b1", rev: 1))
        #expect(rig.engineNtdll("i386") == BridgeRig.b1("i386", "dormison-b1", rev: 1))
        // The release's file is kept for the next revision and for engine reinstalls.
        let orig = engineRoot.appending(path: "wine/lib/wine/i386-windows/ntdll.dll.lullaby-orig")
        #expect(try Data(contentsOf: orig) == BridgeRig.clean("i386", "dormison-b1"))
        // compat_run.sh compares the engine against the bridge's copy.
        #expect(rig.liveFile("wine/x86_64-windows/ntdll.dll") == BridgeRig.b1("x86_64", "dormison-b1", rev: 1))
        #expect(updater.store.state == .init(current: "bridge-dormison-b1-1", previous: nil))
        #expect(updater.active?.id == "bridge-dormison-b1-1")
    }

    @Test("Before state.json exists, the bridge already in lullaby/bridge counts as active")
    func inferredActive() async throws {
        let rig = BridgeRig()
        defer { rig.remove() }
        try rig.engine()
        try rig.bundled()
        let updater = rig.updater
        #expect(updater.active == nil)
        // What SteamInstaller staged before Phase 5: the bundled files, no state.json.
        _ = try BridgePayload.stage(
            located: try #require(updater.catalog().release(id: "bridge-dormison-b1-1")).located(), bridge: rig.live)
        #expect(updater.active?.id == "bridge-dormison-b1-1")
        guard case .upToDate(let current) = try await updater.check(refresh: false) else {
            Issue.record("the staged bundled bridge should be up to date")
            return
        }
        #expect(current.id == "bridge-dormison-b1-1")

        // A new revision then keeps the inferred one for Roll Back.
        try rig.publishManifest(serial: 1, [try rig.artifact(rev: 2)])
        guard case .available(let offered, _) = try await updater.check() else {
            Issue.record("expected revision 2 on offer")
            return
        }
        let outcome = try await updater.install(offered)
        #expect(outcome.previous == "bridge-dormison-b1-1")
        #expect(updater.rollbackTarget?.id == "bridge-dormison-b1-1")
    }

    @Test("An incompatible engine/bridge pair is refused and nothing changes")
    func incompatiblePair() async throws {
        let rig = BridgeRig()
        defer { rig.remove() }
        try rig.engine()
        try rig.bundled()
        let updater = rig.updater
        let engineRoot = rig.runners.appending(path: "dormison-b1")
        updater.store.follow(engine: engineRoot, catalog: updater.catalog())

        // Built against another commit of the same version.
        let otherCommit = String(repeating: "1", count: 40)
        try rig.publishManifest(serial: 1, [try rig.artifact(rev: 2, commit: otherCommit)])
        guard case .upToDate(let current) = try await updater.check() else {
            Issue.record("a bridge for another commit must not be offered")
            return
        }
        #expect(current.id == "bridge-dormison-b1-1")
        let foreign = try #require(updater.catalog().release(id: "bridge-dormison-b1-2"))
        let message = await failureMessage { _ = try await updater.install(foreign) }
        #expect(message.contains("was built against 111111111111"))

        // Built for another Dormison version.
        try rig.publishManifest(serial: 2, [try rig.artifact("dormison-b2", rev: 1)])
        _ = try await updater.check()
        let b2 = try #require(updater.catalog().release(id: "bridge-dormison-b2-1"))
        let other = await failureMessage { _ = try await updater.install(b2) }
        #expect(other.contains("is for Dormison b2"))

        // The release's ntdll.dll is not the one the B1 pair was built from.
        try Data("someone else's ntdll".utf8).write(
            to: engineRoot.appending(path: "wine/lib/wine/x86_64-windows/ntdll.dll"))
        try FileManager.default.removeItem(
            at: engineRoot.appending(path: "wine/lib/wine/x86_64-windows/ntdll.dll.lullaby-orig"))
        let bundled = try #require(updater.catalog().release(id: "bridge-dormison-b1-1"))
        let patched = await failureMessage { try updater.store.activate(bundled, engine: engineRoot) }
        #expect(patched.contains("not the file the Steam loader patch was built for"))

        #expect(rig.liveFile("steam.exe") == BridgeRig.file("steam.exe", rev: 1))
        #expect(updater.store.state.current == "bridge-dormison-b1-1")
        #expect(!FileManager.default.fileExists(atPath: rig.store.appending(path: "bridge-dormison-b1-2").path(percentEncoded: false)))
    }

    @Test("A new revision downloads, verifies and activates; Roll Back returns to the bundled one and forth")
    func updateAndRollback() async throws {
        let rig = BridgeRig()
        defer { rig.remove() }
        try rig.engine()
        try rig.bundled()
        let updater = rig.updater
        updater.store.follow(engine: rig.runners.appending(path: "dormison-b1"), catalog: updater.catalog())
        #expect(updater.rollbackTarget == nil)

        try rig.publishManifest(serial: 1, [try rig.artifact(rev: 2)])
        guard case .available(let offered, let current) = try await updater.check() else {
            Issue.record("expected revision 2 on offer")
            return
        }
        #expect(offered.id == "bridge-dormison-b1-2")
        #expect(current?.id == "bridge-dormison-b1-1")

        let outcome = try await updater.install(offered)
        #expect(outcome == BridgeOutcome(id: "bridge-dormison-b1-2", previous: "bridge-dormison-b1-1"))
        #expect(rig.liveFile("steam.exe") == BridgeRig.file("steam.exe", rev: 2))
        #expect(rig.liveFile("i386-windows/lsteamclient.dll") == BridgeRig.file("i386-windows-lsteamclient.dll", rev: 2))
        #expect(rig.engineNtdll("x86_64") == BridgeRig.b1("x86_64", "dormison-b1", rev: 2))
        #expect(rig.liveFile("wine/i386-windows/ntdll.dll") == BridgeRig.b1("i386", "dormison-b1", rev: 2))
        #expect(updater.store.state == .init(current: "bridge-dormison-b1-2", previous: "bridge-dormison-b1-1"))
        guard case .upToDate(let now) = try await updater.check() else {
            Issue.record("expected up to date")
            return
        }
        #expect(now.id == "bridge-dormison-b1-2")
        // The download is gone, the build sits in bridges/ with its entry.
        #expect(try FileManager.default.contentsOfDirectory(atPath: rig.root.appending(path: "cache").path(percentEncoded: false)).isEmpty)
        let installed = BridgeStore.installedReleases(in: rig.store)
        #expect(installed.map(\.id) == ["bridge-dormison-b1-2"])

        #expect(updater.rollbackTarget?.id == "bridge-dormison-b1-1")
        let back = try updater.rollback()
        #expect(back == BridgeOutcome(id: "bridge-dormison-b1-1", previous: "bridge-dormison-b1-2"))
        #expect(rig.liveFile("steam.exe") == BridgeRig.file("steam.exe", rev: 1))
        #expect(rig.engineNtdll("i386") == BridgeRig.b1("i386", "dormison-b1", rev: 1))
        #expect(updater.store.state == .init(current: "bridge-dormison-b1-1", previous: "bridge-dormison-b1-2"))

        // And forth again, without a download: revision 2 is kept for it.
        rig.feed.transport.offline.withLock { $0 = true }
        #expect(updater.rollbackTarget?.id == "bridge-dormison-b1-2")
        _ = try updater.rollback()
        #expect(rig.liveFile("steam.exe") == BridgeRig.file("steam.exe", rev: 2))
        #expect(rig.engineNtdll("x86_64") == BridgeRig.b1("x86_64", "dormison-b1", rev: 2))
    }

    @Test("An engine fix rides with the bridge: in place with the release's file kept, undone by a roll-back")
    func engineFixFollowsTheBridge() async throws {
        let rig = BridgeRig()
        defer { rig.remove() }
        try rig.engine()
        try rig.bundled()
        let updater = rig.updater
        updater.store.follow(engine: rig.runners.appending(path: "dormison-b1"), catalog: updater.catalog())
        let fix = BridgeRig.fixPath
        #expect(rig.engineFile(fix) == BridgeRig.cleanFix("dormison-b1"))

        try rig.publishManifest(serial: 1, [try rig.artifact(rev: 2, engineFix: true)])
        guard case .available(let offered, _) = try await updater.check() else {
            Issue.record("expected revision 2 on offer")
            return
        }
        #expect(offered.engineFiles.map(\.path) == [fix])
        _ = try await updater.install(offered)
        #expect(rig.engineFile(fix) == BridgeRig.fixed("dormison-b1", rev: 2))
        #expect(rig.engineFile(fix + ".lullaby-orig") == BridgeRig.cleanFix("dormison-b1"))
        #expect(rig.engineNtdll("x86_64") == BridgeRig.b1("x86_64", "dormison-b1", rev: 2))
        // The entry as installed keeps the fix, so the bridge on disk is complete.
        let installed = try #require(BridgeStore.installedReleases(in: rig.store).first)
        #expect(installed.engineFiles == offered.engineFiles)

        // Revision 1 carries no fix: the release's file comes back and the copy goes.
        _ = try updater.rollback()
        #expect(rig.engineFile(fix) == BridgeRig.cleanFix("dormison-b1"))
        #expect(rig.engineFile(fix + ".lullaby-orig") == nil)
        #expect(rig.engineNtdll("x86_64") == BridgeRig.b1("x86_64", "dormison-b1", rev: 1))

        // Forth again: the fix is back.
        _ = try updater.rollback()
        #expect(rig.engineFile(fix) == BridgeRig.fixed("dormison-b1", rev: 2))
    }

    @Test("A bridge with engine fixes packed in the app: unpacked and checked without a feed; a damaged one refused")
    func packedBridge() async throws {
        let rig = BridgeRig()
        defer { rig.remove() }
        let fm = FileManager.default
        try rig.engine()
        let entry = try rig.artifact(rev: 2, engineFix: true)
        let id = "bridge-dormison-b1-2"
        let built = try #require(fm.enumerator(at: rig.root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.first { $0.lastPathComponent == "\(id).tar.xz" })
        let archive = rig.payload.appending(path: "engine-support/\(id).tar.xz")
        try fm.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: built, to: archive)
        var packed = entry.filter { !["url", "sha256", "sizeBytes"].contains($0.key) }
        packed["archive"] = ["path": "engine-support/\(id).tar.xz", "sha256": entry["sha256"]!, "sizeBytes": entry["sizeBytes"]!]
        try JSONSerialization.data(withJSONObject: ["schema": 1, "serial": 1, "bridges": [packed]] as [String: Any])
            .write(to: rig.payload.appending(path: "engine-support/bridge-manifest.json"))

        var updater = rig.updater
        updater.feed = .off("test")
        guard case .available(let offered, nil) = try await updater.check() else {
            Issue.record("the packed bridge should be offered")
            return
        }
        #expect(offered.isBundled)
        #expect(offered.root == nil)
        #expect(BridgeCatalog.load(bundledRoot: rig.payload, store: rig.store, feed: .off("test"), manifests: rig.manifests)
            .verdict(for: "dormison-b1") == .supported(offered))
        _ = try await updater.install(offered)
        #expect(updater.active?.id == id)
        #expect(rig.engineFile(BridgeRig.fixPath) == BridgeRig.fixed("dormison-b1", rev: 2))
        #expect(rig.liveFile("steam.exe") == BridgeRig.file("steam.exe", rev: 2))
        #expect(fm.fileExists(atPath: archive.path(percentEncoded: false)), "the app's own copy stays")
        #expect(rig.feed.transport.fetched.withLock { $0 }.isEmpty)

        // Gone from bridges/ (Delete) and damaged in the app: refused, nothing unpacked.
        try fm.removeItem(at: rig.store)
        let handle = try FileHandle(forWritingTo: archive)
        try handle.seek(toOffset: 40)
        try handle.write(contentsOf: Data("x".utf8))
        try handle.close()
        let message = await failureMessage { _ = try await updater.install(offered) }
        #expect(message.contains("damaged"))
        #expect(BridgeStore.installedReleases(in: rig.store).isEmpty)
    }

    @Test("An engine fix for a file that is not the release's is refused, the engine untouched")
    func engineFixRefusesForeignFile() async throws {
        let rig = BridgeRig()
        defer { rig.remove() }
        try rig.engine()
        try rig.bundled()
        let updater = rig.updater
        updater.store.follow(engine: rig.runners.appending(path: "dormison-b1"), catalog: updater.catalog())
        let foreign = Data("someone else's winemac.so".utf8)
        try foreign.write(to: rig.runners.appending(path: "dormison-b1/\(BridgeRig.fixPath)"))

        try rig.publishManifest(serial: 1, [try rig.artifact(rev: 2, engineFix: true)])
        guard case .available(let offered, _) = try await updater.check() else {
            Issue.record("expected revision 2 on offer")
            return
        }
        let message = await failureMessage { _ = try await updater.install(offered) }
        #expect(message.contains("not the file NotProton's fix was built for"))
        #expect(rig.engineFile(BridgeRig.fixPath) == foreign)
    }

    @Test("Fake signatures: a manifest or an artifact signed by another key is refused")
    func fakeSignatures() async throws {
        let rig = BridgeRig()
        defer { rig.remove() }
        try rig.engine()
        try rig.bundled()
        let updater = rig.updater
        updater.store.follow(engine: rig.runners.appending(path: "dormison-b1"), catalog: updater.catalog())
        let stranger = Curve25519.Signing.PrivateKey()

        try rig.publishManifest(serial: 1, [try rig.artifact(rev: 2)], signer: stranger)
        let manifest = await failureMessage { _ = try await updater.check() }
        #expect(manifest.contains("does not carry NotProton's release signature"))
        #expect(updater.catalog().release(id: "bridge-dormison-b1-2") == nil)
        #expect(!FileManager.default.fileExists(atPath: rig.manifests.appending(path: BridgeCatalog.manifestName).path(percentEncoded: false)))

        // A cached manifest edited on disk no longer verifies, so it is not read.
        try rig.publishManifest(serial: 1, [try rig.artifact(rev: 2, signer: stranger)])
        _ = try await updater.check()
        let offered = try #require(updater.catalog().release(id: "bridge-dormison-b1-2"))
        let artifact = await failureMessage { _ = try await updater.install(offered) }
        #expect(artifact.contains("does not carry NotProton's release signature"))
        #expect(BridgeStore.installedReleases(in: rig.store).isEmpty)
        #expect(rig.liveFile("steam.exe") == BridgeRig.file("steam.exe", rev: 1))

        let cached = rig.manifests.appending(path: BridgeCatalog.manifestName)
        var text = try String(contentsOf: cached, encoding: .utf8)
        text = text.replacingOccurrences(of: "\"rev\":2", with: "\"rev\":3")
        try text.write(to: cached, atomically: true, encoding: .utf8)
        #expect(updater.catalog().release(id: "bridge-dormison-b1-2") == nil)
    }

    @Test("A wrong sha256, an extra file, or an older manifest is refused")
    func integrity() async throws {
        let rig = BridgeRig()
        defer { rig.remove() }
        try rig.engine()
        try rig.bundled()
        let updater = rig.updater
        updater.store.follow(engine: rig.runners.appending(path: "dormison-b1"), catalog: updater.catalog())

        try rig.publishManifest(serial: 5, [try rig.artifact(rev: 2, wrongSha: true)])
        _ = try await updater.check()
        let wrong = try #require(updater.catalog().release(id: "bridge-dormison-b1-2"))
        let sha = await failureMessage { _ = try await updater.install(wrong) }
        #expect(sha.contains("sha256"))

        try rig.publishManifest(serial: 6, [try rig.artifact(rev: 2, extraFile: true)])
        _ = try await updater.check()
        let extra = try #require(updater.catalog().release(id: "bridge-dormison-b1-2"))
        let files = await failureMessage { _ = try await updater.install(extra) }
        #expect(files.contains("extra.dylib"))
        #expect(BridgeStore.installedReleases(in: rig.store).isEmpty)

        // Serial 4 after 6: a replayed older list.
        try rig.publishManifest(serial: 4, [])
        let replay = await failureMessage { _ = try await updater.check() }
        #expect(replay.contains("older than the one NotProton already has"))
        #expect(updater.catalog().remoteSerial == 6)
    }

    @Test("Without a release key only the bundled bridge counts and nothing is fetched")
    func noKey() async throws {
        let rig = BridgeRig()
        defer { rig.remove() }
        try rig.engine()
        try rig.bundled()
        var updater = rig.updater
        updater.feed = ReleaseFeed.setup(url: TestFeed.base, key: "")
        guard case .off(let reason) = updater.feed else {
            Issue.record("an empty key must leave the feed off")
            return
        }
        #expect(reason == ReleaseFeed.noKey)
        guard case .available(let release, nil) = try await updater.check() else {
            Issue.record("the bundled bridge should be offered before anything is active")
            return
        }
        #expect(release.isBundled)
        #expect(rig.feed.transport.fetched.withLock { $0 }.isEmpty)
        _ = try await updater.install(release)
        #expect(updater.active?.id == "bridge-dormison-b1-1")
    }

    @Test("A running game refuses a bridge change")
    func gameRunning() async throws {
        let rig = BridgeRig()
        defer { rig.remove() }
        try rig.engine()
        try rig.bundled()
        let updater = rig.updater
        updater.store.follow(engine: rig.runners.appending(path: "dormison-b1"), catalog: updater.catalog())
        try rig.publishManifest(serial: 1, [try rig.artifact(rev: 2)])
        guard case .available(let offered, _) = try await updater.check() else {
            Issue.record("expected an offer")
            return
        }
        rig.game.value.withLock { $0 = true }
        let message = await failureMessage { _ = try await updater.install(offered) }
        #expect(message.contains(EngineUpdater.gameRunning))
        #expect(rig.liveFile("steam.exe") == BridgeRig.file("steam.exe", rev: 1))
    }

    @Test("Release feed settings: https or file only, assets stay under the feed")
    func feedSettings() throws {
        let key = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        guard case .ready(let feed) = ReleaseFeed.setup(url: "https://github.com/o/r/releases/download", key: key) else {
            Issue.record("expected a feed")
            return
        }
        #expect(feed.bridgeManifestURL.absoluteString
            == "https://github.com/o/r/releases/download/manifest/bridge-manifest.json")
        #expect(feed.allows(URL(string: "https://github.com/o/r/releases/download/bridge-dormison-b1-2/x.tar.xz")!))
        #expect(!feed.allows(URL(string: "https://github.com/o/other/releases/download/x/x.tar.xz")!))
        #expect(!feed.allows(URL(string: "https://github.com/o/r/releases/download/../../other/x")!))
        #expect(!feed.allows(URL(string: "http://github.com/o/r/releases/download/x/x")!))
        if case .ready = ReleaseFeed.setup(url: "ftp://example.test/", key: key) { Issue.record("ftp accepted") }
        if case .ready = ReleaseFeed.setup(url: TestFeed.base, key: "bm90IGEga2V5") { Issue.record("bad key accepted") }
        // The shipped Info.plist carries the placeholder: no key until Phase 6.
        let plist = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Info.plist")
        let info = try #require(NSDictionary(contentsOf: plist.standardizedFileURL) as? [String: Any])
        #expect(info[ReleaseFeed.keyKey] as? String == "")
        #expect((info[ReleaseFeed.urlKey] as? String)?.hasPrefix("https://github.com/") == true)
    }
}
