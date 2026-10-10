// The real steps of the main window's flows (ROADMAP §9.2–9.3), built from the same
// updaters Status used: EngineUpdater, BridgeUpdater, SignatureUpdater, SteamInstaller,
// Uninstall. Tests run the flows with stand-in steps; these are the ones the app runs.

import Foundation
import LullabySettings

/// What Update has to do, found when the window opens (ROADMAP §9.5).
struct UpdatePlan: Equatable, Sendable {
    var engine: EngineRelease?
    var bridge: BridgeRelease?
    var steamPatch = false
    /// NotProton.app's newer version, as Sparkle names it.
    var app: String?

    var isEmpty: Bool { engine == nil && bridge == nil && !steamPatch && app == nil }

    /// The parts for the status line, in the order Update installs them.
    var parts: [String] {
        var parts: [String] = []
        if let engine { parts.append(EngineStore.displayName(engine.version)) }
        if bridge != nil { parts.append(tr("Steam bridge")) }
        if steamPatch { parts.append(tr("Steam patch")) }
        if let app { parts.append("NotProton \(app)") }
        return parts
    }

    /// Engine switches and the Steam patch close Steam.
    var closesSteam: Bool { engine != nil || steamPatch }
}

/// The updaters the steps use. The window uses the real ones; `--release update` and
/// `--release onboarding` hand in ones pointed at a scratch tree and a test feed.
struct SetupEnvironment: Sendable {
    var engine = EngineUpdater()
    var bridge = BridgeUpdater()
    var signatures = SignatureUpdater()
    var gate = SteamUpdateGate()

    static var live: SetupEnvironment { SetupEnvironment() }
}

enum SetupSteps {

    // MARK: Install and Update (onboarding)

    /// Install and Update are one flow (owner's edit to Phase 8): every part is checked
    /// and put in place or updated, whatever is already current is left alone.
    static func setup(_ plan: UpdatePlan? = nil, _ env: SetupEnvironment = .live) -> [FlowStep] {
        var steps = [rosetta(), engine(plan?.engine, env), bridge(env), signatures(env), steam(force: false)]
        if plan?.app != nil { steps.append(app()) }
        return steps
    }

    static func reinstall() -> [FlowStep] {
        [engine(), bridge(), signatures(), steam(force: true)]
    }

    static func rosetta() -> FlowStep {
        FlowStep(.rosetta, tr("Checking Rosetta")) { _ in try await Rosetta.ensure() }
    }

    /// Installs the engine when there is none; with a release, switches to it.
    static func engine(_ wanted: EngineRelease? = nil, _ env: SetupEnvironment = .live) -> FlowStep {
        FlowStep(.engine, tr("Downloading the engine")) { detail in
            let updater = env.engine
            let release: EngineRelease
            if let wanted {
                release = wanted
            } else {
                if updater.installedVersion != nil { return }
                switch try await updater.check(channel: EngineChannel.preferred) {
                case .available(let found), .upToDate(let found, true):
                    release = found
                case .waiting(let found, let reason):
                    throw KnownProblem(.engineNotSupportedYet, log: "\(found.version): \(reason)")
                case let other:
                    throw StepFailure(step: EngineUpdater.step, detail: other.summary)
                }
            }
            let prepared = try await updater.prepare(release) { detail(progressText($0)) }
            _ = try updater.activatePrepared(prepared, mayQuitSteam: true) { detail(progressText($0)) }
        }
    }

    static func bridge(_ env: SetupEnvironment = .live) -> FlowStep {
        FlowStep(.bridge, tr("Installing the Steam bridge")) { detail in
            let updater = env.bridge
            let check: BridgeCheck
            do {
                check = try await updater.check()
            } catch {
                // Without a release feed (a local build) the bridge inside the app is the one.
                guard case .off = updater.feed else { throw error }
                check = updater.evaluate(updater.catalog())
            }
            switch check {
            case .available(let release, _):
                _ = try await updater.install(release) { detail(progressText($0)) }
            case .upToDate:
                return
            case .noBridge(let engine):
                throw KnownProblem(.noBridgeYet, log: "no Steam bridge for \(engine)")
            case .noEngine:
                throw StepFailure(step: BridgeStore.step, detail: "No engine is installed.")
            }
        }
    }

    static func signatures(_ env: SetupEnvironment = .live) -> FlowStep {
        FlowStep(.signatures, tr("Getting Steam support files")) { _ in
            let outcome = try await env.signatures.update()
            if !outcome.installed.isEmpty {
                AppLog.note("updates: new signature databases \(outcome.installed.joined(separator: " "))")
            }
            _ = await env.gate.evaluate()
        }
    }

