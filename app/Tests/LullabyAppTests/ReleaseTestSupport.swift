import CryptoKit
import Foundation
import Synchronization
import Testing

@testable import LullabyApp

/// Serves files from memory, can go offline. Downloads write the whole file.
final class MemoryTransport: EngineTransport, Sendable {
    let files = Mutex<[URL: Data]>([:])
    let offline = Mutex(false)
    let fetched = Mutex<[URL]>([])

    func put(_ url: URL, _ data: Data) { files.withLock { $0[url] = data } }

    func fetch(_ url: URL, limit: Int) async throws -> Data {
        if offline.withLock({ $0 }) { throw URLError(.notConnectedToInternet) }
        fetched.withLock { $0.append(url) }
        guard let data = files.withLock({ $0[url] }) else { throw TransportFailure(detail: "404 \(url)") }
        return data
    }

    func download(_ url: URL, to part: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        if offline.withLock({ $0 }) { throw URLError(.notConnectedToInternet) }
        guard let data = files.withLock({ $0[url] }) else { throw TransportFailure(detail: "404 \(url)") }
        try data.write(to: part)
        progress(Int64(data.count))
    }
}

final class TestFlag: Sendable {
    let value = Mutex(false)
}

/// A test release feed: a throwaway key (never the release key) and its signer.
struct TestFeed {
    static let base = "https://example.test/np/releases/download/"
    let key = Curve25519.Signing.PrivateKey()
    let transport = MemoryTransport()

    var setup: ReleaseFeed.Setup { ReleaseFeed.setup(url: Self.base, key: key.publicKey.rawRepresentation.base64EncodedString()) }
    var feed: ReleaseFeed {
        guard case .ready(let feed) = setup else { fatalError("test feed did not configure") }
        return feed
    }

    func sign(_ data: Data, with other: Curve25519.Signing.PrivateKey? = nil) throws -> Data {
        Data(try (other ?? key).signature(for: data).base64EncodedString().utf8)
    }

    /// Puts a file and its .sig on the feed.
    func publish(_ url: URL, _ data: Data, signer: Curve25519.Signing.PrivateKey? = nil) throws {
        transport.put(url, data)
        transport.put(EngineSignature.signatureURL(for: url), try sign(data, with: signer))
    }

    func publishJSON(_ url: URL, _ object: [String: Any], signer: Curve25519.Signing.PrivateKey? = nil) throws {
        try publish(url, try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), signer: signer)
    }
}

/// A notproton tree in a temporary folder: an engine, the app's bundled bridge, and
/// the folders the bridge store writes.
struct BridgeRig {
    static let commit = "52c2a4b918d6ec5f469ed4e5f58777598c9378ff"
    let root = URL.temporaryDirectory.appending(path: "np-bridge-\(UUID().uuidString)")
    let feed = TestFeed()
    let game = TestFlag()

    var runners: URL { root.appending(path: "runners") }
    var payload: URL { root.appending(path: "payload") }
    var live: URL { root.appending(path: "bridge") }
    var store: URL { root.appending(path: "bridges") }
    var manifests: URL { root.appending(path: "manifests") }

    static func clean(_ arch: String, _ version: String) -> Data { Data("clean \(arch) ntdll of \(version)".utf8) }
    static func b1(_ arch: String, _ version: String, rev: Int) -> Data {
        Data("B1 rev \(rev) \(arch) ntdll of \(version): exports lead to lsteamclient".utf8)
    }
    static func file(_ name: String, rev: Int) -> Data { Data("\(name) of bridge revision \(rev)".utf8) }
    static let fixPath = "wine/lib/wine/x86_64-unix/winemac.so"
    static func cleanFix(_ version: String) -> Data { Data("release winemac.so of \(version)".utf8) }
    static func fixed(_ version: String, rev: Int) -> Data { Data("fixed winemac.so rev \(rev) of \(version)".utf8) }

    func remove() { try? FileManager.default.removeItem(at: root) }

