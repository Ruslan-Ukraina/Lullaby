import CryptoKit
import Foundation
import Testing

@testable import LullabyApp

/// A Steam folder, a notproton folder and a test feed in a temporary directory.
private struct GateRig {
    let root = URL.temporaryDirectory.appending(path: "np-gate-\(UUID().uuidString)")
    let feed = TestFeed()

    var package: URL { root.appending(path: "Steam/package") }
    var cfg: URL { root.appending(path: "Steam/steam.cfg") }
    var innerCfg: URL { root.appending(path: "Steam/inner/steam.cfg") }
    var signatures: URL { root.appending(path: "notproton/signatures/macos.arm64") }
    var manifests: URL { root.appending(path: "notproton/manifests") }
    var gateFile: URL { root.appending(path: "notproton/steam-update-gate") }
    var payload: URL { root.appending(path: "payload") }

    init() throws {
        let fm = FileManager.default
        for dir in [package, innerCfg.deletingLastPathComponent(), signatures, manifests, payload.appending(path: "signatures")] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    static func database(_ build: UInt64, note: String = "") -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "schema_version": 3, "profile_version": 1, "arch": "arm64", "platform": "macos",
            "steam_build": build, "steam_build_date": note,
            "signatures": [["name": "CCompatManager::Init", "aob_hex": "FF"]],
        ] as [String: Any], options: [.sortedKeys])
    }

    /// What Steam installed: a package manifest with `build`, newest of its folder.
    func installedSteam(_ build: UInt64, name: String = "steam_client_signed-2_osx.manifest", age: TimeInterval = 0) throws {
        let url = package.appending(path: name)
        try "\"osx\"\n{\n\t\"version\"\t\t\"\(build)\"\n\t\"ostype\"\t\t\"macos1015\"\n}\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -age)], ofItemAtPath: url.path(percentEncoded: false))
    }

    /// What Valve offers.
    func valveOffers(_ build: UInt64, beta: String? = nil) {
        feed.transport.put(
            SteamBuild.manifestURL(beta: beta),
            Data("\"osx\"\n{\n\t\"version\"\t\t\"\(build)\"\n}\n".utf8))
    }

    /// The app's own list: database 1790904859 fits builds 1788652215 and 1790904859.
    func bundled() throws {
        let data = Self.database(1790904859)
        try data.write(to: signatures.appending(path: "1790904859.json"))
        let manifest: [String: Any] = [
            "schema": 1, "serial": 1,
            "databases": [["file": "1790904859.json", "sha256": Digest.sha256(of: data)]],
            "builds": [
                ["build": 1788652215, "database": "1790904859.json"],
                ["build": 1790904859, "database": "1790904859.json"],
            ],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: payload.appending(path: "signatures/manifest.json"))
    }

    /// signatures-manifest.json on the feed naming `builds` for `database`.
    func publishSignatures(
        serial: Int, database build: UInt64, builds: [UInt64], served: Data? = nil,
        signer: Curve25519.Signing.PrivateKey? = nil
    ) throws {
        let data = Self.database(build)
        let url = feed.feed.asset("signatures", "\(build).json")
        feed.transport.put(url, served ?? data)
        try feed.publishJSON(feed.feed.signaturesManifestURL, [
            "schema": 1, "serial": serial,
            "databases": [["file": "\(build).json", "sha256": Digest.sha256(of: data), "url": url.absoluteString]],
            "builds": builds.map { ["build": $0, "database": "\(build).json"] },
        ], signer: signer)
    }

    var signatureUpdater: SignatureUpdater {
        SignatureUpdater(
            signatures: signatures, manifests: manifests, feed: feed.setup, transport: feed.transport,
            bundledRoot: payload)
    }

    var gate: SteamUpdateGate {
        let updater = signatureUpdater
        return SteamUpdateGate(
            file: gateFile, blockPaths: [cfg, innerCfg], package: package, signatures: signatures,
            transport: feed.transport, support: { updater.support() })
    }

    var blocked: Bool { UpdateBlock.isPresent(at: [cfg, innerCfg]) }
}

@Suite("Steam signatures and update gate", .serialized)
struct SteamGateTests {

    @Test("The rule: manual always blocks; a build without signatures waits; one with them may update")
    func rule() {
        let supported: Set<UInt64> = [100, 200]
        func decide(_ mode: SteamGateMode, _ installed: UInt64?, _ offered: UInt64?) -> SteamGateDecision {
            SteamUpdateGate.decide(mode: mode, installed: installed, offered: offered, supported: supported.contains)
        }
        #expect(decide(.manual, 100, 200) == .init(block: true, state: .manual(installed: 100)))
        #expect(decide(.auto, 100, 100) == .init(block: true, state: .current(build: 100, supported: true)))
        #expect(decide(.auto, 150, 150) == .init(block: true, state: .current(build: 150, supported: false)))
        #expect(decide(.auto, 100, 200) == .init(block: false, state: .updateAllowed(from: 100, to: 200)))
        #expect(decide(.auto, 100, 300) == .init(block: true, state: .waiting(offered: 300, installed: 100)))
        #expect(decide(.auto, nil, 200) == .init(block: false, state: .updateAllowed(from: nil, to: 200)))
        if case .unknown = decide(.auto, 100, nil).state {} else { Issue.record("offline must be unknown") }
        #expect(decide(.auto, 100, nil).block)
    }

