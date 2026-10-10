// Which Steam bridge fits which Dormison release (Phase 5, docs/DECISIONS.md P5-1).
//
// A bridge build is lsteamclient (x86_64 and i386 PE, x86_64 unix), the steam.exe
// shim, and the B1 ntdll.dll pair (P3-1), all built from one Dormison commit. One
// build is one artifact, bridge-<engine>-<rev>, described by an entry of
// bridge-manifest.json:
//
//   { "schema": 1, "serial": 3, "bridges": [ {
//       "id": "bridge-dormison-b1-2", "engine": "dormison-b1",
//       "engineCommit": "52c2a4b9…", "rev": 2,
//       "files": [ { "name": "steam.exe", "path": "steam.exe", "sha256": "…" }, … ],
//       "ntdll": [ { "arch": "x86_64", "path": "wine/lib/wine/x86_64-windows/ntdll.dll",
//                    "file": "ntdll/x86_64-ntdll.dll", "clean": "…", "b1": "…" }, … ],
//       "engineFiles": [ { "path": "wine/lib/wine/x86_64-unix/winemac.so",
//                          "file": "engine/winemac.so", "clean": "…", "patched": "…" } ],
//       "engineRelease": { "url": "https://github.com/kageroumado/dormison/releases/download/b1/dormison-b1.tar.xz",
//                          "sha256": "…", "sizeBytes": 123 },
//       "url": "<feed>/bridge-dormison-b1-2/bridge-dormison-b1-2.tar.xz",
//       "sha256": "…", "sizeBytes": 123 } ] }
//
// engineRelease (optional) is the Dormison tarball the bridge was built for. Dormison's
// engine.json names only its newest release; with this, Install can still take the
// newest engine that has a bridge (DECISIONS P8-17). The tarball is checked the same
// way: this sha256 and size, and Dormison's own signature.
//
// Three places feed the catalog, the higher wins for one id:
//   installed  notproton/bridges/<id>/bridge.json, files verified when installed;
//   bundled    the app's payload (engine-support/bridge-manifest.json), no url and
//              no file digests: SwiftPM strips Mach-O resources (R27), the app's
//              own signature covers them. A bridge with engine fixes (Mach-O .so
//              files) is bundled as its published tarball instead ("archive", every
//              file with its digest) and unpacked into bridges/ when it is needed;
//   remote     the signed manifest from NotProton's releases (ReleaseFeed), every
//              file with its digest.
// An engine is supported when some bridge names its version: the commit and the
// release's ntdll.dll are checked against the entry once the engine is unpacked.

import Foundation

struct BridgeRelease: Sendable, Equatable {
    struct File: Sendable, Equatable {
        /// The BridgePayload resource name: steam.exe, x86_64-windows-lsteamclient.dll, …
        let name: String
        /// Inside the artifact root.
        let path: String
        let sha256: String?
    }

    struct Ntdll: Sendable, Equatable {
        let arch: String
        /// Inside the engine, e.g. wine/lib/wine/x86_64-windows/ntdll.dll.
        let path: String
        /// The B1 file inside the artifact root.
        let file: String
        /// The release's own file, as its engine-manifest.json lists it.
        let clean: String
        let b1: String
    }

    /// An engine file rebuilt from the same commit with NotProton's fixes
    /// (engine-fixes/build-fixes.sh), put in place like the B1 pair. Optional: older
    /// bridges carry none.
    struct EngineFile: Sendable, Equatable {
        /// Inside the engine, e.g. wine/lib/wine/x86_64-unix/winemac.so.
        let path: String
        /// The patched file inside the artifact root.
        let file: String
        /// The release's own file.
        let clean: String
        let patched: String
    }

    /// Where the engine this bridge was built for is downloaded from.
    struct EngineDownload: Sendable, Equatable {
        let url: URL
        let sha256: String
        let sizeBytes: Int64
    }

    enum Origin: Sendable, Equatable {
        case bundled(URL)
        /// The published tarball inside the app, unpacked into bridges/ before use.
        case packed(archive: URL, sha256: String, sizeBytes: Int64)
        case installed(URL)
        case remote(url: URL, sha256: String, sizeBytes: Int64)
    }

    let id: String
    let engine: String
    let engineCommit: String
    let rev: Int
    let files: [File]
    let ntdll: [Ntdll]
    var engineFiles: [EngineFile] = []
    var engineRelease: EngineDownload?
    var origin: Origin