    /// runners/<version> with engine-info.json and the release's ntdll pair, made current.
    func engine(_ version: String = "dormison-b1", commit: String = commit) throws {
        let fm = FileManager.default
        let dir = runners.appending(path: version)
        for arch in ["x86_64", "i386"] {
            let url = dir.appending(path: "wine/lib/wine/\(arch)-windows/ntdll.dll")
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.clean(arch, version).write(to: url)
        }
        let fix = dir.appending(path: Self.fixPath)
        try fm.createDirectory(at: fix.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.cleanFix(version).write(to: fix)
        try JSONSerialization.data(withJSONObject: ["version": version, "commit": commit])
            .write(to: dir.appending(path: "engine-info.json"))
        try EngineStore.pointLink(EngineStore.currentLink, at: version, in: runners)
    }

    func ntdllEntries(_ version: String, rev: Int, file: (String) -> String) -> [[String: String]] {
        ["x86_64", "i386"].map { arch in
            [
                "arch": arch, "path": "wine/lib/wine/\(arch)-windows/ntdll.dll", "file": file(arch),
                "clean": Digest.sha256(of: Self.clean(arch, version)),
                "b1": Digest.sha256(of: Self.b1(arch, version, rev: rev)),
            ]
        }
    }

    /// The app's own bridge: revision 1 for `version`, files under payload/.
    func bundled(_ version: String = "dormison-b1", commit: String = commit) throws {
        let fm = FileManager.default
        for entry in BridgePayload.entries {
            let url = payload.appending(path: "bridge/\(entry.resource)")
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.file(entry.resource, rev: 1).write(to: url)
        }
        for arch in ["x86_64", "i386"] {
            let url = payload.appending(path: "engine-support/\(version)/\(arch)-ntdll.dll")
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.b1(arch, version, rev: 1).write(to: url)
        }
        let manifest: [String: Any] = [
            "schema": 1, "serial": 1,
            "bridges": [[
                "id": "bridge-\(version)-1", "engine": version, "engineCommit": commit, "rev": 1,
                "files": BridgePayload.entries.map { ["name": $0.resource, "path": "bridge/\($0.resource)"] },
                "ntdll": ntdllEntries(version, rev: 1) { "engine-support/\(version)/\($0)-ntdll.dll" },
            ]],
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: payload.appending(path: "engine-support/bridge-manifest.json"))
    }

    /// A downloadable revision on the test feed. Returns its manifest entry.
    func artifact(
        _ version: String = "dormison-b1", rev: Int, commit: String = commit,
        signer: Curve25519.Signing.PrivateKey? = nil, wrongSha: Bool = false, extraFile: Bool = false,
        engineFix: Bool = false
    ) throws -> [String: Any] {
        let fm = FileManager.default
        let id = "bridge-\(version)-\(rev)"
        let work = root.appending(path: "work-\(UUID().uuidString)")
        let top = work.appending(path: id)
        try fm.createDirectory(at: top.appending(path: "ntdll"), withIntermediateDirectories: true)
        var files: [[String: String]] = []
        for entry in BridgePayload.entries {
            let data = Self.file(entry.resource, rev: rev)
            try data.write(to: top.appending(path: entry.resource))
            files.append(["name": entry.resource, "path": entry.resource, "sha256": Digest.sha256(of: data)])
        }
        for arch in ["x86_64", "i386"] {
            try Self.b1(arch, version, rev: rev).write(to: top.appending(path: "ntdll/\(arch)-ntdll.dll"))
        }
        if extraFile { try Data("surprise".utf8).write(to: top.appending(path: "extra.dylib")) }
        if engineFix {
            try fm.createDirectory(at: top.appending(path: "engine"), withIntermediateDirectories: true)
            try Self.fixed(version, rev: rev).write(to: top.appending(path: "engine/winemac.so"))
        }
        let tarball = work.appending(path: "\(id).tar.xz")
        try Shell.check("/usr/bin/tar", [
            "-cJf", tarball.path(percentEncoded: false), "-C", work.path(percentEncoded: false), id,
        ])
        let bytes = try Data(contentsOf: tarball)
        let url = feed.feed.asset(id, "\(id).tar.xz")
        try feed.publish(url, bytes, signer: signer)
        var entry: [String: Any] = [
            "id": id, "engine": version, "engineCommit": commit, "rev": rev, "files": files,
            "ntdll": ntdllEntries(version, rev: rev) { "ntdll/\($0)-ntdll.dll" },
            "url": url.absoluteString,
            "sha256": wrongSha ? Digest.sha256(of: Data("other".utf8)) : Digest.sha256(of: bytes),
            "sizeBytes": bytes.count,
        ]
        if engineFix {
            entry["engineFiles"] = [[
                "path": Self.fixPath, "file": "engine/winemac.so",
                "clean": Digest.sha256(of: Self.cleanFix(version)), "patched": Digest.sha256(of: Self.fixed(version, rev: rev)),
            ]]
        }
        return entry
    }

    func publishManifest(serial: Int, _ entries: [[String: Any]], signer: Curve25519.Signing.PrivateKey? = nil) throws {
        try feed.publishJSON(feed.feed.bridgeManifestURL, ["schema": 1, "serial": serial, "bridges": entries], signer: signer)
    }

    var updater: BridgeUpdater {
        let game = game
        return BridgeUpdater(
            store: BridgeStore(store: store, live: live, downloads: root.appending(path: "cache")),
            runners: runners, manifests: manifests, feed: feed.setup, transport: feed.transport,
            bundledRoot: payload, gameIsRunning: { game.value.withLock { $0 } })
    }

    func liveFile(_ name: String) -> Data? {
        try? Data(contentsOf: live.appending(path: name))
    }

    func engineFile(_ path: String, _ version: String = "dormison-b1") -> Data? {
        try? Data(contentsOf: runners.appending(path: "\(version)/\(path)"))
    }

    func engineNtdll(_ arch: String, _ version: String = "dormison-b1") -> Data? {
        try? Data(contentsOf: runners.appending(path: "\(version)/wine/lib/wine/\(arch)-windows/ntdll.dll"))
    }
}

func failureMessage(_ body: () async throws -> Void) async -> String {
    do {
        try await body()
        Issue.record("expected a failure")
        return ""
    } catch {
        return error.localizedDescription
    }
}
