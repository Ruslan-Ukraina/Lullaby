// Installs, reinstalls and rolls back the Dormison engine (Phase 4).
//
// Install: signed engine.json → channel's release → is it supported (a Steam
// bridge for the version, BridgeCatalog: bundled, downloaded, or in NotProton's
// signed bridge-manifest.json) → tarball, resumed from a .part file → size,
// sha256 from the manifest and the tarball's own Ed25519 signature → the bridge
// downloaded and checked if it is not on disk (BridgeStore) → unpack beside the
// runners into .<version>.partial → every file against engine-manifest.json →
// commit is the bridge's → B1 ntdll.dll pair over the release's (the release's
// kept as .lullaby-orig) → smoke test in a throwaway prefix → Steam and games
// closed → switch → the live bridge follows the engine → prune to one previous
// engine.
//
// Layout under runners/:
//   current  -> dormison-<tag>             what games use
//   previous -> dormison-<tag> | .previous-dormison-<tag>
// A reinstall of the active version swaps the fresh tree into dormison-<tag>
// (renamex_np RENAME_SWAP, so the path games use never disappears) and keeps the
// old tree as .previous-dormison-<tag>. Rollback is the reverse move.

import CryptoKit
import Darwin
import Foundation
import Synchronization

enum EngineUpdateCheck: Sendable, Equatable {
    /// The channel offers what is installed. `supported`: Reinstall is possible.
    case upToDate(EngineRelease, supported: Bool)
    case available(EngineRelease)
    /// A newer Dormison is out, but this NotProton has no B1 ntdll or bridge for it.
    case waiting(EngineRelease, reason: String)
    /// The installed engine is newer than anything on the channel.
    case newerInstalled(EngineRelease)
    case nothingOnChannel(EngineChannel)
}

extension EngineUpdateCheck {
    /// One line for app.log and the headless command.
    var summary: String {
        switch self {
        case .upToDate(let release, let supported):
            "up to date with \(release.version) on \(release.channel.rawValue), reinstall \(supported ? "possible" : "not supported")"
        case .available(let release):
            "\(release.version) available on \(release.channel.rawValue), \(release.sizeBytes) bytes"
        case .waiting(let release, let reason):
            "\(release.version) is out, waiting for support: \(reason)"
        case .newerInstalled(let release):
            "installed engine is newer than \(release.version)"
        case .nothingOnChannel(let channel):
            "nothing on the \(channel.rawValue) channel"
        }
    }
}

enum EngineUpdatePhase: Sendable, Equatable {
    case checking
    case downloading(received: Int64, total: Int64)
    case verifying
    case unpacking
    case checkingFiles
    case patching
    case testing
    case bridge(BridgePhase)
    case stoppingSteam
    case switching
    case cleaning

    var label: String {
        switch self {
        case .checking: "Checking for engine updates"
        case .downloading(let received, let total):
            "Downloading the engine (\(Self.megabytes(received)) of \(Self.megabytes(total)))"
        case .verifying: "Verifying the download"
        case .unpacking: "Unpacking the engine"
        case .checkingFiles: "Checking the engine's files"
        case .patching: "Adding the Steam loader patch"
        case .testing: "Testing the engine"
        case .bridge(let phase): phase.label
        case .stoppingSteam: "Stopping Steam"
        case .switching: "Switching engines"
        case .cleaning: "Cleaning up"
        }
    }

    private static func megabytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct EngineUpdateOutcome: Sendable, Equatable {
    let version: String
    let previous: String?
    let reinstalled: Bool
    let stoppedSteam: Bool
    let smoke: String
}

/// A downloaded, checked, patched and tested engine waiting for the switch.
struct EnginePrepared: Sendable, Equatable {
    let release: EngineRelease
    let partial: URL
    let smoke: String
}

struct EngineRollbackOutcome: Sendable, Equatable {
    let from: String
    let to: String
    let stoppedSteam: Bool
}

struct EngineUpdater: Sendable {
    static let step = "Update the engine"
    static let rollbackStep = "Roll back the engine"
    static let previousLink = "previous"
    static let asidePrefix = ".previous-"

