// Phase 5 in Status: the Steam bridge (BridgeUpdater), Steam signatures
// (SignatureUpdater) and the Steam update gate (SteamUpdateGate).
//
// When Status opens and every three hours while NotProton runs, it reads the signed
// lists from NotProton's releases, writes new signature databases, and lets Steam
// update only to a build that has them. Bridge revisions are offered, not
// installed on their own: a bridge change touches the engine's ntdll.dll.

import Foundation

struct UpdatesSnapshot: Sendable {
    var feedOff: String?
    var activeBridge: BridgeRelease?
    var bridgeRollback: BridgeRelease?
    /// Installed engines with no Steam bridge that fits them (BACKLOG 13).
    var enginesWithoutBridge: Set<String> = []
    var gateMode: SteamGateMode = .auto
    var installedSteam: UInt64?
    var supportedBuilds: [UInt64] = []
    var newestDatabase: String?

    static func capture() -> UpdatesSnapshot {
        let updater = BridgeUpdater()
        let catalog = updater.catalog()
        var off: String?
        if case .off(let reason) = ReleaseFeed.configured { off = reason }
        let gate = SteamUpdateGate()
        return UpdatesSnapshot(
            feedOff: off,
            activeBridge: updater.active,
            bridgeRollback: updater.rollbackTarget,
            enginesWithoutBridge: Set(EngineStore.installed().map(\.tag).filter {
                !EngineStore.hasSteamBridge($0, catalog: catalog)
            }),
            gateMode: gate.mode,
            installedSteam: SteamBuild.installed(),
            supportedBuilds: SignatureUpdater().support().supportedBuilds(installedIn: SupportPaths.signatures),
            newestDatabase: PayloadInspector.newestSignatureDatabase())
    }
}

extension SystemStatus {

    static let releaseCheckInterval: Duration = .seconds(3 * 60 * 60)

    /// Once per app run: the quiet check now and every three hours.
    func startReleaseChecks() {
        guard !releaseChecksStarted else { return }
        releaseChecksStarted = true
        Task { [weak self] in
            while true {
                await self?.checkReleases(quiet: true)
                try? await Task.sleep(for: Self.releaseCheckInterval)
            }
        }
    }

    /// Signatures, then the gate (which needs them), then the bridge list.
    /// `quiet`: failures go to the log only.
    func checkReleases(quiet: Bool = false) async {
        if quiet {
            guard isIdle else { return }
            await runReleaseChecks()
            await refresh()
            return
        }
        await perform(from: BridgePhase.checking.label) { _ in
            await self.runReleaseChecks()
            if let problem = self.releaseProblem { throw StepFailure(step: ReleaseFeed.step, detail: problem) }
            return nil
        }
    }

    private func runReleaseChecks() async {
        var problem: String?
        let outcome = await Task.detached(priority: .utility) { () -> (SignatureOutcome?, String?) in
            do { return (try await SignatureUpdater().update(), nil) } catch {
                return (nil, error.localizedDescription)
            }
        }.value
        if let installed = outcome.0?.installed, !installed.isEmpty {
            AppLog.note("updates: new signature databases \(installed.joined(separator: " "))")
        }
        problem = outcome.1
        gateDecision = await Task.detached(priority: .utility) { await SteamUpdateGate().evaluate() }.value
        let bridge = await Task.detached(priority: .utility) { () -> (BridgeCheck?, String?) in
            do { return (try await BridgeUpdater().check(), nil) } catch {
                return (BridgeUpdater().evaluate(BridgeUpdater().catalog()), error.localizedDescription)
            }
        }.value
        bridgeCheck = bridge.0
        problem = problem ?? bridge.1
        releaseProblem = problem
        releasesCheckedAt = .now
        if let problem { AppLog.note("updates: check finished with a problem: \(problem)") }
    }

    nonisolated static func build(_ build: UInt64?) -> String { build.map(String.init) ?? "unknown" }

    /// One sentence for the Status row and the outcome line.
    nonisolated static func gateSentence(_ state: SteamGateState) -> String {
        switch state {
        case .manual(let installed):
            "Steam stays on build \(build(installed)) because you blocked its updates."
        case .current(let current, let supported):
            supported
                ? "Steam \(current) is current and supported."
                : "Steam \(current) has no NotProton signatures yet."
        case .updateAllowed(_, let to):
            "Steam \(to) is supported. Steam updates to it the next time it starts."
        case .waiting(let offered, _):
            "Steam \(offered) is out. Waiting for NotProton support."
        case .unknown:
            "Steam's latest version could not be checked, so its updates stay on hold."
        }
    }
}
