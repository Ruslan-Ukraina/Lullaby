// The main window's logic (Phase 8 with the owner's edit): one button (Install, Update or
// Delete) and the actions under ⚙︎, each a FlowRunner list of steps. Status's SystemStatus
// still reads the state of Steam, the engine and the bridge, and still runs the Steam
// update gate while the app is open.

import AppKit
import Foundation
import LullabySettings
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
    var checking = false
    var question: Question?
    var showsBadge: Bool
    /// Set the one time ⚙︎ opens with the badge on: the row is highlighted, the tip shown.
    var highlightSteamUpdates = false
    /// The failed flow's alert is on screen; closing it keeps the flow for a retry.
    var alertShown = false

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
        MainScreen.make(install: install, plan: plan, flow: runner.state, checking: checking)
    }

    // MARK: ⚙︎ read-only lines

    /// Steam's build, and whether Lullaby has signatures for it ("checked").
    var steamVersion: (build: String, checked: Bool)? {
        guard let updates = status.snapshot?.updates, let build = updates.installedSteam else { return nil }
        return (String(build), updates.supportedBuilds.contains(build))
    }

    var engineVersion: String? {
        guard case .engine(let version)? = status.snapshot?.runner else { return nil }
        return EngineStore.displayName(version)
    }

    var steamUpdatesOff: Bool { status.snapshot?.updates.gateMode == .manual }

    /// Installed D3DMetal versions, and those this macOS cannot run (D3DMetal 4 needs 27).
    var toolkits: (installed: [String], unusable: [String]) {
        let store = D3DMetalStore.standard
        return (store.installed().map(\.version), store.unusable().map(\.version))
    }

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
        checking = true
        defer { checking = false }
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

    // MARK: The button

    /// Install, Update or Delete. After a failure the same button goes on from the step
    /// that failed (owner's edit: no separate Retry).
    func press() async {
        let button = screen.button
        if case .failed(let kind, _, _, _, _)? = runner.state, kind == button.kind, button != .delete {
            AppLog.note("main: \(kind.rawValue) pressed again, going on from the failed step")
            await retry()
            return
        }
        switch button {
        case .install: await begin(.install)
        case .update: await begin(.update)
        case .delete: question = .delete
        }
    }

    func confirmDelete() async {
        question = nil
        await begin(.delete, asked: true)
    }

    func pressReinstall() async { await begin(.reinstall) }

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
            // The flow stops on its first step; pressing again looks once more.
            AppLog.note("main: \(kind.rawValue) waits, a game is running")
            let probe = self.probe
            let wait = FlowStep(.waitForGame, tr("Checking for running games")) { _ in
                if await probe().game { throw KnownProblem(.gameRunning, log: "a game is running") }
            }
            let succeeded = await runner.start(kind, [wait] + steps(kind, self))
            await finished(succeeded: succeeded)
            return
        }
        if state.steam, !asked, Self.closesSteam(kind, plan: plan) {
            question = .closeSteam(kind)
            return
        }
        await run(kind)
    }

    static func closesSteam(_ kind: FlowKind, plan: UpdatePlan?, legacy: Bool = LegacyMigration.isNeeded()) -> Bool {
        switch kind {
        case .install, .reinstall, .delete: true
        case .update: (plan?.closesSteam ?? false) || legacy
        case .addToolkit, .steamUpdates: false
        }
    }

    private func run(_ kind: FlowKind) async {
        let succeeded = await runner.start(kind, steps(kind, self))
        await finished(succeeded: succeeded)
    }

    private func finished(succeeded: Bool) async {
        guard succeeded, case .finished(let kind)? = runner.state else {
            alertShown = runner.canRetry
            await status.refresh()
            return
        }
        if kind == .install {
            badge.installFinished()
            showsBadge = badge.isShowing
        }
        await status.refresh()
        runner.dismiss()
        if kind == .delete {
            plan = nil
        } else if kind != .steamUpdates, kind != .addToolkit {
            await checkForUpdates()
        }
    }

    static func realSteps(_ kind: FlowKind, _ model: MainModel) -> [FlowStep] {
        switch kind {
        case .install: SetupSteps.setup(nil)
        case .update: SetupSteps.setup(model.plan ?? UpdatePlan())
        case .reinstall: SetupSteps.reinstall()
        case .delete: SetupSteps.delete()
        case .addToolkit: model.pendingImage.map(SetupSteps.addToolkit) ?? []
        case .steamUpdates: SetupSteps.steamUpdates(off: model.pendingUpdatesOff)
        }
    }
}
