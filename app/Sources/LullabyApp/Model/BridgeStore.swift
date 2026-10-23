// Steam bridge builds on disk and the one games use (Phase 5, DECISIONS P5-2).
//
//   lullaby/bridges/<id>/          a downloaded build: the files its entry lists
//                                    and bridge.json (the entry); checked when installed
//   lullaby/bridges/state.json     { "current": id, "previous": id }
//   lullaby/bridge/                what compat_run.sh reads: the active build's
//                                    lsteamclient and steam.exe, Valve's files, and
//                                    the copy of the engine's B1 ntdll.dll
//
// Activating a build puts its B1 ntdll.dll pair into the engine (the release's file
// kept as ntdll.dll.lullaby-orig) and its four files into lullaby/bridge. A
// bridge only fits the engine it was built against: the commit in engine-info.json
// must be the entry's, and the engine's own ntdll.dll must be the one the B1 pair
// was built from. lsteamclient and steam.exe load only in game processes, so Steam
// may stay open; a running game refuses the change.
//
// BridgeUpdater offers newer revisions for the active engine and rolls back;
// EngineUpdater fetches the bridge a new engine needs and, after any engine switch,
// follow() makes the live bridge match the engine.

import CryptoKit
import Darwin
import Foundation
import Synchronization

enum BridgePhase: Sendable, Equatable {
    case checking
    case downloading(received: Int64, total: Int64)
    case verifying
    case unpacking
    case checkingFiles
    case patching
    case switching

    var label: String {
        switch self {
        case .checking: "Checking for Steam bridge updates"
        case .downloading(let received, let total):
            "Downloading the Steam bridge (\(ByteCountFormatter.string(fromByteCount: received, countStyle: .file)) of "
                + "\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)))"
        case .verifying: "Verifying the Steam bridge"
        case .unpacking: "Unpacking the Steam bridge"
        case .checkingFiles: "Checking the Steam bridge's files"
        case .patching: "Adding the Steam loader patch"
        case .switching: "Switching the Steam bridge"
        }
    }
}

struct BridgeStore: Sendable {
    static let step = "Update the Steam bridge"
    static let stateName = "state.json"
    static let infoName = "bridge.json"

    var store: URL = SupportPaths.bridges
    var live: URL = SupportPaths.bridge
    var downloads: URL = SupportPaths.bridgeDownloads

    struct State: Codable, Equatable, Sendable {
        var current: String?
        var previous: String?
    }

    var state: State {
        guard let data = try? Data(contentsOf: store.appending(path: Self.stateName)),
              let state = try? JSONDecoder().decode(State.self, from: data)
        else { return State() }
        return state
    }

    func save(_ state: State) throws {
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try atomicReplace(store.appending(path: Self.stateName), with: try encoder.encode(state), step: Self.step)
    }