    static func steam(force: Bool) -> FlowStep {
        FlowStep(.steam, tr("Installing into Steam")) { detail in
            guard FileManager.default.fileExists(atPath: SupportPaths.Steam.app.path(percentEncoded: false)) else {
                throw KnownProblem(.steamMissing, log: "/Applications/Steam.app is missing")
            }
            if !force, await Task.detached(priority: .userInitiated, operation: { isCurrentInSteam() }).value {
                AppLog.note("install: Steam already has this NotProton, left alone")
                return
            }
            let result = try await Task.detached(priority: .userInitiated) {
                try SteamInstaller.run(force: force, report: { phase in
                    if case .stoppingClient = phase { detail(tr("Closing Steam")) }
                })
            }.value
            AppLog.note("install: done, build \(result.build ?? "?"), Steam stopped \(result.stoppedClient)")
            let missing = await Task.detached(priority: .userInitiated) { () -> Bool in
                SteamHelperFiles.sync()
                return PayloadInspector.inspect().missing.contains { $0.origin.isFetchable }
            }.value
            if missing {
                detail(tr("Downloading Valve's files"))
                _ = try await ValveFetcher.run()
            }
        }
    }

    /// Steam.app carries this app's patch, unchanged, and this account has every part.
    static func isCurrentInSteam() -> Bool {
        let patch = PatchComparison.inspect()
        guard case .installed = SteamBundle.deployment(bundledVersion: AppVersion.bundled, stale: patch?.stale ?? [])
        else { return false }
        return PayloadInspector.inspect().isComplete
    }

    static func app() -> FlowStep {
        FlowStep(.app, tr("Updating NotProton")) { _ in
            // Sparkle shows its own window, downloads, and asks to relaunch.
            await MainActor.run { AppUpdater.shared.check() }
        }
    }

    // MARK: Delete (ROADMAP §9.3)

    static func delete() -> [FlowStep] {
        [
            FlowStep(.removeSteam, tr("Returning Steam to how it was")) { _ in
                let result = try await Uninstall.run(directories: [])
                guard result.restoredValveSignature else {
                    throw StepFailure(step: Uninstall.step, detail: "Steam's own files could not be restored.")
                }
            },
            FlowStep(.removeFiles, tr("Deleting the engine and the Steam bridge")) { _ in
                try await Task.detached(priority: .userInitiated) {
                    try Deletion.removeFiles(Deletion.targets())
                }.value
            },
        ]
    }

    // MARK: ⚙︎

    static func addToolkit(_ image: URL) -> [FlowStep] {
        [FlowStep(.toolkit, tr("Adding the Game Porting Toolkit")) { _ in
            let (status, error) = await Task.detached(priority: .userInitiated) { () -> (Int32, String) in
                let result = SettingsCLI().run(["toolkit", "add", image.path(percentEncoded: false)])
                return (result.status, result.error)
            }.value
            guard status == 0 else {
                if error.contains("evaluation environment") {
                    throw KnownProblem(.toolkitNotFound, log: error)
                }
                throw StepFailure(step: "Add Game Porting Toolkit", detail: error)
            }
        }]
    }

    static func steamUpdates(off: Bool) -> [FlowStep] {
        [FlowStep(.steamUpdates, off ? tr("Turning off Steam updates") : tr("Turning on Steam updates")) { _ in
            _ = try await Task.detached(priority: .userInitiated) { () -> SteamGateDecision in
                let gate = SteamUpdateGate()
                try gate.setMode(off ? .manual : .auto)
                return await gate.evaluate()
            }.value
        }]
    }

    // MARK: Progress

    static func progressText(_ phase: EngineUpdatePhase) -> String {
        switch phase {
        case .downloading(let received, let total): downloaded(received, of: total)
        case .bridge(let inner): progressText(inner)
        case .stoppingSteam: tr("Closing Steam")
        case .testing: tr("Testing the engine")
        default: ""
        }
    }

    static func progressText(_ phase: BridgePhase) -> String {
        if case .downloading(let received, let total) = phase { return downloaded(received, of: total) }
        return ""
    }

    static func downloaded(_ received: Int64, of total: Int64) -> String {
        guard received > 0 else { return "" }
        // Sizes in the window's language, not the region's: "10 MB of 240 MB" in English.
        let language = Bundle.module.preferredLocalizations.first ?? "en"
        let style = ByteCountFormatStyle(style: .file, locale: Locale(identifier: language))
        let done = received.formatted(style)
        guard total > 0 else { return tr("Downloaded \(done)") }
        return tr("Downloaded \(done) of \(total.formatted(style))")
    }
}

/// Delete keeps what a player made or added (owner's edit to Phase 8): game settings, the
/// Game Porting Toolkit, Steam's backups and the logs. Prefixes and their backups are in
/// Steam's libraries, not here, and Delete never touches them.
enum Deletion {
    static let kept: Set<String> = ["settings", "d3dmetal", "backups"]

    static func isKept(_ name: String) -> Bool {
        kept.contains(name) || name.hasSuffix(".log")
    }

    static func targets(
        support: URL = SupportPaths.support,
        caches: URL = SupportPaths.engineDownloads.deletingLastPathComponent()
    ) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: support.path(percentEncoded: false))) ?? []
        return names.sorted().filter { !isKept($0) }.map { support.appending(path: $0) } + [caches]
    }

    static func removeFiles(_ targets: [URL]) throws {
        let files = FileManager.default
        for target in targets {
            let path = target.path(percentEncoded: false)
            // A dangling link is not "there" for fileExists, but still has to go.
            guard (try? files.attributesOfItem(atPath: path)) != nil else { continue }
            try WriteRefused.catching(path) { try files.removeItem(at: target) }
            AppLog.note("delete: removed \(path)")
        }
    }
}
