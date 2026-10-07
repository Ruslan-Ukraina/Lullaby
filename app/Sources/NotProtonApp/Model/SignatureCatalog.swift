// Signature databases for the Steam client and the Steam builds they are known to
// fit (Phase 5, DECISIONS P5-3). notproton.dylib reads the databases from
// notproton/signatures/macos.arm64 when Steam starts, newest first, and keeps the
// first one whose signatures all resolve (dylib/core/loader.c), so a database for
// a newer Steam never breaks the build that is installed.
//
// signatures-manifest.json, signed with the release key (ReleaseFeed):
//
//   { "schema": 1, "serial": 4,
//     "databases": [ { "file": "1790904859.json", "sha256": "…",
//                      "url": "<feed>/signatures/1790904859.json" } ],
//     "builds": [ { "build": 1788652215, "database": "1790904859.json" } ] }
//
// A build is listed once its database resolved every signature against that very
// Steam client (make anchorcheck, CI in Phase 6). The app carries the same file
// without urls (signatures/manifest.json in the repository). Steam may update to
// a build only when it is listed and its database is on disk (SteamUpdateGate).

import Foundation

struct SignatureDatabase: Sendable, Equatable {
    let file: String
    let sha256: String
    /// Where the feed serves it; nil for a database the app carries.
    let url: URL?
}

struct SignatureSupport: Sendable, Equatable {
    static let manifestName = "signatures-manifest.json"
    static let bundledName = "manifest.json"
    static let schema = 1
    static let step = "Update Steam signatures"

    var databases: [SignatureDatabase] = []
    /// Steam build → the database known to fit it.
    var builds: [UInt64: String] = [:]
    var remoteSerial: Int?

    static func isDatabaseName(_ name: String) -> Bool {
        name.wholeMatch(of: /[1-9][0-9]{0,19}\.json/) != nil
    }

    static func build(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value > 0 ? number.uint64Value : nil }
        if let text = value as? String, let number = UInt64(text), number > 0 { return number }
        return nil
    }

    /// `feed`: the manifest came from the feed, so every database needs a url in it.
    static func parse(_ json: [String: Any], feed: ReleaseFeed?) -> SignatureSupport {
        var out = SignatureSupport()
        for item in json["databases"] as? [[String: Any]] ?? [] {
            guard let file = item["file"] as? String, isDatabaseName(file),
                  let sha = (item["sha256"] as? String)?.lowercased(), EngineManifest.isSHA256(sha)
            else {
                AppLog.note("signatures: a database entry is unusable")
                continue
            }
            var url: URL?
            if let feed {
                guard let text = item["url"] as? String, let parsed = URL(string: text), feed.allows(parsed),
                      parsed.lastPathComponent == file
                else {
                    AppLog.note("signatures: \(file) is not served from NotProton's releases")
                    continue
                }
                url = parsed
            }
            out.databases.append(SignatureDatabase(file: file, sha256: sha, url: url))
        }
        let known = Set(out.databases.map(\.file))
        for item in json["builds"] as? [[String: Any]] ?? [] {
            guard let build = build(item["build"]), let database = item["database"] as? String,
                  known.contains(database)
            else { continue }
            out.builds[build] = database
        }
        return out
    }

    /// The app's own list: <payload>/signatures/manifest.json.
    static func bundled(root: URL) -> SignatureSupport {
        guard let data = try? Data(contentsOf: root.appending(path: "signatures/\(bundledName)")),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["schema"] as? Int == schema
        else { return SignatureSupport() }
        return parse(json, feed: nil)
    }

    /// Bundled and the cached signed manifest together; the feed's entry wins for one file.
    static func load(bundledRoot: URL?, feed: ReleaseFeed.Setup, manifests: URL) -> SignatureSupport {
        var out = bundledRoot.map(bundled(root:)) ?? SignatureSupport()
        if case .ready(let feed) = feed,
           let document = SignedDocument.cached(manifestName, in: manifests, key: feed.key, schema: schema)
        {
            out.merge(parse(document.json, feed: feed))
            out.remoteSerial = document.serial
        }
        return out
    }

    mutating func merge(_ other: SignatureSupport) {
        for database in other.databases {
            databases.removeAll { $0.file == database.file && $0.sha256 == database.sha256 }
            databases.append(database)
        }
        builds.merge(other.builds) { _, new in new }
    }

    /// Digests a database file may have: what the app carries and what the feed names.
    func accepted(_ file: String) -> Set<String> {
        Set(databases.filter { $0.file == file }.map(\.sha256))
    }

    /// A listed build whose database is on disk with an accepted digest.
    func supports(_ build: UInt64, installedIn directory: URL) -> Bool {
        guard let file = builds[build], let sha = Digest.sha256IfPresent(directory.appending(path: file)) else {
            return false
        }
        return accepted(file).contains(sha)
    }

    func supportedBuilds(installedIn directory: URL) -> [UInt64] {
        builds.keys.filter { supports($0, installedIn: directory) }.sorted()
    }

    /// The parts of a database notproton.dylib needs to load it (resolver/sigdb.c).
    static func isUsableDatabase(_ data: Data, file: String) -> Bool {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["schema_version"] as? Int == 3, json["arch"] as? String == "arm64",
              json["platform"] as? String == "macos",
              let build = build(json["steam_build"]), "\(build).json" == file,
              let signatures = json["signatures"] as? [[String: Any]], !signatures.isEmpty
        else { return false }
        return true
    }
}