    static func installedReleases(in store: URL) -> [BridgeRelease] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: store.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasPrefix("bridge-") }.sorted().compactMap { name in
            let root = store.appending(path: name)
            guard let data = try? Data(contentsOf: root.appending(path: infoName)),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let release = try? BridgeRelease.parse(json, remote: nil, root: root, bundled: false),
                  release.id == name
            else {
                AppLog.note("bridge: bridges/\(name) has no usable \(infoName)")
                return nil
            }
            return release
        }
    }

    // MARK: Download

    /// A remote build downloaded, verified and unpacked into bridges/<id>; one packed in
    /// the app checked and unpacked the same way; a local one as it is. `key` checks a
    /// download's signature (nil: Lullaby's releases are off, so only packed ones go).
    func obtain(
        _ release: BridgeRelease, key: Curve25519.Signing.PublicKey?, transport: any EngineTransport,
        report: @escaping @Sendable (BridgePhase) -> Void = { _ in }
    ) async throws -> BridgeRelease {
        let step = Self.step
        let fm = FileManager.default
        switch release.origin {
        case .bundled, .installed:
            return release
        case .remote, .packed:
            break
        }
        if let installed = Self.installedReleases(in: store).first(where: { $0.id == release.id }),
           installed.files == release.files, installed.ntdll == release.ntdll,
           installed.engineFiles == release.engineFiles
        {
            return installed
        }
        if case .packed(let archive, let sha, let total) = release.origin {
            report(.verifying)
            guard size(of: archive) == total, Digest.sha256IfPresent(archive) == sha else {
                AppLog.note("bridge: the packed \(archive.lastPathComponent) does not match its entry")
                throw StepFailure(
                    step: step, detail: "The Steam bridge inside Lullaby is damaged. Download Lullaby again.")
            }
            AppLog.note("bridge: packed \(archive.lastPathComponent) verified (size, sha256)")
            return try unpack(release, archive: archive, report: report)
        }
        guard case .remote(let url, let sha, let total) = release.origin else { return release }
        guard let key else { throw StepFailure(step: step, detail: ReleaseFeed.noKey) }
        try fm.createDirectory(at: downloads, withIntermediateDirectories: true)
        try fm.createDirectory(at: store, withIntermediateDirectories: true)
        let name = url.lastPathComponent
        let part = downloads.appending(path: name + ".part")
        if size(of: part) > total { try? fm.removeItem(at: part) }
        if size(of: part) < total {
            AppLog.note("bridge: downloading \(name)\(size(of: part) > 0 ? " from byte \(size(of: part))" : "")")
            report(.downloading(received: size(of: part), total: total))
            let reported = Mutex<Int64>(0)
            do {
                try await transport.download(url, to: part) { received in
                    let due = reported.withLock { last in
                        guard received - last >= max(total / 50, 1 << 20) || received == total else { return false }
                        last = received
                        return true
                    }
                    if due { report(.downloading(received: received, total: total)) }
                }
            } catch {
                AppLog.note("bridge: download stopped at \(size(of: part)) of \(total): \(error.localizedDescription)")
                throw StepFailure(
                    step: step,
                    detail: "The download stopped. \(ReleaseAccess.failure(error)) What arrived is kept, and the next try continues from there.")
            }
        }
        report(.verifying)
        guard size(of: part) == total else {
            if size(of: part) > total { try? fm.removeItem(at: part) }
            throw StepFailure(step: step, detail: "The download is \(size(of: part)) bytes, the bridge list says \(total). Try again.")
        }
        let digest = try Digest.sha256(of: part)
        guard digest == sha else {
            try? fm.removeItem(at: part)
            AppLog.note("bridge: \(name) sha256 \(digest), manifest \(sha)")
            throw StepFailure(
                step: step, detail: "The downloaded Steam bridge does not match the bridge list (sha256), so Lullaby deleted it.")
        }
        let signature: Data
        do {
            signature = try await transport.fetch(EngineSignature.signatureURL(for: url), limit: 1024)
        } catch {
            throw StepFailure(step: step, detail: ReleaseAccess.failure(error))
        }
        guard EngineSignature.isValid(try Data(contentsOf: part, options: .mappedIfSafe), signatureFile: signature, key: key) else {
            try? fm.removeItem(at: part)
            AppLog.note("bridge: \(name) signature invalid")
            throw StepFailure(
                step: step,
                detail: "The downloaded Steam bridge does not carry Lullaby's release signature, so Lullaby deleted it.")
        }
        AppLog.note("bridge: \(name) verified (size, sha256, signature)")
        let installed = try unpack(release, archive: part, report: report)
        try? fm.removeItem(at: part)
        return installed
    }

    /// A checked tarball into bridges/<id>, every file against the entry.
    private func unpack(
        _ release: BridgeRelease, archive part: URL, report: @escaping @Sendable (BridgePhase) -> Void
    ) throws -> BridgeRelease {
        let fm = FileManager.default
        try fm.createDirectory(at: store, withIntermediateDirectories: true)
        report(.unpacking)
        let partial = store.appending(path: ".\(release.id).partial")
        try? fm.removeItem(at: partial)
        do {
            try fm.createDirectory(at: partial, withIntermediateDirectories: true)
            try Shell.check("/usr/bin/tar", [
                "-xJf", part.path(percentEncoded: false), "-C", partial.path(percentEncoded: false),
                "--strip-components", "1", "\(release.id)/",
            ])
            report(.checkingFiles)
            try Self.verifyFiles(of: release, at: partial)
            let info = try JSONSerialization.data(withJSONObject: release.json, options: [.prettyPrinted, .sortedKeys])
            try info.write(to: partial.appending(path: Self.infoName))
            let destination = store.appending(path: release.id)
            if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
                let aside = store.appending(path: ".\(release.id).replaced")
                try? fm.removeItem(at: aside)
                try fm.moveItem(at: destination, to: aside)
                try fm.moveItem(at: partial, to: destination)
                try? fm.removeItem(at: aside)
            } else {
                try fm.moveItem(at: partial, to: destination)
            }
            AppLog.note("bridge: \(release.id) installed in bridges/")
            var installed = release
            installed.origin = .installed(destination)
            return installed
        } catch {
            try? fm.removeItem(at: partial)
            AppLog.note("bridge: unpacking \(release.id) failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Every listed file with its digest, nothing else (bridge.json may be there).
    static func verifyFiles(of release: BridgeRelease, at root: URL) throws {
        var listed: Set<String> = [infoName]
        var problems: [String] = []
        for file in release.files {
            listed.insert(file.path)
            if Digest.sha256IfPresent(root.appending(path: file.path)) != file.sha256 {
                problems.append("\(file.path): sha256 differs or missing")
            }
        }
        for item in release.ntdll {
            listed.insert(item.file)
            if Digest.sha256IfPresent(root.appending(path: item.file)) != item.b1 {
                problems.append("\(item.file): sha256 differs or missing")
            }
        }
        for item in release.engineFiles {
            listed.insert(item.file)
            if Digest.sha256IfPresent(root.appending(path: item.file)) != item.patched {
                problems.append("\(item.file): sha256 differs or missing")
            }
        }
        if let walker = FileManager.default.enumerator(atPath: root.path(percentEncoded: false)) {
            while let relative = walker.nextObject() as? String {
                let type = walker.fileAttributes?[.type] as? FileAttributeType
                if type == .typeDirectory { continue }
                if !listed.contains(relative) { problems.append("\(relative): not in the bridge list") }
            }
        }
        guard problems.isEmpty else {
            AppLog.note("bridge: \(problems.count) file problem(s): " + problems.prefix(8).joined(separator: "; "))
            throw StepFailure(
                step: step,
                detail: "\(problems.count) file(s) of the Steam bridge do not match its list, for example \(problems[0]).")
        }
    }

    // MARK: Activation

    struct EngineInfo: Sendable, Equatable {
        let root: URL
        let version: String
        let commit: String
    }

    static func engineInfo(_ root: URL) -> EngineInfo? {
        guard let data = try? Data(contentsOf: root.appending(path: "engine-info.json")),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let version = json["version"] as? String, let commit = json["commit"] as? String
        else { return nil }
        return EngineInfo(root: root, version: version, commit: commit.lowercased())
    }

    /// Why `release` cannot run games on `engine`, or nil when it fits.
    static func mismatch(_ release: BridgeRelease, _ engine: EngineInfo) -> String? {
        if release.engine != engine.version {
            return "The Steam bridge \(release.id) is for \(EngineStore.displayName(release.engine)), "
                + "the engine is \(EngineStore.displayName(engine.version))."
        }
        if release.engineCommit != engine.commit {
            return "The Steam bridge \(release.id) was built against \(release.engineCommit.prefix(12)), "
                + "the engine is \(engine.commit.prefix(12))."
        }
        return nil
    }

    /// B1 pair into the engine, files into lullaby/bridge, state updated.
    func activate(_ release: BridgeRelease, engine root: URL) throws {
        let step = Self.step
        guard let engine = Self.engineInfo(root) else {
            throw StepFailure(step: step, detail: "The engine has no readable engine-info.json.")
        }
        if let why = Self.mismatch(release, engine) {
            AppLog.note("bridge: refused \(release.id): \(why)")
            throw StepFailure(step: step, detail: why + " Lullaby did not change the bridge.")
        }
        let located = try release.located()
        try Self.applyB1(release, to: root)
        _ = try BridgePayload.stage(located: located, bridge: live)
        EngineUpdater.syncBridgeNtdll(engine: root, bridge: live)
        var state = state
        if state.current != release.id {
            state.previous = state.current
            state.current = release.id
        }
        try save(state)
        AppLog.note("bridge: active \(release.id) (\(release.isBundled ? "bundled" : "downloaded")) "
            + "previous=\(state.previous ?? "none") engine=\(engine.version)")
    }

    /// The engine's ntdll.dll pair becomes this bridge's B1. The release's file is
    /// found in place or as .lullaby-orig and must be the one the pair was built from.
    static func applyB1(_ release: BridgeRelease, to engine: URL) throws {
        let fm = FileManager.default
        guard let root = release.root else {
            throw StepFailure(step: step, detail: "The Steam bridge \(release.id) is not downloaded yet.")
        }
        for item in release.ntdll {
            let live = engine.appending(path: item.path)
            if Digest.sha256IfPresent(live) == item.b1 { continue }
            let original = live.deletingLastPathComponent().appending(path: "ntdll.dll.lullaby-orig")
            if Digest.sha256IfPresent(live) == item.clean {
                let staging = live.deletingLastPathComponent().appending(path: ".ntdll.dll.orig.new")
                try? fm.removeItem(at: staging)
                try fm.copyItem(at: live, to: staging)
                try rename(staging, to: original)
            } else if Digest.sha256IfPresent(original) != item.clean {
                throw StepFailure(
                    step: step,
                    detail: "\(item.path) in \(EngineStore.displayName(release.engine)) is not the file the Steam loader patch was built for.")
            }
            let staging = live.deletingLastPathComponent().appending(path: ".ntdll.dll.new")
            try? fm.removeItem(at: staging)
            try fm.copyItem(at: root.appending(path: item.file), to: staging)
            try rename(staging, to: live)
            guard Digest.sha256IfPresent(live) == item.b1 else {
                throw StepFailure(step: step, detail: "The patched \(item.path) did not check out.")
            }
            AppLog.note("bridge: \(item.arch) ntdll.dll is B1 \(item.b1.prefix(12)) from \(release.id)")
        }
        try applyEngineFiles(release, root: root, to: engine)
    }

    static let originalSuffix = ".lullaby-orig"

    /// The bridge's engine fixes into the engine, each release file kept beside it as
    /// <name>.lullaby-orig; a fix an earlier bridge put in and this one does not carry
    /// gets the release's file back, so a roll-back undoes it.
    static func applyEngineFiles(_ release: BridgeRelease, root: URL, to engine: URL) throws {
        let fm = FileManager.default
        for item in release.engineFiles {
            let live = engine.appending(path: item.path)
            if Digest.sha256IfPresent(live) == item.patched { continue }
            let name = live.lastPathComponent
            let original = live.deletingLastPathComponent().appending(path: name + originalSuffix)
            if Digest.sha256IfPresent(live) == item.clean {
                let staging = live.deletingLastPathComponent().appending(path: ".\(name).orig.new")
                try? fm.removeItem(at: staging)
                try fm.copyItem(at: live, to: staging)
                try rename(staging, to: original)
            } else if Digest.sha256IfPresent(original) != item.clean {
                throw StepFailure(
                    step: step,
                    detail: "\(item.path) in \(EngineStore.displayName(release.engine)) is not the file Lullaby's fix was built for.")
            }
            let staging = live.deletingLastPathComponent().appending(path: ".\(name).new")
            try? fm.removeItem(at: staging)
            try fm.copyItem(at: root.appending(path: item.file), to: staging)
            try rename(staging, to: live)
            guard Digest.sha256IfPresent(live) == item.patched else {
                throw StepFailure(step: step, detail: "The fixed \(item.path) did not check out.")
            }
            AppLog.note("bridge: \(item.path) is the fixed \(item.patched.prefix(12)) from \(release.id)")
        }
        // Fixes of an earlier bridge: the release's file back in place.
        let carried = Set(release.engineFiles.map(\.path) + release.ntdll.map(\.path))
        let wine = engine.appending(path: "wine/lib/wine")
        guard let walker = fm.enumerator(atPath: wine.path(percentEncoded: false)) else { return }
        while let relative = walker.nextObject() as? String {
            guard relative.hasSuffix(originalSuffix) else { continue }
            let livePath = "wine/lib/wine/" + String(relative.dropLast(originalSuffix.count))
            guard !carried.contains(livePath) else { continue }
            let original = wine.appending(path: relative)
            let live = engine.appending(path: livePath)
            let staging = live.deletingLastPathComponent().appending(path: ".\(live.lastPathComponent).new")
            try? fm.removeItem(at: staging)
            try fm.copyItem(at: original, to: staging)
            try rename(staging, to: live)
            try fm.removeItem(at: original)
            AppLog.note("bridge: \(livePath) is the release's again (\(release.id) carries no fix for it)")
        }
    }

    /// After an engine switch: the bridge the active choice names if it fits the engine
    /// now at `engine`, otherwise the best one on disk for it. Nil when none fits.
    @discardableResult
    func follow(engine root: URL, catalog: BridgeCatalog) -> BridgeRelease? {
        guard let engine = Self.engineInfo(root) else { return nil }
        let fitting = catalog.candidates(for: engine.version).filter {
            $0.root != nil && Self.mismatch($0, engine) == nil
        }
        let chosen = fitting.first { $0.id == state.current } ?? fitting.first
        guard let chosen else {
            AppLog.note("bridge: no Steam bridge on disk for \(engine.version) (\(engine.commit.prefix(12)))")
            return nil
        }
        do {
            try activate(chosen, engine: root)
            return chosen
        } catch {
            AppLog.note("bridge: following \(engine.version) with \(chosen.id) failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Removes downloaded builds other than `keep`, and leftovers of interrupted runs.
    func prune(keep: Set<String>) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: store.path(percentEncoded: false))) ?? [] {
            let leftover = name.hasPrefix(".bridge-") && (name.hasSuffix(".partial") || name.hasSuffix(".replaced"))
            guard leftover || (name.hasPrefix("bridge-") && !keep.contains(name)), !name.contains("/") else { continue }
            do {
                try fm.removeItem(at: store.appending(path: name))
                AppLog.note("bridge: removed bridges/\(name)")
            } catch {
                AppLog.note("bridge: could not remove bridges/\(name): \(error.localizedDescription)")
            }
        }
    }

    private static func rename(_ from: URL, to: URL) throws {
        if Darwin.rename(from.path(percentEncoded: false), to.path(percentEncoded: false)) != 0 {
            let reason = String(cString: strerror(errno))
            try? FileManager.default.removeItem(at: from)
            throw StepFailure(step: step, detail: "Could not move \(from.lastPathComponent) into place. \(reason)")
        }
    }

    private func size(of url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.size] as? NSNumber)?
            .int64Value ?? 0
    }
}

