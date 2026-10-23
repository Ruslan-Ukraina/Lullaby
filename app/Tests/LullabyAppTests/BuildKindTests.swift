import CryptoKit
import Foundation
import Testing

@testable import LullabyApp

@Suite("Release builds and TEST keys")
struct BuildKindTests {

    private static let repo = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// release/testkeys.swift's derivation, so a changed phrase cannot slip past the list.
    private static func testKey(_ name: String) throws -> String {
        let phrase = "NotProton TEST \(name) key. Public on purpose; release builds refuse it."
        let seed = Data(SHA256.hash(data: Data(phrase.utf8)))
        return try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
            .publicKey.rawRepresentation.base64EncodedString()
    }

    private static let ownerKey = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
    private static let feed = "https://github.com/Ruslan-Ukraina/Lullaby/releases/download/"
    private static let appcast = feed + "manifest/appcast.xml"

    @Test("test-public-keys.txt, TestKeys and testkeys.swift name the same keys")
    func agreement() throws {
        let text = try String(contentsOf: Self.repo.appending(path: "release/test-public-keys.txt"), encoding: .utf8)
        let listed = Set(text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") })
        #expect(listed == TestKeys.publicKeys)
        #expect(TestKeys.isTestKey(try Self.testKey("release")))
        #expect(TestKeys.isTestKey(try Self.testKey("sparkle")))
        let script = try String(contentsOf: Self.repo.appending(path: "release/testkeys.swift"), encoding: .utf8)
        #expect(script.contains(#""NotProton TEST \(arguments[0]) key. Public on purpose; release builds refuse it.""#))
    }

    @Test("A release build refuses a TEST release key; a test or dev build takes it")
    func releaseFeedRefusesTestKey() throws {
        for key in [try Self.testKey("release"), try Self.testKey("sparkle"), "dXwoMYHG7v/BEEHtb/ifHpQrAz397JPWlea0Np7rVWk="] {
            guard case .off(let reason) = ReleaseFeed.setup(url: Self.feed, key: key, kind: .release) else {
                Issue.record("release build took TEST key \(key)")
                continue
            }
            #expect(reason == TestKeys.refused)
            if case .off = ReleaseFeed.setup(url: Self.feed, key: key, kind: .test) { Issue.record("test build refused \(key)") }
            if case .off = ReleaseFeed.setup(url: Self.feed, key: key, kind: .dev) { Issue.record("dev build refused \(key)") }
        }
        guard case .ready = ReleaseFeed.setup(url: Self.feed, key: Self.ownerKey, kind: .release) else {
            Issue.record("release build refused the owner's key")
            return
        }
    }

    @Test("A release build reads its feed over https only")
    func releaseFeedHttpsOnly() {
        if case .ready = ReleaseFeed.setup(url: "file:///tmp/feed/", key: Self.ownerKey, kind: .release) {
            Issue.record("release build took a file:// feed")
        }
        if case .off = ReleaseFeed.setup(url: "file:///tmp/feed/", key: Self.ownerKey, kind: .test) {
            Issue.record("test build refused a file:// feed")
        }
    }

    @Test("Sparkle stays off in a release build with a TEST key, without a key, or over http")
    func updaterSetup() throws {
        let sparkleTest = try Self.testKey("sparkle")
        #expect(AppUpdater.setup(feed: Self.appcast, key: sparkleTest, kind: .release) == .off(TestKeys.refused))
        #expect(AppUpdater.setup(feed: Self.appcast, key: Self.ownerKey, kind: .release) == .ready)
        #expect(AppUpdater.setup(feed: Self.appcast, key: sparkleTest, kind: .test) == .ready)
        #expect(AppUpdater.setup(feed: "http://127.0.0.1:8000/appcast.xml", key: sparkleTest, kind: .test) == .ready)
        if case .ready = AppUpdater.setup(feed: "http://example.test/appcast.xml", key: Self.ownerKey, kind: .release) {
            Issue.record("release build took an http appcast")
        }
        if case .ready = AppUpdater.setup(feed: "", key: Self.ownerKey, kind: .release) { Issue.record("no feed, but on") }
        if case .ready = AppUpdater.setup(feed: Self.appcast, key: "", kind: .release) { Issue.record("no key, but on") }
        if case .ready = AppUpdater.setup(feed: Self.appcast, key: "bm90IGEga2V5", kind: .dev) { Issue.record("bad key, but on") }
    }

    @Test("The checked-in Info.plist is a dev build with Sparkle off and a signed appcast required")
    func infoPlistDefaults() throws {
        let data = try Data(contentsOf: Self.repo.appending(path: "app/Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist[BuildKind.infoKey] as? String == BuildKind.dev.rawValue)
        #expect(plist[AppUpdater.feedKey] as? String == "")
        #expect(plist[AppUpdater.keyKey] as? String == "")
        #expect(plist[ReleaseFeed.keyKey] as? String == "")
        #expect(plist["SUEnableAutomaticChecks"] as? Bool == false)
        #expect(plist["SURequireSignedFeed"] as? Bool == true)
        #expect(plist["SUVerifyUpdateBeforeExtraction"] as? Bool == true)
    }

    @Test("Native Steam windows stay off by default")
    func nativeWindowsOff() throws {
        let missing = FileManager.default.temporaryDirectory.appending(path: "np-no-such-\(UUID().uuidString)")
        #expect(SteamWindows.mode(at: missing) == SteamWindows.off)
        #expect(!SteamWindows.isOn(at: missing))
        #expect(!SteamWindows.isRegularApp(at: missing))
    }
}