    var root: URL? {
        switch origin {
        case .bundled(let root), .installed(let root): root
        case .remote, .packed: nil
        }
    }

    var isBundled: Bool {
        switch origin {
        case .bundled, .packed: true
        case .installed, .remote: false
        }
    }

    /// "revision 2 for Dormison b1"
    var label: String { "revision \(rev) for \(EngineStore.displayName(engine))" }

    /// The four files in BridgePayload's shape, for staging into notproton/bridge.
    func located() throws -> BridgePayload.Located {
        guard let root else {
            throw StepFailure(step: BridgeStore.step, detail: "The Steam bridge \(id) is not downloaded yet.")
        }
        return BridgePayload.Located(sources: BridgePayload.entries.compactMap { entry in
            files.first { $0.name == entry.resource }.map { (root.appending(path: $0.path), entry.bridgePaths) }
        })
    }

    /// The entry as bridge.json and the manifests carry it (without the origin).
    var json: [String: Any] {
        var out: [String: Any] = [
            "id": id, "engine": engine, "engineCommit": engineCommit, "rev": rev,
            "files": files.map { file -> [String: String] in
                var item = ["name": file.name, "path": file.path]
                if let sha = file.sha256 { item["sha256"] = sha }
                return item
            },
            "ntdll": ntdll.map {
                ["arch": $0.arch, "path": $0.path, "file": $0.file, "clean": $0.clean, "b1": $0.b1]
            },
        ]
        if !engineFiles.isEmpty {
            out["engineFiles"] = engineFiles.map {
                ["path": $0.path, "file": $0.file, "clean": $0.clean, "patched": $0.patched]
            }
        }
        if let engineRelease {
            out["engineRelease"] = [
                "url": engineRelease.url.absoluteString, "sha256": engineRelease.sha256,
                "sizeBytes": engineRelease.sizeBytes,
            ] as [String: Any]
        }
        if case .remote(let url, let sha, let size) = origin {
            out["url"] = url.absoluteString
            out["sha256"] = sha
            out["sizeBytes"] = size
        }
        return out
    }

    static let fileNames = Set(BridgePayload.entries.map(\.resource))