// MARK: - Updates for the active engine

enum BridgeCheck: Sendable, Equatable {
    case upToDate(BridgeRelease)
    /// `release` is newer than `current` (nil: no bridge is active for this engine).
    case available(BridgeRelease, current: BridgeRelease?)
    case noEngine
    /// Nothing anywhere fits the active engine.
    case noBridge(engine: String)

    var summary: String {
        switch self {
        case .upToDate(let release): "up to date with \(release.id)"
        case .available(let release, let current): "\(release.id) available (active: \(current?.id ?? "none"))"
        case .noEngine: "no engine"
        case .noBridge(let engine): "no bridge for \(engine)"
        }
    }
}

struct BridgeOutcome: Sendable, Equatable {
    let id: String
    let previous: String?
}

struct BridgeUpdater: Sendable {
    static let rollbackStep = "Roll back the Steam bridge"

    var store = BridgeStore()
    var runners: URL = SupportPaths.runners
    var manifests: URL = SupportPaths.manifests
    var feed: ReleaseFeed.Setup = ReleaseFeed.configured
    var transport: any EngineTransport = URLSessionEngineTransport()
    var bundledRoot: URL? = try? InstallPayload.root()
    var gameIsRunning: @Sendable () -> Bool = { SteamBundle.gameIsRunning }

