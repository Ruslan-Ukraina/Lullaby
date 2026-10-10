import AppKit
import Foundation
import SwiftUI
import Testing

@testable import LullabyApp

// Phase 8 (ROADMAP §9.8, with the owner's edit): the window's states, its one button
// (Install, Update, Delete), the flows behind it, the badge and Delete. Nothing here
// touches Steam, the engine or the network: the steps and the probes are stand-ins.

private func step(_ id: FlowStep.ID, _ log: Log) -> FlowStep {
    FlowStep(id, id.rawValue) { _ in
        await log.add(id)
        if await log.shouldFail(id) { throw StepFailure(step: id.rawValue, detail: "stand-in failure") }
    }
}

private actor Log {
    var ran: [FlowStep.ID] = []
    var failing: Set<FlowStep.ID> = []
    func add(_ id: FlowStep.ID) { ran.append(id) }
    func shouldFail(_ id: FlowStep.ID) -> Bool { failing.contains(id) }
    func fail(_ ids: Set<FlowStep.ID>) { failing = ids }
}

private actor GameSwitch {
    var running = true
    func quit() { running = false }
}

private func defaults() -> UserDefaults {
    let name = "lullaby-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
private func model(_ log: Log? = nil, steam: Bool = false) -> MainModel {
    let model = MainModel(badge: BadgeStore(defaults: defaults(), dock: { _ in }))
    model.probe = { (false, steam) }
    model.findUpdates = { _ in UpdatePlan() }
    if let log {
        model.steps = { kind, _ in
            switch kind {
            case .delete: SetupSteps.delete().map { step($0.id, log) }
            default: [step(.engine, log), step(.bridge, log), step(.steam, log)]
            }
        }
    }
    return model
}

private let release = EngineRelease(
    channel: .beta, version: "dormison-b3",
    url: URL(string: "https://github.com/kageroumado/dormison/releases/download/b3/dormison-b3.tar.xz")!,
    sha256: String(repeating: "0", count: 64), sizeBytes: 1, notes: nil, minAppVersion: nil)

private var updatePlan: UpdatePlan {
    var plan = UpdatePlan()
    plan.engine = release
    plan.steamPatch = true
    return plan
}

@MainActor
@Suite("Main window states")
struct MainWindowStateTests {

    @Test("Not installed: the one button is a blue Install")
    func notInstalled() {
        let screen = MainScreen.make(install: .notInstalled, plan: nil, flow: nil)
        #expect(screen.button == .install)
        #expect(screen.buttonEnabled)
        #expect(screen.status == tr("Not installed"))
        #expect(screen.problem == nil && screen.progress == nil)
    }

    @Test("Installing: the step shows under the name, the button waits")
    func installing() {
        let flow = FlowState.running(.install, step: 1, of: 5, title: "Downloading the engine", detail: "Downloaded 10 MB")
        let screen = MainScreen.make(install: .notInstalled, plan: nil, flow: flow)
        #expect(screen.button == .install)
        #expect(!screen.buttonEnabled)
        #expect(!screen.gearEnabled)
        #expect(screen.status == "Downloading the engine · Downloaded 10 MB")
        #expect(screen.progress?.step == 1 && screen.progress?.of == 5)
    }

    @Test("Installed and current: the button is a grey Delete")
    func installed() {
        let screen = MainScreen.make(install: .installed(engine: "Dormison b2"), plan: UpdatePlan(), flow: nil)
        #expect(screen.button == .delete)
        #expect(screen.buttonEnabled)
        #expect(screen.status == tr("Installed · \("Dormison b2")"))
    }

    @Test("Delete waits while the window looks for updates")
    func deleteWaitsForTheCheck() {
        #expect(!MainScreen.make(install: .installed(engine: "Dormison b2"), plan: nil, flow: nil, checking: true).buttonEnabled)
        #expect(!MainScreen.make(install: .installed(engine: "Dormison b2"), plan: nil, flow: nil).buttonEnabled)
    }

    @Test("Update available: the button is Update, Delete is not offered")
    func updateAvailable() {
        let screen = MainScreen.make(install: .installed(engine: "Dormison b2"), plan: updatePlan, flow: nil)
        #expect(screen.button == .update)
        #expect(screen.buttonEnabled)
        #expect(screen.tone == .attention)
        #expect(screen.status.contains("Dormison b3") && screen.status.contains(tr("Steam patch")))
    }

    @Test("Updating: the button keeps its name and waits")
    func updating() {
        let flow = FlowState.running(.update, step: 0, of: 5, title: "Checking Rosetta", detail: nil)
        let screen = MainScreen.make(install: .installed(engine: "Dormison b2"), plan: updatePlan, flow: flow)
        #expect(screen.button == .update)
        #expect(!screen.buttonEnabled)
        #expect(screen.status == "Checking Rosetta")
    }

    @Test("Error: a problem for the system alert, and the button stays pressable")
    func error() {
        let problem = FlowProblem(cause: .offline, detail: "The Internet connection appears to be offline.")
        let flow = FlowState.failed(.install, step: 1, of: 5, title: "Downloading the engine", problem: problem)
        let screen = MainScreen.make(install: .notInstalled, plan: nil, flow: flow)
        #expect(screen.problem == problem)
        #expect(screen.problemKind == .install)
        #expect(screen.button == .install && screen.buttonEnabled)
        #expect(FlowProblem.title(.install) == tr("Couldn't install Lullaby"))
        #expect(problem.message == tr("No connection to the internet. Check it, then try again."))
    }

    // The window itself, drawn for each state at its fixed size: a state that broke the
    // layout (a crash, or a view too tall for 360×220) fails here.
    @Test("The window draws every state at 360×220", arguments: [
        "not-installed", "incomplete", "legacy", "installing", "installed", "update-available", "updating", "error",
    ])
    func draws(_ name: String) throws {
        let model = MainModel(badge: BadgeStore(defaults: defaults(), dock: { _ in }))
        switch name {
        case "not-installed":
            model.installOverride = .notInstalled
        case "incomplete":
            model.installOverride = .incomplete
        case "legacy":
            model.installOverride = .legacy
        case "installing":
            model.installOverride = .notInstalled
            model.runner.show(.running(.install, step: 1, of: 5, title: tr("Downloading the engine"),
                                       detail: SetupSteps.downloaded(10_000_000, of: 240_000_000)))
        case "installed":
            model.installOverride = .installed(engine: "Dormison b2")
            model.plan = UpdatePlan()
        case "update-available":
            model.installOverride = .installed(engine: "Dormison b2")
            model.plan = updatePlan
        case "updating":
            model.installOverride = .installed(engine: "Dormison b2")
            model.plan = updatePlan
            model.runner.show(.running(.update, step: 1, of: 5, title: tr("Downloading the engine"), detail: nil))
        default:
            model.installOverride = .notInstalled
            model.runner.show(.failed(.install, step: 4, of: 5, title: tr("Installing into Steam"),
                                      problem: FlowProblem(cause: .steamDidNotQuit, detail: "Steam did not quit")))
        }
        let renderer = ImageRenderer(content: MainView().environment(model))
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        #expect(image.width == Int(MainView.size.width) * 2)
        #expect(image.height == Int(MainView.size.height) * 2)
        #expect(SetupSteps.downloaded(0, of: 10).isEmpty)
        if let folder = ProcessInfo.processInfo.environment["LB_WINDOW_SNAPSHOTS"] {
            let url = URL(filePath: folder).appending(path: "\(name).png")
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}

@MainActor
@Suite("Main window flows")
struct MainWindowFlowTests {

    @Test("A failed step stops the flow; the runner goes on from it, not from the beginning")
    func retryResumes() async {
        let log = Log()
        await log.fail([.bridge])
        let runner = FlowRunner()
        let steps = [step(.rosetta, log), step(.engine, log), step(.bridge, log), step(.steam, log)]

        #expect(!(await runner.start(.install, steps)))
        guard case .failed(.install, 2, 4, _, let problem)? = runner.state else {
            Issue.record("not failed: \(String(describing: runner.state))"); return
        }
        #expect(problem.cause == .failed(.bridge))

        await log.fail([])
        #expect(await runner.retry())
        #expect(runner.state == .finished(.install))
        #expect(await log.ran == [.rosetta, .engine, .bridge, .bridge, .steam])
    }

    @Test("The button: Install runs, a failure raises the alert, the same button goes on")
    func installAlertThenSameButton() async {
        let log = Log()
        await log.fail([.bridge])
        let model = model(log)
        model.installOverride = .notInstalled

        await model.press()
        #expect(model.alertShown)
        #expect(model.screen.problem?.cause == .failed(.bridge))
        #expect(model.screen.button == .install)

        model.alertShown = false
        await log.fail([])
        await model.press()
        #expect(!model.alertShown)
        #expect(await log.ran == [.engine, .bridge, .bridge, .steam])
        #expect(model.runner.state == nil)
        #expect(model.showsBadge)
    }

    @Test("The button: Update runs when there is an update")
    func updateButton() async {
        let log = Log()
        let model = model(log)
        model.installOverride = .installed(engine: "Dormison b2")
        model.plan = updatePlan
        #expect(model.screen.button == .update)
        await model.press()
        #expect(await log.ran == [.engine, .bridge, .steam])
    }

    @Test("Steam running: the button asks before closing it, and runs only after Yes")
    func asksAboutSteam() async {
        let log = Log()
        let model = model(log, steam: true)
        model.installOverride = .notInstalled

        await model.press()
        #expect(model.question == .closeSteam(.install))
        #expect(await log.ran.isEmpty)

        await model.confirmCloseSteam(.install)
        #expect(await log.ran == [.engine, .bridge, .steam])
    }

    @Test("A running game stops the flow; the same button goes on once it is closed")
    func gameRunning() async {
        let log = Log()
        let game = GameSwitch()
        let model = model(log, steam: true)
        model.installOverride = .installed(engine: "Dormison b2")
        model.plan = updatePlan
        model.probe = { (await game.running, true) }

        await model.press()
        guard case .failed(.update, 0, 4, _, let problem)? = model.runner.state else {
            Issue.record("not refused: \(String(describing: model.runner.state))"); return
        }
        #expect(problem.cause == .gameRunning)
        #expect(problem.message == tr("A game is still running. Quit it, then try again."))
        #expect(model.alertShown)

        await model.press()
        #expect(await log.ran.isEmpty)

        await game.quit()
        await model.press()
        #expect(await log.ran == [.engine, .bridge, .steam])
    }

    @Test("Update closes Steam only when the engine or the Steam patch changes")
    func updateClosesSteam() {
        var plan = UpdatePlan()
        plan.app = "1.2.0"
        #expect(!MainModel.closesSteam(.update, plan: plan, legacy: false))
        #expect(MainModel.closesSteam(.update, plan: plan, legacy: true), "the move from NotProton closes Steam")
        plan.steamPatch = true
        #expect(MainModel.closesSteam(.update, plan: plan, legacy: false))
        #expect(MainModel.closesSteam(.install, plan: nil))
        #expect(!MainModel.closesSteam(.steamUpdates, plan: nil))
    }

    @Test("Install and Update are one flow that checks every part: Rosetta, engine, bridge, signatures, Steam")
    func oneFlow() {
        // This Mac's own files must not decide the steps (LegacyMigrationTests covers the move).
        var env = SetupEnvironment()
        env.legacy = nil
        #expect(SetupSteps.setup(nil, env).map(\.id) == [.rosetta, .engine, .bridge, .signatures, .steam])
        var plan = updatePlan
        #expect(SetupSteps.setup(plan, env).map(\.id) == [.rosetta, .engine, .bridge, .signatures, .steam])
        plan.app = "1.2.0"
        #expect(SetupSteps.setup(plan, env).map(\.id) == [.rosetta, .engine, .bridge, .signatures, .steam, .app])
    }

    @Test("Known causes become plain sentences")
    func problems() {
        #expect(FlowProblem(SteamBundle.StillRunning(seconds: 30), step: .steam).cause == .steamDidNotQuit)
        #expect(FlowProblem(URLError(.notConnectedToInternet), step: .engine).cause == .offline)
        #expect(FlowProblem(StepFailure(step: "x", detail: SteamInstaller.gameRunning), step: .steam).cause == .gameRunning)
        #expect(FlowProblem(WriteRefused(path: "/Applications/Steam.app"), step: .steam).cause == .appManagement)
        #expect(FlowProblem(KnownProblem(.noBridgeYet, log: "x"), step: .bridge).message
            == tr("The Steam bridge for this engine isn't ready yet. Try again later."))
        for id in FlowStep.ID.allCases { #expect(!FlowProblem.failedText(id).isEmpty) }
        for kind in FlowKind.allCases { #expect(!FlowProblem.title(kind).isEmpty) }
    }
}

@MainActor
@Suite("Badge")
struct BadgeTests {

    @Test("No badge before the first install")
    func noneBefore() {
        let badge = BadgeStore(defaults: defaults(), dock: { _ in })
        #expect(!badge.isShowing)
        #expect(!badge.gearOpened())
    }

    @Test("The first install puts it on ⚙︎ and the Dock; opening ⚙︎ takes it off for good")
    func onceThenGone() {
        let store = defaults()
        var dock: [String?] = []
        let badge = BadgeStore(defaults: store, dock: { dock.append($0) })
        badge.installFinished()
        #expect(badge.isShowing)
        #expect(dock.last == "1")

        #expect(badge.gearOpened())
        #expect(!badge.isShowing)
        #expect(dock.last == .some(nil))
        #expect(!badge.gearOpened())

        badge.installFinished()
        #expect(!badge.isShowing)
        #expect(!BadgeStore(defaults: store, dock: { _ in }).isShowing)
    }

    @Test("The model lights the Steam updates row only the one time")
    func modelHighlight() {
        let model = MainModel(badge: BadgeStore(defaults: defaults(), dock: { _ in }))
        model.badge.installFinished()
        model.showsBadge = model.badge.isShowing
        model.gearOpened()
        #expect(model.highlightSteamUpdates)
        #expect(!model.showsBadge)
        model.gearOpened()
        #expect(!model.highlightSteamUpdates)
    }
}

@MainActor
@Suite("Delete")
struct DeleteTests {

    @Test("Delete asks first; Yes returns Steam and removes the files, then the button is Install")
    func throughTheQuestion() async {
        let log = Log()
        let model = model(log, steam: true)
        model.installOverride = .installed(engine: "Dormison b2")
        model.plan = UpdatePlan()
        #expect(model.screen.button == .delete)

        await model.press()
        #expect(model.question == .delete)
        #expect(await log.ran.isEmpty)
        await model.confirmDelete()
        #expect(model.question == nil)
        #expect(await log.ran == [.removeSteam, .removeFiles])

        model.installOverride = .notInstalled
        #expect(model.screen.button == .install)
    }

    @Test("Delete never has a prefixes step")
    func noPrefixes() {
        #expect(SetupSteps.delete().map(\.id) == [.removeSteam, .removeFiles])
    }

    @Test("Delete keeps game settings, the toolkit, Steam's backups and the logs")
    func keeps() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "np-delete-\(UUID().uuidString)")
        let support = root.appending(path: "lullaby")
        let caches = root.appending(path: "caches")
        defer { try? FileManager.default.removeItem(at: root) }
        let names = ["runners", "bridge", "bridges", "signatures", "manifests", "mullion", "renderers",
                     "settings", "d3dmetal", "backups", "app.log", "lullaby.log", "overlay-shim.dylib"]
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        for name in names {
            let url = support.appending(path: name)
            if name.contains(".") {
                try Data("x".utf8).write(to: url)
            } else {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)

        let targets = Deletion.targets(support: support, caches: caches)
        try Deletion.removeFiles(targets)

        let left = Set(try FileManager.default.contentsOfDirectory(atPath: support.path(percentEncoded: false)))
        #expect(left == ["settings", "d3dmetal", "backups", "app.log", "lullaby.log"])
        #expect(!FileManager.default.fileExists(atPath: caches.path(percentEncoded: false)))
        #expect(targets.allSatisfy { !$0.path(percentEncoded: false).contains("compatdata") })
    }
}
