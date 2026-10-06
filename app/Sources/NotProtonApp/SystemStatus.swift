// Logic behind Status view

import AppKit
import Foundation
import Observation

enum AppVersion {
    static let fallback = "0.1.0-dev"

    static var bundled: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallback
    }
}

struct StatusSnapshot: Sendable {
    var steam: SteamDeployment
    var steamRunning: Bool
    var updateBlocked: Bool
    var runner: EngineState
    var payload: PayloadState
    var installedEngines: [InstalledEngine] = []
    var patch: InstalledPatch?

    static func capture(bundledVersion: String) -> StatusSnapshot {
        let patch = PatchComparison.inspect()
        return StatusSnapshot(
            steam: SteamBundle.deployment(bundledVersion: bundledVersion, stale: patch?.stale ?? []),
            steamRunning: SteamBundle.isRunning,
            updateBlocked: UpdateBlock.isPresent(),
            runner: EngineStore.state(),
            payload: PayloadInspector.inspect(),
            installedEngines: EngineStore.installed(),
            patch: patch
        )
    }
}

@MainActor
@Observable
final class SystemStatus {

    var snapshot: StatusSnapshot?
    var isRefreshing = false
    var activity: String?
    var outcome: String?
    private(set) var failure: String?
    private(set) var failureRemedy: Remedy?

    private var runInFlight = false

    var isBusy: Bool { activity != nil || runInFlight }
    var isIdle: Bool { !isBusy && !isRefreshing }

    enum Confirmation: Identifiable, Hashable {
        case replaceSteam
        case blockUpdates
        case removeEngine
        case removeEverything
        case stopSteamToInstall

        var id: Self { self }
    }

    var pendingConfirmation: Confirmation?
    var generation = 0

    func beginRun(_ label: String) -> Int {
        activity = label
        AppLog.note("run begin: \(label)")
        return generation
    }

    func report(_ run: Int, _ label: String) {
        guard run == generation else { return }
        activity = label
        AppLog.note("run step: \(label)")
    }

    func endRun() {
        generation += 1
        activity = nil
        AppLog.note("run end\(failure == nil ? "" : " (failed)")")
    }

    private func record(_ error: Error) {
        setFailure(error)
        if let refusal = error as? WriteRefused {
            AppLog.note("run failed: cannot write \(refusal.path)")
        } else {
            AppLog.note("run failed: \(error.localizedDescription)")
        }
    }

    func setFailure(_ message: String) {
        failure = message
        failureRemedy = nil
    }

    func setFailure(_ error: Error) {
        let report = FailureReport([error])
        failure = report?.message
        failureRemedy = report?.remedy
    }

    func clearFailure() {
        failure = nil
        failureRemedy = nil
        retryInstallForce = nil
    }

    /// Set when an install stopped because Steam would not quit: the force flag to retry with.
    private(set) var retryInstallForce: Bool?

    func retryInstall() async {
        guard let force = retryInstallForce else { return }
        AppLog.note("install: retry after Steam did not quit")
        await requestInstall(force: force)
    }

    /// Install, Update and Reinstall. A running game refuses it here and in the installer;
    /// a running Steam is asked about first, because the install closes it.
    private(set) var pendingForce = false

    /// Set when the last install stopped Steam, so Status can offer to start it again.
    private(set) var offerSteamLaunch = false

    func requestInstall(force: Bool = false) async {
        guard isIdle else { return }
        offerSteamLaunch = false
        let state = await Task.detached(priority: .userInitiated) {
            (game: SteamBundle.gameIsRunning, steam: SteamBundle.isRunning)
        }.value
        if state.game {
            outcome = nil
            setFailure(SteamInstaller.gameRunning)
            AppLog.note("install: refused, a game is running")
            return
        }
        if state.steam {
            pendingForce = force
            pendingConfirmation = .stopSteamToInstall
            return
        }
        await installIntoSteam(force: force)
    }

    func confirmPendingInstall() async {
        let force = pendingForce
        pendingForce = false
        await installIntoSteam(force: force)
    }