    func catalog() -> BridgeCatalog {
        BridgeCatalog.load(bundledRoot: bundledRoot, store: store.store, feed: feed, manifests: manifests)
    }

    /// Reads the signed list from Lullaby's releases into the cache. Nothing to do
    /// when the build has no release key.
    func refreshManifest() async throws {
        guard case .ready(let feed) = feed else { return }
        _ = try await SignedDocument.fetch(
            feed.bridgeManifestURL, feed: feed, transport: feed.transport(over: transport), cache: manifests,
            schema: BridgeCatalog.schema)
    }

    var engine: BridgeStore.EngineInfo? {
        BridgeStore.engineInfo(runners.appending(path: EngineStore.currentLink).resolvingSymlinksInPath())
    }

    var active: BridgeRelease? {
        guard let engine else { return nil }
        let catalog = catalog()
        let fitting = catalog.candidates(for: engine.version).filter { BridgeStore.mismatch($0, engine) == nil }
        return current(in: fitting)
    }

    /// The build state.json names, or, before anything wrote it (an install from
    /// before Phase 5), the one whose files lullaby/bridge already holds.
    func current(in fitting: [BridgeRelease]) -> BridgeRelease? {
        if let id = store.state.current { return fitting.first { $0.id == id } }
        return fitting.first { release in
            guard let root = release.root else { return false }
            return BridgePayload.entries.allSatisfy { entry in
                guard let file = release.files.first(where: { $0.name == entry.resource }),
                      let path = entry.bridgePaths.first
                else { return false }
                let have = Digest.sha256IfPresent(store.live.appending(path: path))
                return have != nil && have == Digest.sha256IfPresent(root.appending(path: file.path))
            }
        }
    }