struct SignatureOutcome: Sendable, Equatable {
    /// Databases written this time.
    let installed: [String]
    let supportedBuilds: [UInt64]
}

struct SignatureUpdater: Sendable {
    var signatures: URL = SupportPaths.signatures
    var manifests: URL = SupportPaths.manifests
    var feed: ReleaseFeed.Setup = ReleaseFeed.configured
    var transport: any EngineTransport = URLSessionEngineTransport()
    var bundledRoot: URL? = try? InstallPayload.root()

    func support() -> SignatureSupport {
        SignatureSupport.load(bundledRoot: bundledRoot, feed: feed, manifests: manifests)
    }

    /// Reads the signed manifest and writes every database it names that is missing
    /// or different on disk. Steam picks them up the next time it starts.
    func update() async throws -> SignatureOutcome {
        guard case .ready(let feed) = feed else {
            let support = support()
            return SignatureOutcome(installed: [], supportedBuilds: support.supportedBuilds(installedIn: signatures))
        }
        let document = try await SignedDocument.fetch(
            feed.signaturesManifestURL, feed: feed, transport: transport, cache: manifests,
            schema: SignatureSupport.schema)
        let remote = SignatureSupport.parse(document.json, feed: feed)
        try FileManager.default.createDirectory(at: signatures, withIntermediateDirectories: true)
        var installed: [String] = []
        for database in remote.databases {
            guard let url = database.url else { continue }
            let target = signatures.appending(path: database.file)
            if Digest.sha256IfPresent(target) == database.sha256 { continue }
            let data: Data
            do {
                data = try await transport.fetch(url, limit: 8 << 20)
            } catch {
                AppLog.note("signatures: \(database.file) fetch failed: \(error.localizedDescription)")
                throw StepFailure(step: SignatureSupport.step, detail: EngineUpdater.offline)
            }
            guard Digest.sha256(of: data) == database.sha256 else {
                AppLog.note("signatures: \(database.file) sha256 does not match the manifest")
                throw StepFailure(
                    step: SignatureSupport.step,
                    detail: "The signature database \(database.file) does not match NotProton's signed list, so NotProton refused it.")
            }
            guard SignatureSupport.isUsableDatabase(data, file: database.file) else {
                throw StepFailure(
                    step: SignatureSupport.step,
                    detail: "The signature database \(database.file) is not one notproton.dylib can read, so NotProton refused it.")
            }
            try atomicReplace(target, with: data, step: SignatureSupport.step)
            installed.append(database.file)
            AppLog.note("signatures: installed \(database.file) (\(database.sha256.prefix(12)))")
        }
        let builds = support().supportedBuilds(installedIn: signatures)
        AppLog.note("signatures: serial \(document.serial), supported builds \(builds.map(String.init).joined(separator: " "))")
        return SignatureOutcome(installed: installed, supportedBuilds: builds)
    }
}
