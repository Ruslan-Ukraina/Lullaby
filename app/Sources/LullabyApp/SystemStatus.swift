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
    /// What Rollback returns to, e.g. "dormison-b1"; the same name as the current
    /// engine when the previous tree is the copy from before a reinstall.
    var rollbackTarget: String?
    var engineCapabilities = EngineCapabilities()
    var nativeSteamWindows = false
    var steamAsRegularApp = false
    var updates = UpdatesSnapshot()
    /// NotProton's files or patch are still on this Mac (LegacyMigration).
    var legacy = false

    static func capture(bundledVersion: String) -> StatusSnapshot {
        let patch = PatchComparison.inspect()
        return StatusSnapshot(
            steam: SteamBundle.deployment(bundledVersion: bundledVersion, stale: patch?.stale ?? []),
            steamRunning: SteamBundle.isRunning,
            updateBlocked: UpdateBlock.isPresent(),
            runner: EngineStore.state(),
            payload: PayloadInspector.inspect(),
            installedEngines: EngineStore.installed(),
            patch: patch,
            rollbackTarget: EngineUpdater().rollbackTarget,
            engineCapabilities: DormisonEngine().capabilities,
            nativeSteamWindows: SteamWindows.isOn(),
            steamAsRegularApp: SteamWindows.isRegularApp(),
            updates: UpdatesSnapshot.capture(),
            legacy: LegacyMigration.isNeeded()
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

    // Phase 5: SystemStatus+Updates.swift.
    var bridgeCheck: BridgeCheck?
    var gateDecision: SteamGateDecision?
    var releasesCheckedAt: Date?
    var releaseProblem: String?
    var releaseChecksStarted = false

    /// Set when an install stopped because Steam would not quit: the force flag to retry with.
    private(set) var retryInstallForce: Bool?

    /// Set when the last install stopped Steam, so Status can offer to start it again.
    var offerSteamLaunch = false

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

    private static let restartHint = "Steam was stopped, so start it again."

    private static let noEngine =
        "No engine is installed yet: press Check for Updates in the Engine section to install it."

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
                (force ? "Lullaby reinstalled" : "Lullaby successfully installed")
                    + (result.build.map { " (build \($0))." } ?? ".")
            ]
            if result.stoppedClient {
                parts.append(Self.restartHint)
                self.offerSteamLaunch = true
            }
            let state = await Task.detached(priority: .userInitiated) {
                SteamHelperFiles.sync()
                return (runner: EngineStore.state(), payload: PayloadInspector.inspect())
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

    func repairSteam() async {
        await perform(from: RepairPhase.checking.label) { progress in
            _ = await Task.detached(priority: .userInitiated) { SteamHelperFiles.remove() }.value
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
                ? "Lullaby has been removed."
                : "Lullaby has been removed. Steam needs to be redownloaded. "
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
    }
}
