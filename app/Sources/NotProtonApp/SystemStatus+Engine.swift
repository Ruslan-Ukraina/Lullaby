// Engine section of Status: check Dormison's signed list, update or reinstall
// through EngineUpdater, roll back. A running game refuses all of it.
//
// Update and Reinstall download, check and test the engine while Steam stays open,
// then ask "Close Steam and Switch?" and close Steam the moment that is pressed.
// Asking first and closing Steam minutes later, after the download, read as Steam
// not closing at all (your check, 2026-10-06). Roll Back is instant, so it asks
// first and closes Steam right away.

import Foundation

enum EngineAction: Sendable, Equatable {
    case install(EngineRelease)
    /// Switch to the engine already prepared (after the question, or on Retry).
    case finish
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
        switch action {
        case .install(let release):
            await prepareEngine(release)
        case .finish:
            await runEngine(.finish, mayQuitSteam: true)
        case .rollback:
            if state.steam {
                pendingEngine = action
                pendingConfirmation = .stopSteamForEngine
                return
            }
            await runEngine(action, mayQuitSteam: false)
        }
    }

    /// Download, check and test with Steam open; then switch, asking first if Steam runs.
    private func prepareEngine(_ release: EngineRelease) async {
        let reinstall = release.version == EngineStore.currentTag()
        let first = reinstall ? "Reinstalling \(release.displayName)" : "Installing \(release.displayName)"
        var ready = false
        await perform(from: first) { progress in
            let prepared = try await Task.detached(priority: .userInitiated) {
                try await EngineUpdater().prepare(release) { progress($0.label) }
            }.value
            self.preparedEngine = prepared
            ready = true
            return nil
        }
        guard ready else { return }
        if await Task.detached(priority: .userInitiated, operation: { SteamBundle.isRunning }).value {
            AppLog.note("engine: \(release.version) ready, asking to close Steam")
            outcome = "\(release.displayName) is downloaded and tested. Close Steam to switch to it."
            pendingEngine = .finish
            pendingConfirmation = .stopSteamForEngine
            return
        }
        await runEngine(.finish, mayQuitSteam: false)
    }

    func confirmPendingEngine() async {
        guard let action = pendingEngine else { return }
        pendingEngine = nil
        AppLog.note("engine: Close Steam confirmed for \(action == .rollback ? "roll back" : "the switch")")
        await runEngine(action, mayQuitSteam: true)
    }

    /// "Cancel" on the question: a prepared engine is dropped, the current one stays.
    func cancelPendingEngine() {
        let action = pendingEngine
        pendingEngine = nil
        guard action == .finish, let prepared = preparedEngine else { return }
        preparedEngine = nil
        Task.detached { EngineUpdater().discard(prepared) }
        outcome = "Update cancelled. \(EngineStore.displayName(EngineStore.currentTag() ?? "")) stays."
        AppLog.note("engine: switch cancelled, prepared engine dropped")
    }

    func retryEngineAction() async {
        guard let action = retryEngine else { return }
        AppLog.note("engine: retry after Steam did not quit")
        await requestEngine(action)
    }

    private func runEngine(_ action: EngineAction, mayQuitSteam: Bool) async {
        switch action {
        case .install(let release):
            await prepareEngine(release)
        case .finish:
            guard let prepared = preparedEngine else { return }
            let release = prepared.release
            await perform(from: "Switching to \(release.displayName)") { progress in
                let result: EngineUpdateOutcome
                do {
                    result = try await Task.detached(priority: .userInitiated) {
                        try EngineUpdater().activatePrepared(prepared, mayQuitSteam: mayQuitSteam) {
                            progress($0.label)
                        }
                    }.value
                } catch let stillRunning as SteamBundle.StillRunning {
                    self.retryEngine = .finish
                    throw stillRunning
                } catch {
                    self.preparedEngine = nil
                    throw error
                }
                self.preparedEngine = nil
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

    /// `--ui-test-engine-reinstall` / `--ui-test-engine-rollback`: the buttons' path
    /// without a mouse. The same SystemStatus calls the Reinstall (or Roll Back) button
    /// and "Close Steam and …" make, in the running app with its window, the question
    /// left on screen for a few seconds so it can be photographed.
    static let uiTestReinstall = "--ui-test-engine-reinstall"
    static let uiTestRollback = "--ui-test-engine-rollback"

    func runEngineUITestIfRequested(arguments: [String] = CommandLine.arguments) async {
        let reinstall = arguments.contains(Self.uiTestReinstall)
        guard reinstall || arguments.contains(Self.uiTestRollback) else { return }
        AppLog.note("ui-test: begin \(reinstall ? "reinstall" : "rollback")")
        if reinstall {
            await checkEngineUpdates()
            guard case .upToDate(let release, true)? = engineCheck else {
                AppLog.note("ui-test: reinstall not offered (\(engineCheck?.summary ?? "no check"))")
                return
            }
            AppLog.note("ui-test: press Reinstall")
            await requestEngine(.install(release))
        } else {
            AppLog.note("ui-test: press Roll Back")
            await requestEngine(.rollback)
        }
        if pendingConfirmation == .stopSteamForEngine {
            AppLog.note("ui-test: question on screen (Steam running: \(SteamBundle.isRunning))")
            try? await Task.sleep(for: .seconds(8))
            AppLog.note("ui-test: press Close Steam and \(reinstall ? "Switch" : "Roll Back")")
            pendingConfirmation = nil
            await confirmPendingEngine()
        }
        AppLog.note("ui-test: end outcome=\(outcome ?? "none") failure=\(failure ?? "none") "
            + "steamRunning=\(SteamBundle.isRunning)")
    }
}
