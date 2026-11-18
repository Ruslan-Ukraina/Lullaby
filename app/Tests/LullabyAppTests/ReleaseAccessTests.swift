import CryptoKit
import Foundation
import Synchronization
import Testing

@testable import LullabyApp

/// Answers GitHub's API from memory and records every request.
final class FakeGitHub: RequestTransport, Sendable {
    let requests = Mutex<[URLRequest]>([])
    let assets: [String: [String: (id: Int, data: Data)]]   // tag -> name -> asset

    init(_ assets: [String: [String: (id: Int, data: Data)]]) { self.assets = assets }

    private func answer(_ request: URLRequest) throws -> Data {
        requests.withLock { $0.append(request) }
        let path = request.url?.path(percentEncoded: false) ?? ""
        if let range = path.range(of: "/releases/tags/") {
            let tag = String(path[range.upperBound...])
            guard let list = assets[tag] else { throw TransportFailure(detail: "404 \(path)") }
            let json = ["assets": list.map { ["id": $0.value.id, "name": $0.key] }]
            return try JSONSerialization.data(withJSONObject: json)
        }
        if let range = path.range(of: "/releases/assets/"), let id = Int(path[range.upperBound...]) {
            for list in assets.values { if let hit = list.values.first(where: { $0.id == id }) { return hit.data } }
        }
        throw TransportFailure(detail: "404 \(path)")
    }

    func fetch(_ request: URLRequest, limit: Int) async throws -> Data { try answer(request) }

    func download(_ request: URLRequest, to part: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let data = try answer(request)
        try data.write(to: part)
        progress(Int64(data.count))
    }
}

@Suite("Private release access")
struct ReleaseAccessTests {

    private static let repo = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    private static let base = URL(string: "https://github.com/owner/lullaby/releases/download/")!
    private static let key = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()

    private func transport(_ github: FakeGitHub) -> GitHubAssetTransport {
        GitHubAssetTransport(base: Self.base, repository: "owner/lullaby", token: "t0ken", client: github)
    }

    @Test("A feed file is read through the API: the release by tag, then the asset as octet-stream, with the token")
    func resolvesThroughAPI() async throws {
        let github = FakeGitHub(["manifest": ["bridge-manifest.json": (id: 42, data: Data("{}".utf8))]])
        let data = try await transport(github).fetch(Self.base.appending(path: "manifest/bridge-manifest.json"), limit: 1024)
        #expect(data == Data("{}".utf8))
        let requests = github.requests.withLock { $0 }
        #expect(requests.count == 2)
        #expect(requests[0].url?.absoluteString == "https://api.github.com/repos/owner/lullaby/releases/tags/manifest")
        #expect(requests[0].value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(requests[1].url?.absoluteString == "https://api.github.com/repos/owner/lullaby/releases/assets/42")
        #expect(requests[1].value(forHTTPHeaderField: "Accept") == "application/octet-stream")
        for request in requests {
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t0ken")
        }
    }

    @Test("A file the release does not have is told as missing, not as a network failure")
    func missingFileIsNotOffline() async throws {
        let github = FakeGitHub(["manifest": ["bridge-manifest.json": (id: 42, data: Data("{}".utf8))]])
        do {
            _ = try await transport(github).fetch(Self.base.appending(path: "manifest/game-fixes.json"), limit: 1024)
            Issue.record("a file that is not in the release was fetched")
        } catch {
            #expect((error as? TransportFailure)?.status == 404)
            #expect(ReleaseAccess.failure(error) == ReleaseAccess.notFound)
            #expect(ReleaseAccess.failure(error) != EngineUpdater.offline)
        }
    }

    @Test("Sparkle gets the appcast's direct address: its own Accept header would make the API answer JSON")
    func appcastDirectAddress() async throws {
        let github = FakeGitHub(["manifest": ["appcast.xml": (id: 9, data: Data("<rss/>".utf8))]])
        let asked = Mutex<[URLRequest]>([])
        let direct = URL(string: "https://release-assets.githubusercontent.com/x/appcast?sig=1")!
        let url = try await transport(github).directURL(tag: "manifest", file: "appcast.xml", locate: { request in
            asked.withLock { $0.append(request) }
            return direct
        })
        #expect(url == direct)
        let request = try #require(asked.withLock { $0.first })
        #expect(request.url?.absoluteString == "https://api.github.com/repos/owner/lullaby/releases/assets/9")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/octet-stream")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t0ken")
    }

    @Test("A download (a bridge) resolves the same way, and one release is looked up once")
    func downloadAndCache() async throws {
        let bytes = Data(repeating: 7, count: 100)
        let github = FakeGitHub(["bridge-dormison-b1-3": [
            "bridge-dormison-b1-3.tar.xz": (id: 7, data: bytes),
            "bridge-dormison-b1-3.tar.xz.sig": (id: 8, data: Data("sig".utf8)),
        ]])
        let reader = transport(github)
        let part = FileManager.default.temporaryDirectory.appending(path: "np-private-\(UUID().uuidString).part")
        defer { try? FileManager.default.removeItem(at: part) }
        let url = Self.base.appending(path: "bridge-dormison-b1-3/bridge-dormison-b1-3.tar.xz")
        try await reader.download(url, to: part) { _ in }
        #expect(try Data(contentsOf: part) == bytes)
        #expect(try await reader.fetch(EngineSignature.signatureURL(for: url), limit: 1024) == Data("sig".utf8))
        let tagLookups = github.requests.withLock { $0.filter { $0.url?.path().contains("/releases/tags/") == true } }
        #expect(tagLookups.count == 1)
    }