    var runners: URL = SupportPaths.runners
    var cache: URL = SupportPaths.engineDownloads
    var bridge: URL = SupportPaths.bridge
    /// Downloaded Steam bridge builds (BridgeStore).
    var bridges: URL = SupportPaths.bridges
    var manifestURL: URL = EngineManifest.url
    var key: Curve25519.Signing.PublicKey = EngineSignature.dormisonKey
    var transport: any EngineTransport = URLSessionEngineTransport()
    /// NotProton's own releases: the key bridge downloads are checked with.
    var feed: ReleaseFeed.Setup = ReleaseFeed.configured
    var support: @Sendable () throws -> BridgeCatalog = { BridgeUpdater().catalog() }
    /// Reads the signed bridge list before a check, so a new engine's bridge is known.
    var refreshBridges: @Sendable () async -> Void = {
        do { try await BridgeUpdater().refreshManifest() } catch {
            AppLog.note("engine: bridge list not refreshed: \(error.localizedDescription)")
        }
    }
    var gameIsRunning: @Sendable () -> Bool = { SteamBundle.gameIsRunning }
    var steamIsRunning: @Sendable () -> Bool = { SteamBundle.isRunning }
    var quitSteam: @Sendable () throws -> Bool = { try SteamBundle.quitClient() }
    var smokeTest: @Sendable (URL) throws -> String = { try EngineSmokeTest.run(engine: $0) }
    var freeSpace: @Sendable (URL) -> Int64? = EngineUpdater.availableCapacity

    static let gameRunning =
        "A game is running under NotProton. Quit the game, then try again."
    static let steamRunning =
        "Steam is running. Quit Steam, then try again."
    static let offline =
        "NotProton could not reach GitHub. Check your internet connection and try again."

    // MARK: Check

    func fetchManifest() async throws -> EngineManifest {
        let body: Data, signature: Data
        do {
            body = try await transport.fetch(manifestURL, limit: 1 << 20)
            signature = try await transport.fetch(EngineSignature.signatureURL(for: manifestURL), limit: 1024)
        } catch {
            AppLog.note("engine: manifest fetch failed: \(error.localizedDescription)")
            throw StepFailure(step: EngineManifest.step, detail: Self.offline)
        }
        let manifest = try EngineManifest.verified(body, signatureFile: signature, key: key)
        AppLog.note("engine: manifest verified, "
            + manifest.releases.values.sorted { $0.channel.rawValue < $1.channel.rawValue }
                .map { "\($0.channel.rawValue)=\($0.version)" }.joined(separator: " "))
        return manifest
    }

    var bridgeStore: BridgeStore {
        BridgeStore(store: bridges, live: bridge, downloads: cache.appending(path: "bridge"))
    }

    func check(channel: EngineChannel) async throws -> EngineUpdateCheck {
        let manifest = try await fetchManifest()
        await refreshBridges()
        let result = try evaluate(manifest, channel: channel)
        AppLog.note("engine: check channel=\(channel.rawValue) installed=\(installedVersion ?? "none") → \(result.summary)")
        return result
    }

    func evaluate(_ manifest: EngineManifest, channel: EngineChannel) throws -> EngineUpdateCheck {
        let catalog = try support()
        let installed = installedVersion
        // Dormison's newest release may have no bridge yet; meanwhile the newest engine
        // that has one is taken, when it is newer than what is installed (DECISIONS P8-17).
        let fallback = catalog.newestDownloadableEngine(on: channel).flatMap { found in
            installed.map { EngineManifest.isOlder($0, than: found.version) } ?? true ? found : nil
        }
        guard let release = manifest.release(for: channel) else {
            return fallback.map(EngineUpdateCheck.available) ?? .nothingOnChannel(channel)
        }
        let verdict = catalog.verdict(for: release.version)
        if let installed {
            if installed == release.version {
                if case .supported = verdict { return .upToDate(release, supported: true) }
                return .upToDate(release, supported: false)
            }
            if EngineManifest.isOlder(release.version, than: installed) { return .newerInstalled(release) }
        }
        switch verdict {
        case .supported: return .available(release)
        case .waiting(let reason):
            if let fallback, EngineManifest.isOlder(fallback.version, than: release.version) {
                AppLog.note("engine: \(release.version) has no Steam bridge yet, taking \(fallback.version), the newest that has")
                return .available(fallback)
            }
            return .waiting(release, reason: reason)
        }
    }

    var installedVersion: String? {
        guard let tag = EngineStore.currentTag(runners: runners) else { return nil }
        return DormisonEngine(root: runners.appending(path: tag)).isUsable ? tag : nil
    }

