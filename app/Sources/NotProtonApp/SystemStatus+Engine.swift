// Engine section of Status: check Dormison's signed list, update or reinstall
// through EngineUpdater, roll back. A running game refuses all of it; a running
// Steam is asked about first, because the switch closes it.

import Foundation

enum EngineAction: Sendable, Equatable {
    case install(EngineRelease)
    case rollback
}

extension SystemStatus {

    /// `quiet`: the automatic check when Status opens; failures go to the log only.
    func checkEngineUpdates(quiet: Bool = false) async {
        guard isIdle else { return }
        let channel = engineChannel
        if quiet {
            do {
                engineCheck = try await EngineUpdater().check(channel: channel)
                engineCheckedAt = .now
            } catch {
                AppLog.note("engine: automatic check failed: \(error.localizedDescription)")
            }
            return
        }
        await perform(from: EngineUpdatePhase.checking.label) { _ in
            let result = try await EngineUpdater().check(channel: channel)
            self.engineCheck = result
            self.engineCheckedAt = .now
            return nil
        }
    }

    func setEngineChannel(_ channel: EngineChannel) async {
        guard channel != engineChannel else { return }
        engineChannel = channel
        EngineChannel.preferred = channel
        engineCheck = nil
        AppLog.note("engine: channel set to \(channel.rawValue)")
        await checkEngineUpdates()
    }

    func requestEngine(_ action: EngineAction) async {
        guard isIdle else { return }
        offerSteamLaunch = false
        let state = await Task.detached(priority: .userInitiated) {
            (game: SteamBundle.gameIsRunning, steam: SteamBundle.isRunning)
        }.value
        if state.game {
            outcome = nil
            setFailure(EngineUpdater.gameRunning)
            AppLog.note("engine: refused, a game is running")
            return
        }
        if state.steam {
            pendingEngine = action
            pendingConfirmation = .stopSteamForEngine
            return
        }
        await runEngine(action, mayQuitSteam: false)
    }

    func confirmPendingEngine() async {
        guard let action = pendingEngine else { return }
        pendingEngine = nil
        await runEngine(action, mayQuitSteam: true)
    }

    func retryEngineAction() async {
        guard let action = retryEngine else { return }
        AppLog.note("engine: retry after Steam did not quit")
        await requestEngine(action)
    }

    private func runEngine(_ action: EngineAction, mayQuitSteam: Bool) async {
        switch action {
        case .install(let release):
            let reinstall = release.version == EngineStore.currentTag()
            let first = reinstall ? "Reinstalling \(release.displayName)" : "Installing \(release.displayName)"
            await perform(from: first) { progress in
                let result: EngineUpdateOutcome
                do {
                    result = try await Task.detached(priority: .userInitiated) {
                        try await EngineUpdater().install(release, mayQuitSteam: mayQuitSteam) {
                            progress($0.label)
                        }
                    }.value
                } catch let stillRunning as SteamBundle.StillRunning {
                    self.retryEngine = action
                    throw stillRunning
                }
                self.engineCheck = .upToDate(release, supported: true)
                var parts = [
                    result.reinstalled
                        ? "\(release.displayName) reinstalled. The copy it replaced is kept: Roll Back returns to it."
                        : "Now using \(release.displayName)."
                        + (result.previous.map { " \(EngineStore.displayName($0)) is kept for Roll Back." } ?? ""),
                ]
                if result.stoppedSteam {
                    parts.append("Steam was stopped, so start it again.")
                    self.offerSteamLaunch = true
                }
                return parts.joined(separator: " ")
            }
        case .rollback:
            await perform(from: "Rolling back the engine") { progress in
                let result: EngineRollbackOutcome
                do {
                    result = try await Task.detached(priority: .userInitiated) {
                        try EngineUpdater().rollback(mayQuitSteam: mayQuitSteam) { progress($0.label) }
                    }.value
                } catch let stillRunning as SteamBundle.StillRunning {
                    self.retryEngine = action
                    throw stillRunning
                }
                self.engineCheck = nil
                var text = "Back on \(EngineStore.displayName(result.to))."
                if result.stoppedSteam {
                    text += " Steam was stopped, so start it again."
                    self.offerSteamLaunch = true
                }
                return text
            }
        }
    }
}