    @Test("Addresses outside the feed go out as they are, without the token")
    func passesOthersThrough() async throws {
        let github = FakeGitHub([:])
        let dormison = URL(string: "https://github.com/kageroumado/dormison/releases/download/manifest/engine.json")!
        _ = try? await transport(github).fetch(dormison, limit: 1024)
        let request = try #require(github.requests.withLock { $0.first })
        #expect(request.url == dormison)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(transport(github).asset(of: Self.base.appending(path: "a/b/c")) == nil)
        #expect(transport(github).asset(of: Self.base.appending(path: "../x")) == nil)
    }

    @Test("A file the release does not have is a clear failure")
    func missingAsset() async throws {
        let github = FakeGitHub(["manifest": [:]])
        await #expect(throws: TransportFailure.self) {
            _ = try await transport(github).fetch(Self.base.appending(path: "manifest/appcast.xml"), limit: 1024)
        }
    }

    @Test("A redirect to another host drops the token; the same host keeps it")
    func redirectDropsToken() {
        var original = URLRequest(url: URL(string: "https://api.github.com/repos/o/r/releases/assets/1")!)
        original.setValue("Bearer t", forHTTPHeaderField: "Authorization")
        var storage = URLRequest(url: URL(string: "https://release-assets.githubusercontent.com/x?sig=1")!)
        storage.setValue("Bearer t", forHTTPHeaderField: "Authorization")
        #expect(RedirectPolicy.follow(storage, from: original).value(forHTTPHeaderField: "Authorization") == nil)
        var same = URLRequest(url: URL(string: "https://api.github.com/other")!)
        same.setValue("Bearer t", forHTTPHeaderField: "Authorization")
        #expect(RedirectPolicy.follow(same, from: original).value(forHTTPHeaderField: "Authorization") == "Bearer t")
    }

    @Test("A private feed needs its repository and a token; a public one ignores both")
    func privateSetup() throws {
        let url = Self.base.absoluteString
        if case .off(let reason) = ReleaseFeed.setup(url: url, key: Self.key, access: "private",
                                                     repository: "owner/lullaby", token: nil, manifestTag: nil) {
            #expect(reason == ReleaseAccess.needsToken)
        } else {
            Issue.record("a private feed without a token is ready")
        }
        if case .ready = ReleaseFeed.setup(url: url, key: Self.key, access: "private", repository: "lullaby",
                                           token: "t", manifestTag: nil) { Issue.record("no owner, but ready") }
        if case .ready = ReleaseFeed.setup(url: url, key: Self.key, access: "shared", repository: "o/r",
                                           token: "t", manifestTag: nil) { Issue.record("unknown mode, but ready") }
        guard case .ready(let feed) = ReleaseFeed.setup(url: url, key: Self.key, access: "private",
                                                        repository: "owner/lullaby", token: "t", manifestTag: "feeds")
        else { Issue.record("private feed with a token is off"); return }
        #expect(feed.access == .private(repository: "owner/lullaby", token: "t"))
        #expect(feed.bridgeManifestURL.absoluteString == url + "feeds/bridge-manifest.json")
        #expect(feed.transport(over: MemoryTransport()) is GitHubAssetTransport)
        guard case .ready(let open) = ReleaseFeed.setup(url: url, key: Self.key, access: "public",
                                                        repository: "", token: nil, manifestTag: nil)
        else { Issue.record("public feed is off"); return }
        #expect(open.access == .public)
        #expect(open.transport(over: MemoryTransport()) is MemoryTransport)
    }

    @Test("The engine manifest address is configurable, but only as a GitHub release download over https")
    func engineManifestURL() {
        let other = "https://github.com/someone/dormison-mirror/releases/download/manifest/engine.json"
        #expect(EngineManifest.configuredURL(other).absoluteString == other)
        for bad in [nil, "", "http://github.com/a/b/releases/download/m/engine.json",
                    "https://example.com/a/b/releases/download/m/engine.json",
                    "https://github.com/a/b/raw/engine.json"] {
            #expect(EngineManifest.configuredURL(bad) == EngineManifest.defaultURL)
        }
        #expect(EngineSignature.assetPathPrefix == EngineSignature.defaultAssetPathPrefix)
    }

    @Test("release/feed.json and the checked-in Info.plist name the same feed")
    func configAgreement() throws {
        let config = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: Self.repo.appending(path: "release/feed.json"))) as? [String: Any])
        let plist = try #require(try PropertyListSerialization.propertyList(
            from: Data(contentsOf: Self.repo.appending(path: "app/Info.plist")), format: nil) as? [String: Any])
        let repository = try #require(config["repository"] as? String)
        #expect(plist[ReleaseAccess.repositoryKey] as? String == repository)
        #expect(plist[ReleaseAccess.infoKey] as? String == config["access"] as? String)
        #expect(plist[ReleaseAccess.manifestTagKey] as? String == config["manifestTag"] as? String)
        #expect(plist[EngineManifest.infoKey] as? String == config["engineManifest"] as? String)
        #expect(plist[ReleaseFeed.urlKey] as? String == "https://github.com/\(repository)/releases/download/")
        // r6: the repository is public, so are its releases; no token is needed (RELEASING.md, public/private).
        #expect(config["access"] as? String == "public")
    }
}