    // MARK: Install

    /// Prepare and switch in one go. `mayQuitSteam`: the person agreed beforehand to
    /// close Steam for the switch (the headless command's --quit-steam); without it a
    /// running Steam refuses the update before anything is downloaded.
    func install(
        _ release: EngineRelease,
        mayQuitSteam: Bool,
        report: @escaping @Sendable (EngineUpdatePhase) -> Void = { _ in }
    ) async throws -> EngineUpdateOutcome {
        guard mayQuitSteam || !steamIsRunning() else {
            AppLog.note("engine: refused, Steam is running")
            throw StepFailure(step: Self.step, detail: Self.steamRunning)
        }
        let prepared = try await prepare(release, report: report)
        do {
            return try activatePrepared(prepared, mayQuitSteam: mayQuitSteam, report: report)
        } catch {
            if !(error is SteamBundle.StillRunning) { discard(prepared) }
            throw error
        }
    }

    /// Everything that can happen while Steam stays open: the download, every check,
    /// the B1 patch and the smoke test. The result is a complete engine tree beside
    /// the runners, ready for activatePrepared, which is quick.
    func prepare(
        _ release: EngineRelease,
        report: @escaping @Sendable (EngineUpdatePhase) -> Void = { _ in }
    ) async throws -> EnginePrepared {
        let step = Self.step
        let version = release.version
        AppLog.note("engine: install begin \(version) channel=\(release.channel.rawValue) "
            + "minAppVersion=\(release.minAppVersion ?? "none")")
        guard EngineManifest.isVersionName(version), EngineSignature.isDormisonAsset(release.url) else {
            throw StepFailure(step: step, detail: "\(release.url.absoluteString) is not a Dormison release.")
        }
        guard !gameIsRunning() else {
            AppLog.note("engine: refused, a game is running")
            throw StepFailure(step: step, detail: Self.gameRunning)
        }
        report(.checking)
        guard case .supported(var bridgeRelease) = try support().verdict(for: version) else {
            throw StepFailure(
                step: step,
                detail: "\(release.displayName) is out, but NotProton does not support it yet. Wait for a NotProton update.")
        }
        let fm = FileManager.default
        try fm.createDirectory(at: runners, withIntermediateDirectories: true)
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        if let free = freeSpace(runners), free < release.sizeBytes * 7 {
            throw StepFailure(
                step: step,
                detail: "Not enough free disk space: the engine needs about "
                    + ByteCountFormatter.string(fromByteCount: release.sizeBytes * 7, countStyle: .file) + ".")
        }

        let tarball = try await obtainTarball(release, report: report)

        switch bridgeRelease.origin {
        case .remote:
            guard case .ready(let feed) = feed else {
                throw StepFailure(step: step, detail: ReleaseFeed.noKey)
            }
            bridgeRelease = try await bridgeStore.obtain(
                bridgeRelease, key: feed.key, transport: transport, report: { report(.bridge($0)) })
        case .packed:
            bridgeRelease = try await bridgeStore.obtain(
                bridgeRelease, key: nil, transport: transport, report: { report(.bridge($0)) })
        case .bundled, .installed:
            break
        }
        let entry = bridgeRelease

        let partial = runners.appending(path: ".\(version).partial")
        try removeIfPresent(partial)
        do {
            report(.unpacking)
            try fm.createDirectory(at: partial, withIntermediateDirectories: true)
            try Shell.check("/usr/bin/tar", [
                "-xJf", tarball.path(percentEncoded: false), "-C", partial.path(percentEncoded: false),
                "--strip-components", "1", "\(version)/",
            ])

            report(.checkingFiles)
            let commit = try EngineFiles.verify(root: partial, version: version)
            guard commit.lowercased() == entry.engineCommit else {
                throw StepFailure(
                    step: step,
                    detail: "\(release.displayName) was built from \(commit.prefix(12)), "
                        + "but NotProton's Steam bridge is for \(entry.engineCommit.prefix(12)).")
            }
            AppLog.note("engine: \(version) files match engine-manifest.json, commit \(commit.prefix(12))")

            report(.patching)
            try BridgeStore.applyB1(entry, to: partial)

            report(.testing)
            let smoke = try smokeTest(partial)
            AppLog.note("engine: smoke test passed: \(smoke)")
            AppLog.note("engine: \(version) prepared in \(partial.lastPathComponent)")
            return EnginePrepared(release: release, partial: partial, smoke: smoke)
        } catch {
            AppLog.note("engine: install of \(version) failed: \(error.localizedDescription)")
            try? removeIfPresent(partial)
            throw error
        }
    }