    @Test("Steam's builds: the newest package manifest, Valve's manifest per beta")
    func builds() throws {
        let rig = try GateRig()
        defer { rig.remove() }
        #expect(SteamBuild.installed(package: rig.package) == nil)
        try rig.installedSteam(1773099986, name: "steam_client_signed_osx.manifest", age: 3600 * 24 * 200)
        try rig.installedSteam(1788652215)
        #expect(SteamBuild.installed(package: rig.package) == 1788652215)
        #expect(SteamBuild.version(in: "\"osx\"\n{\n\t\"version\"\t\t\"1791249696\"\n") == 1791249696)
        #expect(SteamBuild.version(in: "no version here") == nil)
        #expect(SteamBuild.manifestURL(beta: nil).absoluteString
            == "https://client-update.akamai.steamstatic.com/steam_client_osx")
        #expect(SteamBuild.manifestURL(beta: "publicbeta").absoluteString
            == "https://client-update.akamai.steamstatic.com/steam_client_publicbeta_osx")
        #expect(SteamBuild.beta(package: rig.package) == nil)
        try "publicbeta\n".write(to: rig.package.appending(path: "beta"), atomically: true, encoding: .utf8)
        #expect(SteamBuild.beta(package: rig.package) == "publicbeta")
        try "../../x".write(to: rig.package.appending(path: "beta"), atomically: true, encoding: .utf8)
        #expect(SteamBuild.beta(package: rig.package) == nil)
    }

    @Test("A Steam build without signatures: the block goes in and Status waits for support")
    func buildWithoutSignatures() async throws {
        let rig = try GateRig()
        defer { rig.remove() }
        try rig.bundled()
        try rig.installedSteam(1788652215)
        rig.valveOffers(1791249696)
        #expect(!rig.blocked)

        let decision = await rig.gate.evaluate()
        #expect(decision == .init(block: true, state: .waiting(offered: 1791249696, installed: 1788652215)))
        #expect(rig.blocked)
        #expect(try String(contentsOf: rig.gateFile, encoding: .utf8) == "auto\n")
        #expect(SystemStatus.gateSentence(decision.state) == "Steam 1791249696 is out. Waiting for NotProton support.")
    }

    @Test("Signatures appear: the database is downloaded and the block lifts on its own, then comes back")
    func signaturesAppear() async throws {
        let rig = try GateRig()
        defer { rig.remove() }
        try rig.bundled()
        try rig.installedSteam(1788652215)
        rig.valveOffers(1791249696)
        try rig.publishSignatures(serial: 1, database: 1790904859, builds: [1788652215])
        _ = try await rig.signatureUpdater.update()
        #expect(await rig.gate.evaluate().block)

        // The feed now lists the new build with its own database.
        try rig.publishSignatures(serial: 2, database: 1791249696, builds: [1791249696])
        let outcome = try await rig.signatureUpdater.update()
        #expect(outcome.installed == ["1791249696.json"])
        #expect(outcome.supportedBuilds.contains(1791249696))
        #expect(try Data(contentsOf: rig.signatures.appending(path: "1791249696.json")) == GateRig.database(1791249696))
        let lifted = await rig.gate.evaluate()
        #expect(lifted == .init(block: false, state: .updateAllowed(from: 1788652215, to: 1791249696)))
        #expect(!rig.blocked)

        // Steam updated: the next evaluation holds the block again for the build after.
        try rig.installedSteam(1791249696, name: "steam_client_signed-3_osx.manifest")
        let current = await rig.gate.evaluate()
        #expect(current == .init(block: true, state: .current(build: 1791249696, supported: true)))
        #expect(rig.blocked)
    }

    @Test("Manual block holds whatever Valve offers; turning it off hands over to the gate")
    func manual() async throws {
        let rig = try GateRig()
        defer { rig.remove() }
        try rig.bundled()
        try rig.installedSteam(1788652215)
        rig.valveOffers(1790904859)

        // A block from before Phase 5 is the person's own choice.
        try UpdateBlock.write(to: [rig.cfg, rig.innerCfg])
        #expect(rig.gate.mode == .manual)
        #expect(await rig.gate.evaluate().state == .manual(installed: 1788652215))
        #expect(rig.blocked)
        #expect(rig.feed.transport.fetched.withLock { $0 }.isEmpty)

        try rig.gate.setMode(.auto)
        let auto = await rig.gate.evaluate()
        #expect(auto == .init(block: false, state: .updateAllowed(from: 1788652215, to: 1790904859)))
        #expect(!rig.blocked)

        try rig.gate.setMode(.manual)
        #expect(await rig.gate.evaluate().block)
        #expect(rig.blocked)
        // Without any block and without the file, the gate starts automatic.
        try FileManager.default.removeItem(at: rig.gateFile)
        try UpdateBlock.remove(from: [rig.cfg, rig.innerCfg])
        #expect(rig.gate.mode == .auto)
    }

    @Test("No network: Valve's version unknown, the block holds")
    func offline() async throws {
        let rig = try GateRig()
        defer { rig.remove() }
        try rig.bundled()
        try rig.installedSteam(1788652215)
        rig.feed.transport.offline.withLock { $0 = true }
        let decision = await rig.gate.evaluate()
        #expect(decision.block)
        guard case .unknown(1788652215, _) = decision.state else {
            Issue.record("expected unknown")
            return
        }
        #expect(rig.blocked)
        let message = await failureMessage { _ = try await rig.signatureUpdater.update() }
        #expect(message.contains("could not reach GitHub"))
    }

    @Test("Fake signature, wrong digest or an unreadable database: refused, nothing written")
    func refusals() async throws {
        let rig = try GateRig()
        defer { rig.remove() }
        try rig.bundled()
        try rig.publishSignatures(serial: 1, database: 1791249696, builds: [1791249696], signer: Curve25519.Signing.PrivateKey())
        let fake = await failureMessage { _ = try await rig.signatureUpdater.update() }
        #expect(fake.contains("does not carry NotProton's release signature"))

        try rig.publishSignatures(serial: 1, database: 1791249696, builds: [1791249696], served: GateRig.database(1791249696, note: "x"))
        let sha = await failureMessage { _ = try await rig.signatureUpdater.update() }
        #expect(sha.contains("does not match NotProton's signed list"))
        #expect(!FileManager.default.fileExists(atPath: rig.signatures.appending(path: "1791249696.json").path(percentEncoded: false)))
        #expect(!rig.signatureUpdater.support().supports(1791249696, installedIn: rig.signatures))

        // Signed and matching, but not a database notproton.dylib can load.
        let junk = Data("{\"schema_version\":2}".utf8)
        let url = rig.feed.feed.asset("signatures", "1791249696.json")
        rig.feed.transport.put(url, junk)
        try rig.feed.publishJSON(rig.feed.feed.signaturesManifestURL, [
            "schema": 1, "serial": 2,
            "databases": [["file": "1791249696.json", "sha256": Digest.sha256(of: junk), "url": url.absoluteString]],
            "builds": [["build": 1791249696, "database": "1791249696.json"]],
        ])
        let unusable = await failureMessage { _ = try await rig.signatureUpdater.update() }
        #expect(unusable.contains("not one notproton.dylib can read"))

        #expect(SignatureSupport.isUsableDatabase(GateRig.database(1791249696), file: "1791249696.json"))
        #expect(!SignatureSupport.isUsableDatabase(GateRig.database(1791249696), file: "1791249697.json"))
    }

    @Test("A database the feed revised is accepted as current next to the app's own copy")
    func accepted() throws {
        let rig = try GateRig()
        defer { rig.remove() }
        try rig.bundled()
        var support = rig.signatureUpdater.support()
        let bundledSha = Digest.sha256(of: GateRig.database(1790904859))
        #expect(support.accepted("1790904859.json") == [bundledSha])
        support.merge(SignatureSupport.parse([
            "databases": [["file": "1790904859.json", "sha256": String(repeating: "a", count: 64),
                           "url": rig.feed.feed.asset("signatures", "1790904859.json").absoluteString]],
            "builds": [["build": "1791249696", "database": "1790904859.json"]],
        ], feed: rig.feed.feed))
        #expect(support.accepted("1790904859.json") == [bundledSha, String(repeating: "a", count: 64)])
        #expect(support.builds[1791249696] == "1790904859.json")
        #expect(support.supportedBuilds(installedIn: rig.signatures) == [1788652215, 1790904859, 1791249696])
    }

    @Test("The shipped signature list matches signatures/macos.arm64 and lists the build checked live")
    func shippedList() throws {
        let repo = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../..").standardizedFileURL
        let data = try Data(contentsOf: repo.appending(path: "signatures/manifest.json"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let support = SignatureSupport.parse(json, feed: nil)
        let dir = repo.appending(path: "signatures/macos.arm64")
        #expect(support.supports(1788652215, installedIn: dir))
        for database in support.databases {
            #expect(Digest.sha256IfPresent(dir.appending(path: database.file)) == database.sha256)
            #expect(SignatureSupport.isUsableDatabase(try Data(contentsOf: dir.appending(path: database.file)), file: database.file))
        }
    }
}
