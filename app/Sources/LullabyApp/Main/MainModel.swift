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

    // MARK: Private releases (Phase 6)

    /// The Keychain side of the token, a stand-in in tests.
    struct TokenKeychain {
        var read: (String) -> String?
        var save: (String, String) -> Bool
        var remove: (String) -> Void

        static var live: TokenKeychain { TokenKeychain(
            read: { ReleaseToken.read(repository: $0) },
            save: { ReleaseToken.save($0, repository: $1) },
            remove: { ReleaseToken.remove(repository: $0) }) }
    }

    /// LBReleaseAccess and LBReleaseRepository of this build (`make app` from release/feed.json).
    @ObservationIgnored var releaseInfo: () -> (access: String, repository: String) = {
        (Bundle.main.object(forInfoDictionaryKey: ReleaseAccess.infoKey) as? String ?? "public",
         Bundle.main.object(forInfoDictionaryKey: ReleaseAccess.repositoryKey) as? String ?? "")
    }
    @ObservationIgnored var tokenKeychain = TokenKeychain.live
    @ObservationIgnored var checkToken: (String, String) async -> ReleaseToken.Check = {
        await ReleaseToken.check($0, repository: $1)
    }
    /// The updater and the feeds read the Keychain again (AppUpdater.start).
    @ObservationIgnored var restartUpdates: @MainActor () -> Void = { AppUpdater.shared.start() }

    /// The token sheet is open; what came of the last save.
    var tokenPromptShown = false
    var tokenResult: String?
    private(set) var hasReleaseToken = false

    /// The repository of a private release feed; nil when releases are public, and then
    /// ⚙︎ has no token row at all.
    var privateReleaseRepository: String? {
        let info = releaseInfo()
        return info.access == "private" && !info.repository.isEmpty ? info.repository : nil
    }

    func readTokenState() {
        hasReleaseToken = privateReleaseRepository.map { tokenKeychain.read($0) != nil } ?? false
    }

    /// Checks the token with GitHub, keeps it in the Keychain, and looks for updates with it.
    /// The token is never logged; only what GitHub said is.
    func saveReleaseToken(_ text: String) async {
        guard let repository = privateReleaseRepository else { return }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        let check = await checkToken(token, repository)
        AppLog.note("release access: GitHub says the new token \(check.rawValue)")
        switch check {
        case .works:
            _ = tokenKeychain.save(token, repository)
            tokenResult = tr("The token works. Lullaby checks for updates now.")
        case .unreachable:
            _ = tokenKeychain.save(token, repository)
            tokenResult = tr("GitHub can't be reached. The token is saved; Lullaby tries it next time.")
        case .rejected:
            tokenResult = tr("GitHub didn't accept this token.")
        case .noAccess:
            tokenResult = tr("This token has no access to Lullaby's releases.")
        }
        readTokenState()
        guard check == .works || check == .unreachable else { return }
        restartUpdates()
        await checkForUpdates()
    }

    func removeReleaseToken() {
        guard let repository = privateReleaseRepository else { return }
        tokenKeychain.remove(repository)
        AppLog.note("release access: token removed from the Keychain")
        readTokenState()
        restartUpdates()
        plan = nil
    }

    // MARK: Opening

    /// When the window opens: read the state, then look for updates once (ROADMAP §9.5).
    func opened() async {
        badge.apply()
        await status.refresh()
        status.startReleaseChecks()
        await checkForUpdates()
        await continueAfterAppUpdate()
    }

    /// The version that came up after Lullaby's own update puts its patch into Steam, which the old one left for it.
    private func continueAfterAppUpdate() async {
        let marker = UpdateContinuation.take()
        guard UpdateContinuation.shouldContinue(marker, bundled: AppVersion.bundled), let marker else {
            if marker != nil { AppLog.note("main: the update note is from this very version, dropped") }
            return
        }
        guard plan?.steamPatch == true else {
            AppLog.note("main: Lullaby was updated from \(marker.from), Steam's patch is current already")
            return
        }
        AppLog.note("main: Lullaby was updated from \(marker.from); going on with the patch for Steam")
        reopenSteam = true
        await begin(.update, asked: true)
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
        if case .outdated(_, _, let stale)? = status.snapshot?.steam {
            plan.steamPatch = true
            plan.steamPatchQuits = stale.contains(.dylib)
        }
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
        reopenSteam = true
        await run(kind)
    }

    /// The owner agreed to close Steam for a flow: it opens again when the flow is done
    /// (owner, 11.10: "agreed to restart Steam, but it did not restart").
    private var reopenSteam = false
    @ObservationIgnored var openSteam: @MainActor () -> Void = {
        AppLog.note("main: opening Steam again")
        NSWorkspace.shared.openApplication(at: SupportPaths.Steam.app, configuration: .init())
    }

    func retry() async {
        guard runner.canRetry else { return }
        let succeeded = await runner.retry()
        await finished(succeeded: succeeded)
    }

    /// ⚙︎ opened: the badge goes for good, and the first time the Steam updates row lights up.
    func gearOpened() {
        readTokenState()
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
        if reopenSteam, !runner.canRetry {
            reopenSteam = false
            if !(await probe().steam) { openSteam() }
        }
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
        if AppUpdater.pendingRelaunch {
            askToRelaunch()
            return
        }
        if kind == .delete {
            plan = nil
        } else if kind != .steamUpdates, kind != .addToolkit {
            await checkForUpdates()
        }
    }

    /// The new Lullaby.app is downloaded and verified: one system alert, then Sparkle
    /// quits and relaunches it (owner, 11.10: no Sparkle windows).
    private func askToRelaunch() {
        let alert = NSAlert()
        alert.messageText = tr("Lullaby is updated")
        alert.informativeText = tr("Restart Lullaby to finish. Steam and your games keep running.")
        alert.addButton(withTitle: tr("Restart"))
        alert.addButton(withTitle: tr("Later"))
        let now = alert.runModal() == .alertFirstButtonReturn
        AppUpdater.shared.relaunch(now: now)
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
