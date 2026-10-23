import Foundation
import CryptoKit
import Testing
@testable import LullabyApp
@testable import LullabySettings

@Suite("Game fix catalog updates")
struct GameFixUpdaterTests {
    struct Rig {
        let feed = TestFeed()
        let root = URL.temporaryDirectory.appending(path: "np-fixes-\(UUID().uuidString)")
        var cache: URL { root.appending(path: "manifests") }
        var settings: URL { root.appending(path: "settings") }
        init() throws { try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true) }

        func catalog(serial: Int, entries: String = GameFixUpdaterTests.entry) -> Data {
            Data(#"{"schema":1,"serial":\#(serial),"entries":[\#(entries)]}"#.utf8)
        }
        func publish(_ data: Data, signer: Curve25519Signer? = nil) throws {
            try feed.publish(feed.feed.gameFixesURL, data, signer: signer)
        }
        func refresh() async throws -> GameFixUpdater.Outcome {
            try await GameFixUpdater.refresh(feed: feed.feed, transport: feed.transport, cache: cache, settings: settings)
        }
        var installed: Data? { try? Data(contentsOf: settings.appending(path: "game-fixes.json")) }
    }
    typealias Curve25519Signer = Curve25519.Signing.PrivateKey

    static let entry = """
    {"id":"peak","name":"PEAK","match":{"appIDs":[3527290]},"verdict":"fits","backend":"dxmt","verifiedOn":"r6",
     "source":{"kind":"lullaby","ref":"","license":"GPL-3.0"}}
    """

    @Test("A signed catalog is stored for the settings; the same one again changes nothing")
    func updates() async throws {
        let r = try Rig()
        try r.publish(r.catalog(serial: 1))
        #expect(try await r.refresh() == .updated(serial: 1, entries: 1))
        #expect(r.installed == r.catalog(serial: 1))
        #expect(try await r.refresh() == .unchanged(serial: 1))
        let store = SettingsStore(root: r.settings)
        #expect(store.stack(for: 3527290).value(\.renderer) == (.dxmt, .recipe))
    }

    @Test("A catalog signed by another key, or one that is not usable, is refused and the old one stays")
    func refusals() async throws {
        let r = try Rig()
        try r.publish(r.catalog(serial: 1))
        _ = try await r.refresh()
        try r.publish(r.catalog(serial: 2), signer: Curve25519Signer())
        await #expect(throws: StepFailure.self) { try await r.refresh() }
        try r.publish(r.catalog(serial: 3, entries: #"{"id":"x","name":"X","match":{"appIDs":[1]},"verdict":"fits","env":{"DYLD_INSERT_LIBRARIES":"x"},"source":{"kind":"lullaby","ref":"","license":""}}"#))
        await #expect(throws: StepFailure.self) { try await r.refresh() }
        #expect(r.installed == r.catalog(serial: 1))
    }

    @Test("An older signed catalog (replayed by a mirror) and a missing network leave the catalog alone")
    func oldAndOffline() async throws {
        let r = try Rig()
        try r.publish(r.catalog(serial: 5))
        _ = try await r.refresh()
        try r.publish(r.catalog(serial: 4))
        await #expect(throws: StepFailure.self) { try await r.refresh() }
        r.feed.transport.offline.withLock { $0 = true }
        await #expect(throws: StepFailure.self) { try await r.refresh() }
        #expect(r.installed == r.catalog(serial: 5))
    }
}