    /// One entry. `remote`: the feed it must come from; nil reads a local entry
    /// (bundled or installed) whose files sit under `root`.
    static func parse(_ item: [String: Any], remote feed: ReleaseFeed?, root: URL?, bundled: Bool) throws -> BridgeRelease {
        let id = item["id"] as? String ?? "?"
        let bad = { (why: String) in
            StepFailure(step: BridgeStore.step, detail: "The Steam bridge list entry \(id) is unusable: \(why).")
        }
        guard let engine = item["engine"] as? String, EngineManifest.isVersionName(engine) else {
            throw bad("no Dormison version")
        }
        guard let rev = item["rev"] as? Int, rev > 0, id == "bridge-\(engine)-\(rev)" else {
            throw bad("its name is not bridge-<engine>-<revision>")
        }
        guard let commit = item["engineCommit"] as? String, commit.count == 40, commit.allSatisfy(\.isHexDigit) else {
            throw bad("no engine commit")
        }
        var files: [File] = []
        for raw in item["files"] as? [[String: Any]] ?? [] {
            guard let name = raw["name"] as? String, let path = raw["path"] as? String,
                  fileNames.contains(name), EngineSupport.isSafeRelative(path)
            else { throw bad("a file entry is unusable") }
            let sha = (raw["sha256"] as? String)?.lowercased()
            if let sha, !EngineManifest.isSHA256(sha) { throw bad("\(name) has no valid sha256") }
            if !bundled || item["archive"] != nil, sha == nil { throw bad("\(name) has no sha256") }
            files.append(File(name: name, path: path, sha256: sha))
        }
        guard Set(files.map(\.name)) == fileNames, files.count == fileNames.count else {
            throw bad("it does not list lsteamclient and steam.exe exactly once each")
        }
        var ntdll: [Ntdll] = []
        for raw in item["ntdll"] as? [[String: Any]] ?? [] {
            guard let arch = raw["arch"] as? String, let path = raw["path"] as? String,
                  let file = raw["file"] as? String, let clean = (raw["clean"] as? String)?.lowercased(),
                  let b1 = (raw["b1"] as? String)?.lowercased(),
                  EngineSupport.isSafeRelative(path), EngineSupport.isSafeRelative(file),
                  EngineManifest.isSHA256(clean), EngineManifest.isSHA256(b1)
            else { throw bad("an ntdll.dll entry is unusable") }
            ntdll.append(Ntdll(arch: arch, path: path, file: file, clean: clean, b1: b1))
        }
        guard Set(ntdll.map(\.arch)) == ["x86_64", "i386"], ntdll.count == 2 else {
            throw bad("the Steam loader patch is not there for both x86_64 and i386")
        }
        var engineFiles: [EngineFile] = []
        for raw in item["engineFiles"] as? [[String: Any]] ?? [] {
            guard let path = raw["path"] as? String, let file = raw["file"] as? String,
                  let clean = (raw["clean"] as? String)?.lowercased(),
                  let patched = (raw["patched"] as? String)?.lowercased(),
                  EngineSupport.isSafeRelative(path), EngineSupport.isSafeRelative(file),
                  path.hasPrefix("wine/lib/wine/"), !ntdll.contains(where: { $0.path == path }),
                  EngineManifest.isSHA256(clean), EngineManifest.isSHA256(patched)
            else { throw bad("an engine file entry is unusable") }
            engineFiles.append(EngineFile(path: path, file: file, clean: clean, patched: patched))
        }
        guard Set(engineFiles.map(\.path)).count == engineFiles.count else {
            throw bad("an engine file is listed twice")
        }

        var engineRelease: EngineDownload?
        if let raw = item["engineRelease"] {
            guard let raw = raw as? [String: Any],
                  let text = raw["url"] as? String, let url = URL(string: text),
                  EngineSignature.isDormisonAsset(url), url.lastPathComponent == "\(engine).tar.xz",
                  let sha = (raw["sha256"] as? String)?.lowercased(), EngineManifest.isSHA256(sha),
                  let size = (raw["sizeBytes"] as? NSNumber)?.int64Value, size > 0
            else { throw bad("its engine download is not a Dormison release asset with a sha256 and size") }
            engineRelease = EngineDownload(url: url, sha256: sha, sizeBytes: size)
        }

        let origin: Origin
        if let feed {
            guard let text = item["url"] as? String, let url = URL(string: text), feed.allows(url),
                  url.lastPathComponent.hasPrefix(id)
            else { throw bad("its download is not in NotProton's releases") }
            guard let sha = (item["sha256"] as? String)?.lowercased(), EngineManifest.isSHA256(sha) else {
                throw bad("no sha256")
            }
            guard let size = (item["sizeBytes"] as? NSNumber)?.int64Value, size > 0 else { throw bad("no size") }
            origin = .remote(url: url, sha256: sha, sizeBytes: size)
        } else if let root, bundled, let raw = item["archive"] {
            guard let raw = raw as? [String: Any],
                  let path = raw["path"] as? String, EngineSupport.isSafeRelative(path),
                  let sha = (raw["sha256"] as? String)?.lowercased(), EngineManifest.isSHA256(sha),
                  let size = (raw["sizeBytes"] as? NSNumber)?.int64Value, size > 0
            else { throw bad("its bundled archive is unusable") }
            origin = .packed(archive: root.appending(path: path), sha256: sha, sizeBytes: size)
        } else if let root {
            origin = bundled ? .bundled(root) : .installed(root)
        } else {
            throw bad("it has no files")
        }
        return BridgeRelease(
            id: id, engine: engine, engineCommit: commit.lowercased(), rev: rev, files: files, ntdll: ntdll,
            engineFiles: engineFiles, engineRelease: engineRelease, origin: origin)
    }

    /// The bridge list of a manifest. Unusable entries are left out and logged, so
    /// one bad entry does not hide the others.
    static func list(_ json: [String: Any], remote feed: ReleaseFeed?, root: URL?, bundled: Bool) -> [BridgeRelease] {
        (json["bridges"] as? [[String: Any]] ?? []).compactMap { item in
            do {
                return try parse(item, remote: feed, root: root, bundled: bundled)
            } catch {
                AppLog.note("bridge: \(error.localizedDescription)")
                return nil
            }
        }
    }
}

struct BridgeCatalog: Sendable {
    static let manifestName = "bridge-manifest.json"
    static let schema = 1

    /// One per id: installed over bundled over remote.
    let releases: [BridgeRelease]
    /// The serial of the verified remote manifest the catalog read, if any.
    let remoteSerial: Int?

