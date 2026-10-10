// The main window's logic (Phase 8): Install, Update, Delete and the ⚙︎ actions, each a
// FlowRunner list of steps. Status's SystemStatus still reads the state of Steam, the
// engine and the bridge, and still runs the Steam update gate while the app is open.

import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class MainModel {

    /// The questions the window asks before a flow.
    enum Question: Identifiable, Equatable {
        case closeSteam(FlowKind)
        case delete
        case steamUpdatesOff

        var id: String {
            switch self {
            case .closeSteam(let kind): "close-\(kind.rawValue)"
            case .delete: "delete"
            case .steamUpdatesOff: "steam-updates-off"
            }
        }
    }

    let status: SystemStatus
    let runner: FlowRunner
    let badge: BadgeStore
    var plan: UpdatePlan?
    var question: Question?
    /// Delete's box: also delete game prefixes. Off unless the player ticks it (§9.3).
    var deletePrefixes = false
    var showsBadge: Bool
    /// Set the one time ⚙︎ opens with the badge on: the row is highlighted, the tip shown.
    var highlightSteamUpdates = false

    /// Stand-ins for tests: the real steps, the game and Steam probes, the update check.
    @ObservationIgnored var steps: @MainActor (FlowKind, MainModel) -> [FlowStep] = MainModel.realSteps
    @ObservationIgnored var probe: @Sendable () async -> (game: Bool, steam: Bool) = {
        await Task.detached { (SteamBundle.gameIsRunning, SteamBundle.isRunning) }.value
    }
    @ObservationIgnored var findUpdates: @MainActor (MainModel) async -> UpdatePlan? = { await $0.realUpdatePlan() }

    private var pendingImage: URL?
    private var pendingUpdatesOff = false

    init(status: SystemStatus = SystemStatus(), runner: FlowRunner = FlowRunner(), badge: BadgeStore = BadgeStore()) {
        self.status = status
        self.runner = runner
        self.badge = badge
        showsBadge = badge.isShowing
    }

    /// Set by tests and previews in place of what Status reads from the Mac.
    var installOverride: InstallState?

    var install: InstallState { installOverride ?? InstallState.from(status.snapshot) }

    var screen: MainScreen {
        MainScreen.make(install: install, plan: plan, flow: runner.state)
    }

    /// "NotProton 1.1.0 · Dormison b2 · bridge b2-3 · Steam patch 1506B51E, 10 Oct 2026":
    /// what is installed, for ⚙︎ and the status line's tooltip (CLAUDE.md §8, build and date).
    var versionsLine: String {
        var parts = ["NotProton \(AppVersion.bundled)"]
        guard let snapshot = status.snapshot else { return parts[0] }
        if case .engine(let version) = snapshot.runner { parts.append(EngineStore.displayName(version)) }
        if let bridge = snapshot.updates.activeBridge { parts.append(bridge.id) }
        if let patch = snapshot.patch, let build = patch.build {
            let date = patch.installedAt.map { ", " + $0.formatted(date: .abbreviated, time: .shortened) } ?? ""
            parts.append("Steam patch \(build)\(date)")
        }
        return parts.joined(separator: " · ")
    }

    var steamUpdatesOff: Bool { status.snapshot?.updates.gateMode == .manual }
    var engineRollback: String? { status.snapshot?.rollbackTarget }
    var bridgeRollback: BridgeRelease? { status.snapshot?.updates.bridgeRollback }

    // MARK: Opening

    /// When the window opens: read the state, then look for updates once (ROADMAP §9.5).
    func opened() async {
        badge.apply()
        await status.refresh()
        status.startReleaseChecks()
        await checkForUpdates()
    }

    func checkForUpdates() async {
        guard install.isInstalled, !runner.isRunning else { plan = nil; return }
        plan = await findUpdates(self)
        AppLog.note("main: update check, \(plan.map { $0.isEmpty ? "nothing" : $0.parts.joined(separator: ", ") } ?? "not checked")")
    }

    private func realUpdatePlan() async -> UpdatePlan {
        var plan = UpdatePlan()
        if case .available(let release)? = try? await EngineUpdater().check(channel: EngineChannel.preferred) {
            plan.engine = release
        }
        await status.checkReleases(quiet: true)
        if case .available(let release, _)? = status.bridgeCheck { plan.bridge = release }
        if case .outdated? = status.snapshot?.steam { plan.steamPatch = true }
        plan.app = await AppUpdater.shared.probe()
        return plan
    }

    // MARK: Buttons

    func pressInstall() async { await begin(.install) }
    func pressUpdate() async { await begin(.update) }
    func pressReinstall() async { await begin(.reinstall) }
    func pressRollbackEngine() async { await begin(.rollbackEngine) }
    func pressRollbackBridge() async { await begin(.rollbackBridge) }

    func pressDelete() {
        deletePrefixes = false
        question = .delete
    }

    func confirmDelete() async {
        question = nil
        await begin(.delete, asked: true)
    }

    func addToolkit(_ image: URL) async {
        pendingImage = image
        await begin(.addToolkit)
    }

    /// The toggle in ⚙︎. Turning updates off asks first; on goes back to the automatic gate.
    func setSteamUpdatesOff(_ off: Bool) async {
        if off {
            question = .steamUpdatesOff
            return
        }
        pendingUpdatesOff = false
        await begin(.steamUpdates)
    }

    func confirmSteamUpdatesOff() async {
        question = nil
        pendingUpdatesOff = true
        await begin(.steamUpdates)
    }

    func confirmCloseSteam(_ kind: FlowKind) async {
        question = nil
        await run(kind)
    }

    func retry() async {
        guard runner.canRetry else { return }
        let succeeded = await runner.retry()
        await finished(succeeded: succeeded)
    }

    func openSteam() {
        runner.dismiss()
        AppLog.note("main: open Steam")
        NSWorkspace.shared.openApplication(at: SupportPaths.Steam.app, configuration: NSWorkspace.OpenConfiguration())
    }

    func revealLogs() {
        NSWorkspace.shared.activateFileViewerSelecting([AppLog.file])
    }

    /// ⚙︎ opened: the badge goes for good, and the first time the Steam updates row lights up.
    func gearOpened() {
        highlightSteamUpdates = badge.gearOpened()
        showsBadge = badge.isShowing
    }

    // MARK: Flow

    private func begin(_ kind: FlowKind, asked: Bool = false) async {
        guard !runner.isRunning else { return }
        let state = await probe()
        if state.game, kind != .addToolkit, kind != .steamUpdates {
            AppLog.note("main: \(kind.rawValue) refused, a game is running")
            await runner.start(kind, [FlowStep(.quitSteam, MainScreen.runningLine(kind)) { _ in
                throw KnownProblem(.gameRunning, log: "a game is running")
            }])
            return
        }
        if state.steam, !asked, Self.closesSteam(kind, plan: plan) {
            question = .closeSteam(kind)
            return
        }
        await run(kind)
    }

    static func closesSteam(_ kind: FlowKind, plan: UpdatePlan?) -> Bool {
        switch kind {
        case .install, .reinstall, .delete, .rollbackEngine: true
        case .update: plan?.closesSteam ?? false
        case .rollbackBridge, .addToolkit, .steamUpdates: false
        }
    }

    private func run(_ kind: FlowKind) async {
        let succeeded = await runner.start(kind, steps(kind, self))
        await finished(succeeded: succeeded)
    }

    private func finished(succeeded: Bool) async {
        guard succeeded, case .finished(let kind)? = runner.state else {
            await status.refresh()
            return
        }
        if kind == .install {
            badge.installFinished()
            showsBadge = badge.isShowing
        }
        await status.refresh()
        if kind == .update || kind == .install || kind == .reinstall || kind == .rollbackEngine || kind == .rollbackBridge {
            await checkForUpdates()
        }
        if kind == .delete { plan = nil }
    }

    static func realSteps(_ kind: FlowKind, _ model: MainModel) -> [FlowStep] {
        switch kind {
        case .install: SetupSteps.install()
        case .update: SetupSteps.update(model.plan ?? UpdatePlan())
        case .reinstall: SetupSteps.reinstall()
        case .delete: SetupSteps.delete(prefixes: model.deletePrefixes)
        case .rollbackEngine: SetupSteps.rollbackEngine()
        case .rollbackBridge: SetupSteps.rollbackBridge()
        case .addToolkit: model.pendingImage.map(SetupSteps.addToolkit) ?? []
        case .steamUpdates: SetupSteps.steamUpdates(off: model.pendingUpdatesOff)
        }
    }
}