    func openSteam() {
        offerSteamLaunch = false
        AppLog.note("open Steam after install")
        NSWorkspace.shared.openApplication(
            at: SupportPaths.Steam.app, configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private(set) var pendingRemoval: String?

    func requestEngineRemoval(_ tag: String) {
        guard isIdle else { return }
        pendingRemoval = tag
        pendingConfirmation = .removeEngine
    }

    func cancelEngineRemoval() {
        pendingRemoval = nil
    }

    func removePendingEngine() async {
        guard let tag = pendingRemoval else { return }
        pendingRemoval = nil
        await perform(from: EngineStore.removeStep) { _ in
            try await Task.detached(priority: .userInitiated) {
                try EngineStore.remove(tag)
            }.value
            return "Removed \(EngineStore.displayName(tag))."
        }
    }

    func switchEngine(to tag: String) async {
        guard isIdle, tag != EngineStore.currentTag() else { return }
        await perform(from: EngineStore.step) { _ in
            try await Task.detached(priority: .userInitiated) {
                try EngineStore.switchTo(tag)
            }.value
            return "Now using \(EngineStore.displayName(tag))."
        }
    }

    func perform(
        from first: String,
        _ body: (_ progress: @escaping @Sendable (String) -> Void) async throws -> String?
    ) async {
        guard !runInFlight else {
            AppLog.note("run refused: '\(first)' overlaps a run already in flight")
            return
        }
        runInFlight = true
        defer { runInFlight = false }

        clearFailure()
        outcome = nil
        let run = beginRun(first)
        defer { endRun() }

        do {
            outcome = try await body { label in
                Task { @MainActor in self.report(run, label) }
            }
        } catch {
            record(error)
        }

        await refresh()
    }

    func fetchValveBinaries() async {
        await perform(from: ValveFetcher.Phase.verifying.label) { progress in
            let result = try await ValveFetcher.run { progress($0.label) }
            return result.wroteNothing ? nil : "Downloaded missing components."
        }
    }

    private static let restartHint = "Steam was stopped, so start it again."

    private static let noEngine =
        "No engine is installed yet: run engine/fetch-dormison.sh --activate until the app installs it."

    func installIntoSteam(force: Bool = false) async {
        await perform(from: InstallPhase.checkingPayload.label) { progress in
            let result: InstallOutcome
            do {
                result = try await Task.detached(priority: .userInitiated) {
                    try SteamInstaller.run(force: force, report: { progress($0.label) })
                }.value
            } catch let stillRunning as SteamBundle.StillRunning {
                self.retryInstallForce = force
                throw stillRunning
            }

            var parts = [
                (force ? "NotProton reinstalled" : "NotProton successfully installed")
                    + (result.build.map { " (build \($0))." } ?? ".")
            ]
            if result.stoppedClient {
                parts.append(Self.restartHint)
                self.offerSteamLaunch = true
            }
            let state = await Task.detached(priority: .userInitiated) {
                (runner: EngineStore.state(), payload: PayloadInspector.inspect())
            }.value
            if state.runner == .none { parts.append(Self.noEngine) }

            // Fetch binaries from Valve
            if state.payload.missing.contains(where: { $0.origin.isFetchable }) {
                progress("Downloading missing components")
                _ = try await ValveFetcher.run { progress($0.label) }
            }

            return parts.joined(separator: " ")
        }
    }

    func setUpdateBlock(_ blocked: Bool) async {
        await perform(from: blocked ? "Blocking Steam client updates"
                                    : "Allowing Steam client updates") { _ in
            if blocked {
                try UpdateBlock.write()
                return "Steam client updates are blocked."
            }

            try UpdateBlock.remove()
            return "Steam client updates are allowed."
        }
    }

    func repairSteam() async {
        await perform(from: RepairPhase.checking.label) { progress in
            let result = try await SteamRepair.run { progress($0.label) }

            var parts = ["Steam restored to its original state."]
            if result.stoppedClient { parts.append(Self.restartHint) }
            return parts.joined(separator: " ")
        }
    }

    func removeEverything() async {
        await perform(from: UninstallPhase.stoppingClient.label) { progress in
            let result = try await Uninstall.run { progress($0.label) }

            return result.restoredValveSignature
                ? "NotProton has been removed."
                : "NotProton has been removed. Steam needs to be redownloaded. "
                    + "Please run Repair Steam again once you are online."
        }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let version = AppVersion.bundled
        let captured = await Task.detached(priority: .userInitiated) {
            StatusSnapshot.capture(bundledVersion: version)
        }.value
        snapshot = captured
        AppLog.note(captured)
        await measureRunnerSizes()
    }

    private(set) var runnerSizes: [String: Int64] = [:]

    func measureRunnerSizes() async {
        let known = Set(runnerSizes.keys)
        let present = await Task.detached(priority: .utility) {
            Set(EngineStore.installed().map(\.tag))
        }.value

        for stale in known.subtracting(present) { runnerSizes[stale] = nil }

        for tag in present.subtracting(known) {
            runnerSizes[tag] = await Task.detached(priority: .utility) {
                EngineStore.size(of: tag)
            }.value
        }
    }
}