    init(releases: [BridgeRelease], remoteSerial: Int? = nil) {
        var byID: [String: BridgeRelease] = [:]
        func rank(_ release: BridgeRelease) -> Int {
            switch release.origin {
            case .installed: 2
            case .bundled, .packed: 1
            case .remote: 0
            }
        }
        for release in releases where byID[release.id].map({ rank($0) < rank(release) }) ?? true {
            byID[release.id] = release
        }
        self.releases = byID.values.sorted { ($0.engine, $0.rev) < ($1.engine, $1.rev) }
        self.remoteSerial = remoteSerial
    }

    /// The bundled list: <root>/engine-support/bridge-manifest.json, files under root.
    static func bundled(root: URL) -> [BridgeRelease] {
        let file = root.appending(path: "\(EngineSupport.directoryName)/\(manifestName)")
        guard let data = try? Data(contentsOf: file),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["schema"] as? Int == schema
        else { return [] }
        return BridgeRelease.list(json, remote: nil, root: root, bundled: true)
    }

    static func load(
        bundledRoot: URL?, store: URL, feed: ReleaseFeed.Setup, manifests: URL
    ) -> BridgeCatalog {
        var releases = bundledRoot.map(bundled(root:)) ?? []
        releases += BridgeStore.installedReleases(in: store)
        var serial: Int?
        if case .ready(let feed) = feed,
           let document = SignedDocument.cached(manifestName, in: manifests, key: feed.key, schema: schema)
        {
            releases += BridgeRelease.list(document.json, remote: feed, root: nil, bundled: false)
            serial = document.serial
        }
        return BridgeCatalog(releases: releases, remoteSerial: serial)
    }

    /// Bridges for `engine`, best first: higher revision, then one already on disk.
    func candidates(for engine: String) -> [BridgeRelease] {
        releases.filter { $0.engine == engine }.sorted {
            if $0.rev != $1.rev { return $0.rev > $1.rev }
            return $0.root != nil && $1.root == nil
        }
    }

    enum Verdict: Sendable, Equatable {
        case supported(BridgeRelease)
        case waiting(reason: String)
    }

    /// Supported: a bridge for the version that is on disk with its B1 files, or
    /// one NotProton's releases offer for download.
    func verdict(for version: String) -> Verdict {
        let all = candidates(for: version)
        guard !all.isEmpty else {
            return .waiting(reason: "No Steam bridge has been published for it yet.")
        }
        for release in all {
            guard let root = release.root else { return .supported(release) }
            let complete = release.ntdll.allSatisfy { Digest.sha256IfPresent(root.appending(path: $0.file)) == $0.b1 }
                && release.engineFiles.allSatisfy { Digest.sha256IfPresent(root.appending(path: $0.file)) == $0.patched }
                && release.files.allSatisfy {
                    FileManager.default.fileExists(atPath: root.appending(path: $0.path).path(percentEncoded: false))
                }
            if complete { return .supported(release) }
            AppLog.note("bridge: \(release.id) is incomplete on disk")
        }
        return .waiting(reason: "The Steam loader patch for it is missing from this build.")
    }

    func release(id: String) -> BridgeRelease? { releases.first { $0.id == id } }

    /// The newest engine NotProton can download by itself, from the bridges that say
    /// where their engine comes from, and only when that bridge is usable (verdict).
    /// What Install falls back to while Dormison's newest release has no bridge.
    func newestDownloadableEngine(on channel: EngineChannel) -> EngineRelease? {
        let engines = Set(releases.filter { $0.engineRelease != nil }.map(\.engine))
        let newestFirst = engines.sorted { EngineManifest.isOlder($1, than: $0) }
        for engine in newestFirst {
            guard case .supported = verdict(for: engine),
                  let download = candidates(for: engine).lazy.compactMap(\.engineRelease).first
            else { continue }
            return EngineRelease(
                channel: channel, version: engine, url: download.url, sha256: download.sha256,
                sizeBytes: download.sizeBytes, notes: "the newest engine with a Steam bridge", minAppVersion: nil)
        }
        return nil
    }
}

/// Helpers shared with the engine side.
enum EngineSupport {
    static let directoryName = "engine-support"
    /// The string the B1 hook logs; its presence tells a B1 ntdll.dll from the release's.
    static let b1Marker = Data("lead to lsteamclient".utf8)

    static func isSafeRelative(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }

    static func carriesB1(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        return data.range(of: b1Marker) != nil
    }
}