    func check(refresh: Bool = true) async throws -> BridgeCheck {
        if refresh { try await refreshManifest() }
        let result = evaluate(catalog())
        AppLog.note("bridge: check → \(result.summary)")
        return result
    }

    func evaluate(_ catalog: BridgeCatalog) -> BridgeCheck {
        guard let engine else { return .noEngine }
        let fitting = catalog.candidates(for: engine.version).filter { BridgeStore.mismatch($0, engine) == nil }
        guard let best = fitting.first else { return .noBridge(engine: engine.version) }
        guard let current = current(in: fitting) else { return .available(best, current: nil) }
        return best.rev > current.rev ? .available(best, current: current) : .upToDate(current)
    }

    /// Download if needed, check, activate; keeps the build Roll Back returns to.
    func install(
        _ release: BridgeRelease, report: @escaping @Sendable (BridgePhase) -> Void = { _ in }
    ) async throws -> BridgeOutcome {
        let step = BridgeStore.step
        guard !gameIsRunning() else {
            AppLog.note("bridge: refused, a game is running")
            throw StepFailure(step: step, detail: EngineUpdater.gameRunning)
        }
        guard let engine else { throw StepFailure(step: step, detail: "No engine is installed.") }
        if let why = BridgeStore.mismatch(release, engine) {
            AppLog.note("bridge: refused \(release.id): \(why)")
            throw StepFailure(step: step, detail: why + " Lullaby did not change the bridge.")
        }
        report(.checking)
        var local = release
        switch release.origin {
        case .remote:
            guard case .ready(let feed) = feed else { throw StepFailure(step: step, detail: ReleaseFeed.noKey) }
            local = try await store.obtain(release, key: feed.key, transport: feed.transport(over: transport), report: report)
        case .packed:
            local = try await store.obtain(release, key: nil, transport: transport, report: report)
        case .bundled, .installed:
            break
        }
        report(.switching)
        // An install from before Phase 5 has no state.json yet: the build already in
        // lullaby/bridge becomes the one Roll Back returns to.
        if store.state.current == nil, let inferred = active {
            try store.save(.init(current: inferred.id, previous: nil))
        }
        let before = store.state.current
        try store.activate(local, engine: engine.root)
        prune()
        return BridgeOutcome(id: local.id, previous: before == local.id ? store.state.previous : before)
    }