    /// The switch: a game refuses it; a running Steam is closed (the soft way) only
    /// with `mayQuitSteam`. When Steam will not quit (StillRunning) the prepared tree
    /// is kept, so Retry switches without downloading again; any other failure drops it.
    func activatePrepared(
        _ prepared: EnginePrepared,
        mayQuitSteam: Bool,
        report: @escaping @Sendable (EngineUpdatePhase) -> Void = { _ in }
    ) throws -> EngineUpdateOutcome {
        let step = Self.step
        let fm = FileManager.default
        let version = prepared.release.version
        guard DormisonEngine(root: prepared.partial).isUsable else {
            throw StepFailure(step: step, detail: "The prepared engine is gone. Update again.")
        }
        guard !gameIsRunning() else {
            AppLog.note("engine: switch refused, a game is running")
            throw StepFailure(step: step, detail: Self.gameRunning)
        }
        var stopped = false
        if steamIsRunning() {
            guard mayQuitSteam else { throw StepFailure(step: step, detail: Self.steamRunning) }
            report(.stoppingSteam)
            AppLog.note("engine: closing Steam to switch to \(version)")
            stopped = try quitSteam()
        }
        do {
            report(.switching)
            let switched = try activate(partial: prepared.partial, version: version)
            report(.cleaning)
            prune()
            BridgeUpdater(store: bridgeStore, runners: runners, feed: feed, bundledRoot: nil).prune()
            // The tarball, its signature, and parts of downloads that were given up.
            for name in (try? fm.contentsOfDirectory(atPath: cache.path(percentEncoded: false))) ?? [] {
                try? fm.removeItem(at: cache.appending(path: name))
            }
            AppLog.note("engine: installed \(version)\(switched.reinstalled ? " (reinstall)" : "") "
                + "previous=\(switched.previous ?? "none") stoppedSteam=\(stopped)")
            return EngineUpdateOutcome(
                version: version, previous: switched.previous, reinstalled: switched.reinstalled,
                stoppedSteam: stopped, smoke: prepared.smoke)
        } catch {
            AppLog.note("engine: switch to \(version) failed: \(error.localizedDescription)")
            discard(prepared)
            throw error
        }
    }

    /// Drops a prepared tree that will not be switched to.
    func discard(_ prepared: EnginePrepared) {
        guard prepared.partial.lastPathComponent.hasSuffix(".partial"),
              prepared.partial.deletingLastPathComponent().standardizedFileURL == runners.standardizedFileURL
        else { return }
        try? removeIfPresent(prepared.partial)
        AppLog.note("engine: prepared \(prepared.release.version) discarded")
    }

    private func signatureFile(for tarball: URL) -> URL {
        tarball.deletingLastPathComponent().appending(path: tarball.lastPathComponent + ".sig")
    }

    /// The verified tarball in the cache. A complete earlier download is reused;
    /// a cut-short one is continued; a corrupt one is thrown away.
    func obtainTarball(
        _ release: EngineRelease, report: @escaping @Sendable (EngineUpdatePhase) -> Void
    ) async throws -> URL {
        let step = Self.step
        let fm = FileManager.default
        let name = release.url.lastPathComponent
        let tarball = cache.appending(path: name)
        let part = cache.appending(path: name + ".part")
        let total = release.sizeBytes

        if size(of: tarball) != total || Digest.sha256IfPresent(tarball) != release.sha256 {
            try removeIfPresent(tarball)
            if size(of: part) > total { try removeIfPresent(part) }
            let already = size(of: part)
            if already < total {
                AppLog.note("engine: downloading \(name)\(already > 0 ? " from byte \(already)" : "")")
                report(.downloading(received: already, total: total))
                // About one report per percent, not one per network packet.
                let reported = Mutex<Int64>(already)
                let stride = max(total / 100, 1 << 20)
                do {
                    try await transport.download(release.url, to: part, size: total) { received in
                        let due = reported.withLock { last in
                            guard received - last >= stride || received == total else { return false }
                            last = received
                            return true
                        }
                        if due { report(.downloading(received: received, total: total)) }
                    }
                } catch {
                    AppLog.note("engine: download stopped at \(size(of: part)) of \(total): \(error.localizedDescription)")
                    throw StepFailure(
                        step: step,
                        detail: "The download stopped. " + Self.offline
                            + " What arrived is kept, and the next try continues from there.")
                }
            }
            report(.verifying)
            let got = size(of: part)
            guard got == total else {
                if got > total { try removeIfPresent(part) }
                throw StepFailure(
                    step: step, detail: "The download is \(got) bytes, the engine list says \(total). Try again.")
            }
            let digest = try Digest.sha256(of: part)
            guard digest == release.sha256 else {
                try removeIfPresent(part)
                AppLog.note("engine: \(name) sha256 \(digest), manifest \(release.sha256)")
                throw StepFailure(
                    step: step,
                    detail: "The downloaded engine does not match the engine list (sha256), so NotProton deleted it.")
            }
            try fm.moveItem(at: part, to: tarball)
        }

        report(.verifying)
        let signature: Data
        do {
            signature = try await transport.fetch(EngineSignature.signatureURL(for: release.url), limit: 1024)
        } catch {
            throw StepFailure(step: step, detail: Self.offline)
        }
        let bytes = try Data(contentsOf: tarball, options: .mappedIfSafe)
        guard EngineSignature.isValid(bytes, signatureFile: signature, key: key) else {
            try removeIfPresent(tarball)
            AppLog.note("engine: \(name) signature invalid")
            throw StepFailure(
                step: step,
                detail: "The downloaded engine does not carry Dormison's signature, so NotProton deleted it.")
        }
        try signature.write(to: signatureFile(for: tarball))
        AppLog.note("engine: \(name) verified (size, sha256, signature)")
        return tarball
    }

    // MARK: Switching

    struct Switched: Equatable {
        let previous: String?
        let reinstalled: Bool
    }

    /// Moves a checked tree into place and points `current` and `previous`.
    func activate(partial: URL, version: String) throws -> Switched {
        let step = Self.step
        let fm = FileManager.default
        let current = EngineStore.currentTag(runners: runners)
        let destination = runners.appending(path: version)
        let exists = fm.fileExists(atPath: destination.path(percentEncoded: false))

        var previous: String?
        var reinstalled = false
        if !exists {
            try renameOrThrow(partial, destination, step: step)
            if let current, current != version { previous = current }
            try EngineStore.pointLink(EngineStore.currentLink, at: version, in: runners)
        } else if current == version {
            // The active tree is swapped, never removed: games keep a valid path.
            try swap(partial, destination, step: step)
            let aside = runners.appending(path: Self.asidePrefix + version)
            try removeIfPresent(aside)
            try renameOrThrow(partial, aside, step: step)
            previous = aside.lastPathComponent
            reinstalled = true
        } else {
            let replaced = runners.appending(path: ".\(version).replaced")
            try removeIfPresent(replaced)
            try renameOrThrow(destination, replaced, step: step)
            try renameOrThrow(partial, destination, step: step)
            try removeIfPresent(replaced)
            previous = current
            try EngineStore.pointLink(EngineStore.currentLink, at: version, in: runners)
        }
        if let previous {
            try EngineStore.pointLink(Self.previousLink, at: previous, in: runners)
        }
        afterSwitch()
        return Switched(previous: previous, reinstalled: reinstalled)
    }

    /// What Rollback would switch to: the version name, or nil when there is nothing.
    var rollbackTarget: String? {
        guard let target = previousTarget, let current = EngineStore.currentTag(runners: runners) else { return nil }
        guard DormisonEngine(root: runners.appending(path: target)).isUsable else { return nil }
        if target.hasPrefix(Self.asidePrefix) {
            return target == Self.asidePrefix + current ? current : nil
        }
        return target.hasPrefix(EngineStore.prefix) && target != current ? target : nil
    }

    var previousTarget: String? {
        try? FileManager.default.destinationOfSymbolicLink(
            atPath: runners.appending(path: Self.previousLink).path(percentEncoded: false))
    }