    /// The previous build, when it is on disk and fits the active engine.
    var rollbackTarget: BridgeRelease? {
        guard let id = store.state.previous, let engine,
              let release = catalog().release(id: id), release.root != nil,
              BridgeStore.mismatch(release, engine) == nil
        else { return nil }
        return release
    }

    func rollback() throws -> BridgeOutcome {
        let step = Self.rollbackStep
        guard let target = rollbackTarget, let engine else {
            throw StepFailure(step: step, detail: "There is no previous Steam bridge for this engine to go back to.")
        }
        guard !gameIsRunning() else { throw StepFailure(step: step, detail: EngineUpdater.gameRunning) }
        let from = store.state.current
        try store.activate(target, engine: engine.root)
        AppLog.note("bridge: rolled back from \(from ?? "none") to \(target.id)")
        return BridgeOutcome(id: target.id, previous: from)
    }

    /// Keeps the active and previous builds and the one the previous engine needs.
    func prune() {
        var keep = Set([store.state.current, store.state.previous].compactMap { $0 })
        let previousEngine = runners.appending(path: EngineUpdater.previousLink).resolvingSymlinksInPath()
        if let info = BridgeStore.engineInfo(previousEngine),
           let fit = catalog().candidates(for: info.version).first(where: {
               $0.root != nil && BridgeStore.mismatch($0, info) == nil
           })
        {
            keep.insert(fit.id)
        }
        store.prune(keep: keep)
    }
}