    func rollback(
        mayQuitSteam: Bool, report: @escaping @Sendable (EngineUpdatePhase) -> Void = { _ in }
    ) throws -> EngineRollbackOutcome {
        let step = Self.rollbackStep
        guard let current = EngineStore.currentTag(runners: runners), rollbackTarget != nil,
              let target = previousTarget
        else { throw StepFailure(step: step, detail: "There is no previous engine to go back to.") }
        guard !gameIsRunning() else { throw StepFailure(step: step, detail: Self.gameRunning) }
        var stopped = false
        if steamIsRunning() {
            guard mayQuitSteam else { throw StepFailure(step: step, detail: Self.steamRunning) }
            report(.stoppingSteam)
            stopped = try quitSteam()
        }
        report(.switching)
        let to: String
        if target.hasPrefix(Self.asidePrefix) {
            // Same version: swap the trees, `previous` keeps naming the other one.
            try swap(runners.appending(path: target), runners.appending(path: current), step: step)
            to = current + " (the other copy from the last reinstall)"
        } else {
            try EngineStore.pointLink(EngineStore.currentLink, at: target, in: runners)
            try EngineStore.pointLink(Self.previousLink, at: current, in: runners)
            to = target
        }
        afterSwitch()
        AppLog.note("engine: rolled back from \(current) to \(to)")
        return EngineRollbackOutcome(from: current, to: to, stoppedSteam: stopped)
    }

    /// The env file compat_run.sh reads, the Steam bridge (lsteamclient, steam.exe
    /// and the B1 pair) and the bridge's copy of the B1 ntdll it compares the engine
    /// against, all follow the active engine.
    func afterSwitch() {
        let engine = DormisonEngine(root: runners.appending(path: EngineStore.currentLink))
        engine.ensureEnvironmentFile()
        let root = engine.root.resolvingSymlinksInPath()
        if let catalog = try? support() { bridgeStore.follow(engine: root, catalog: catalog) }
        EngineUpdater.syncBridgeNtdll(engine: root, bridge: bridge)
    }

    static func syncBridgeNtdll(engine: URL, bridge: URL) {
        let fm = FileManager.default
        for arch in ["x86_64", "i386"] {
            let live = engine.appending(path: "wine/lib/wine/\(arch)-windows/ntdll.dll")
            let copy = bridge.appending(path: "wine/\(arch)-windows/ntdll.dll")
            guard EngineSupport.carriesB1(live) else {
                // compat_run.sh then logs that this arch has no patched ntdll, which is true.
                try? fm.removeItem(at: copy)
                AppLog.note("engine: \(arch) ntdll.dll has no B1 hook, bridge copy removed")
                continue
            }
            if Digest.sha256IfPresent(copy) == Digest.sha256IfPresent(live) { continue }
            do {
                try fm.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
                let staging = copy.deletingLastPathComponent().appending(path: ".ntdll.dll.new")
                try? fm.removeItem(at: staging)
                try fm.copyItem(at: live, to: staging)
                if rename(staging.path(percentEncoded: false), copy.path(percentEncoded: false)) != 0 {
                    try? fm.removeItem(at: staging)
                }
                AppLog.note("engine: bridge copy of \(arch) ntdll.dll updated")
            } catch {
                AppLog.note("engine: could not update the bridge copy of \(arch) ntdll.dll: \(error.localizedDescription)")
            }
        }
    }

    /// Keeps `current`, `previous` and what they point at; removes other engines,
    /// set-aside trees and leftovers of interrupted runs.
    func prune() {
        let fm = FileManager.default
        let keep = Set([EngineStore.currentTag(runners: runners), previousTarget].compactMap { $0 })
        let entries = (try? fm.contentsOfDirectory(atPath: runners.path(percentEncoded: false))) ?? []
        for name in entries where !keep.contains(name) {
            let ours = name.hasPrefix(EngineStore.prefix) || name.hasPrefix(Self.asidePrefix + EngineStore.prefix)
                || (name.hasPrefix(".") && (name.hasSuffix(".partial") || name.hasSuffix(".replaced")))
            guard ours, !name.contains("/") else { continue }
            do {
                try fm.removeItem(at: runners.appending(path: name))
                AppLog.note("engine: removed runners/\(name)")
            } catch {
                AppLog.note("engine: could not remove runners/\(name): \(error.localizedDescription)")
            }
        }
    }

    // MARK: Helpers

    private func swap(_ a: URL, _ b: URL, step: String) throws {
        if renamex_np(a.path(percentEncoded: false), b.path(percentEncoded: false), UInt32(RENAME_SWAP)) != 0 {
            throw StepFailure(step: step, detail: "Could not swap engine folders. \(String(cString: strerror(errno)))")
        }
    }

    private func renameOrThrow(_ from: URL, _ to: URL, step: String) throws {
        if rename(from.path(percentEncoded: false), to.path(percentEncoded: false)) != 0 {
            throw StepFailure(
                step: step,
                detail: "Could not move \(from.lastPathComponent) to \(to.lastPathComponent). \(String(cString: strerror(errno)))")
        }
    }

    private func removeIfPresent(_ url: URL) throws {
        let path = url.path(percentEncoded: false)
        guard (try? FileManager.default.attributesOfItem(atPath: path)) != nil else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func size(of url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.size] as? NSNumber)?
            .int64Value ?? 0
    }

    static func availableCapacity(_ url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }
}

/// An unpacked release checked against its own engine-manifest.json: every
/// listed file has its digest, every listed link its target, nothing extra.
enum EngineFiles {
    static let step = "Check the engine's files"

    /// Returns the commit the release was built from.
    static func verify(root: URL, version: String) throws -> String {
        let fail = { (why: String) in StepFailure(step: step, detail: why) }
        func json(_ name: String) throws -> [String: Any] {
            guard let data = try? Data(contentsOf: root.appending(path: name)),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { throw fail("The engine has no readable \(name).") }
            return object
        }
        let manifest = try json("engine-manifest.json")
        let info = try json("engine-info.json")
        let source = manifest["source"] as? [String: Any] ?? [:]
        guard manifest["version"] as? String == version, info["version"] as? String == version else {
            throw fail("The engine's files name another version than \(version).")
        }
        guard source["dirty"] as? Bool != true else { throw fail("The engine was built from a modified source tree.") }
        guard let commit = source["head"] as? String, info["commit"] as? String == commit else {
            throw fail("engine-info.json and engine-manifest.json name different commits.")
        }

        let components = manifest["components"] as? [[String: Any]] ?? []
        guard !components.isEmpty else { throw fail("engine-manifest.json lists no files.") }
        let fm = FileManager.default
        let base = root.resolvingSymlinksInPath()
        var listed: Set<String> = ["engine-manifest.json"]
        var files: [(path: String, sha: String)] = []
        var problems: [String] = []
        for component in components {
            guard let path = component["path"] as? String, EngineSupport.isSafeRelative(path) else {
                throw fail("engine-manifest.json lists an unsafe path.")
            }
            listed.insert(path)
            let full = base.appending(path: path).path(percentEncoded: false)
            if let link = component["link"] as? String {
                if (try? fm.destinationOfSymbolicLink(atPath: full)) != link {
                    problems.append("\(path): expected a link to \(link)")
                }
            } else if let sha = component["sha256"] as? String {
                files.append((path, sha.lowercased()))
            } else {
                problems.append("\(path): no digest")
            }
        }

        let mismatched = Mutex<[String]>([])
        DispatchQueue.concurrentPerform(iterations: files.count) { index in
            let (path, want) = files[index]
            let url = base.appending(path: path)
            let attributes = try? fm.attributesOfItem(atPath: url.path(percentEncoded: false))
            let problem: String?
            if attributes?[.type] as? FileAttributeType != .typeRegular {
                problem = "\(path): missing"
            } else if let got = try? Digest.sha256(of: url), got == want {
                problem = nil
            } else {
                problem = "\(path): sha256 differs"
            }
            if let problem { mismatched.withLock { $0.append(problem) } }
        }
        problems += mismatched.withLock { $0 }.sorted()

        // Paths relative to the root, so /var and /private/var cannot disagree.
        if let walker = fm.enumerator(atPath: base.path(percentEncoded: false)) {
            while let relative = walker.nextObject() as? String {
                let type = walker.fileAttributes?[.type] as? FileAttributeType
                if type == .typeSymbolicLink { walker.skipDescendants() }
                if type == .typeDirectory { continue }
                if !listed.contains(relative) { problems.append("\(relative): not in engine-manifest.json") }
            }
        }

        guard problems.isEmpty else {
            AppLog.note("engine: \(problems.count) file problem(s): " + problems.prefix(10).joined(separator: "; "))
            throw fail("\(problems.count) file(s) of the engine do not match its manifest, for example \(problems[0]).")
        }
        return commit
    }
}
