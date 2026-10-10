import AppKit
import Foundation
import SwiftUI
import Testing

@testable import NotProtonApp

// Phase 8 (ROADMAP §9.8): the window's six states, the flows behind its buttons, the
// badge and Delete. Nothing here touches Steam, the engine or the network: the steps
// and the probes are stand-ins.

private func step(_ id: FlowStep.ID, _ log: Log, fail: Bool = false) -> FlowStep {
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
    let name = "notproton-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private let release = EngineRelease(
    channel: .beta, version: "dormison-b3",
    url: URL(string: "https://github.com/kageroumado/dormison/releases/download/b3/dormison-b3.tar.xz")!,
    sha256: String(repeating: "0", count: 64), sizeBytes: 1, notes: nil, minAppVersion: nil)

@MainActor
@Suite("Main window states")
struct MainWindowStateTests {

    @Test("Not installed: blue Install, no Update")
    func notInstalled() {
        let screen = MainScreen.make(install: .notInstalled, plan: nil, flow: nil)
        #expect(screen.primary == .install)
        #expect(screen.primaryEnabled)
        #expect(!screen.showsUpdate)
        #expect(screen.status == tr("Not installed"))
        #expect(screen.message == .none)
    }

    @Test("Installing: the step shows, nothing else can be pressed")
    func installing() {
        let flow = FlowState.running(.install, step: 1, of: 5, title: "Downloading the engine", detail: "Downloaded 10 MB")
        let screen = MainScreen.make(install: .notInstalled, plan: nil, flow: flow)
        #expect(screen.message == .progress(title: "Downloading the engine", detail: "Downloaded 10 MB", step: 1, of: 5))
        #expect(!screen.primaryEnabled)
        #expect(!screen.gearEnabled)
        #expect(screen.status == tr("Installing…"))
    }

    @Test("Installed: grey Delete, Update shown but off when nothing is new")
    func installed() {
        let screen = MainScreen.make(install: .installed(engine: "Dormison b2"), plan: UpdatePlan(), flow: nil)
        #expect(screen.primary == .delete)
        #expect(screen.showsUpdate)
        #expect(!screen.updateEnabled)
        #expect(screen.status.contains("Dormison b2"))
        #expect(screen.tone == .normal)
    }

    @Test("Update available: Update can be pressed, the status names what is new")
    func updateAvailable() {
        var plan = UpdatePlan()
        plan.engine = release
        plan.steamPatch = true
        let screen = MainScreen.make(install: .installed(engine: "Dormison b2"), plan: plan, flow: nil)
        #expect(screen.updateEnabled)
        #expect(screen.tone == .attention)
        #expect(screen.status.contains("Dormison b3"))
        #expect(screen.status.contains(tr("Steam patch")))
    }

    @Test("Updating: Update and Delete wait")
    func updating() {
        var plan = UpdatePlan()
        plan.bridge = nil
        plan.steamPatch = true
        let flow = FlowState.running(.update, step: 0, of: 2, title: "Getting Steam support files", detail: nil)
        let screen = MainScreen.make(install: .installed(engine: "Dormison b2"), plan: plan, flow: flow)
        #expect(!screen.updateEnabled)
        #expect(!screen.primaryEnabled)
        #expect(screen.status == tr("Updating…"))
    }

    @Test("Error: a plain sentence and Retry")
    func error() {
        let problem = FlowProblem(cause: .offline, detail: "The Internet connection appears to be offline.")
        let flow = FlowState.failed(.install, step: 1, of: 5, title: "Downloading the engine", problem: problem)
        let screen = MainScreen.make(install: .notInstalled, plan: nil, flow: flow)
        #expect(screen.message == .problem(problem))
        #expect(screen.tone == .problem)
        #expect(screen.primaryEnabled)
        #expect(problem.message == tr("No connection to the internet. Check it, then press Retry."))
    }

    @Test("Install's last word offers Open Steam")
    func doneOffersSteam() {
        let screen = MainScreen.make(install: .installed(engine: "Dormison b2"), plan: UpdatePlan(), flow: .finished(.install))
        #expect(screen.message == .done(tr("Done! Open Steam and start a Windows game."), openSteam: true))
        let deleted = MainScreen.make(install: .notInstalled, plan: nil, flow: .finished(.delete))
        guard case .done(_, let openSteam) = deleted.message else { Issue.record("no outcome"); return }
        #expect(!openSteam)
    }

    // The window itself, drawn for each state at its fixed size: a state that broke the
    // layout (a crash, or a view too tall for 360×220) fails here.
    @Test("The window draws every state at 360×220", arguments: [
        "not-installed", "installing", "installed", "update-available", "updating", "error",
    ])
    func draws(_ name: String) throws {
        let model = MainModel(badge: BadgeStore(defaults: defaults(), dock: { _ in }))
        var plan = UpdatePlan()
        switch name {
        case "not-installed":
            model.installOverride = .notInstalled
        case "installing":
            model.installOverride = .notInstalled
            model.runner.show(.running(.install, step: 1, of: 5, title: tr("Downloading the engine"),
                                       detail: SetupSteps.downloaded(10_000_000, of: 240_000_000)))
        case "installed":
            model.installOverride = .installed(engine: "Dormison b2")
            model.plan = plan
        case "update-available":
            model.installOverride = .installed(engine: "Dormison b2")
            plan.engine = release
            model.plan = plan
        case "updating":
            model.installOverride = .installed(engine: "Dormison b2")
            plan.engine = release
            model.plan = plan
            model.runner.show(.running(.update, step: 1, of: 3, title: tr("Downloading the engine"), detail: nil))
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
        if let folder = ProcessInfo.processInfo.environment["NP_WINDOW_SNAPSHOTS"] {
            let url = URL(filePath: folder).appending(path: "\(name).png")
            let rep = NSBitmapImageRep(cgImage: image)
            try rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
}

@MainActor
@Suite("Main window flows")
struct MainWindowFlowTests {

    @Test("A failed step stops the flow; Retry starts from it, not from the beginning")
    func retryResumes() async {
        let log = Log()
        await log.fail([.bridge])
        let runner = FlowRunner()
        let steps = [step(.rosetta, log), step(.engine, log), step(.bridge, log), step(.steam, log)]

        let first = await runner.start(.install, steps)
        #expect(!first)
        guard case .failed(.install, let index, 4, _, let problem)? = runner.state else {
            Issue.record("not failed: \(String(describing: runner.state))"); return
        }
        #expect(index == 2)
        #expect(problem.cause == .failed(.bridge))
        #expect(problem.message == FlowProblem.failedText(.bridge))

        await log.fail([])
        let second = await runner.retry()
        #expect(second)
        #expect(runner.state == .finished(.install))
        #expect(await log.ran == [.rosetta, .engine, .bridge, .bridge, .steam])
    }

    @Test("Install runs its steps, then puts the badge up once")
    func installBadges() async {
        let log = Log()
        let store = defaults()
        var dock: [String?] = []
        let model = MainModel(badge: BadgeStore(defaults: store, dock: { dock.append($0) }))
        model.steps = { kind, _ in kind == .install ? [step(.engine, log), step(.steam, log)] : [] }
        model.probe = { (false, false) }
        model.findUpdates = { _ in UpdatePlan() }

        await model.pressInstall()
        #expect(model.runner.state == .finished(.install))
        #expect(await log.ran == [.engine, .steam])
        #expect(model.showsBadge)
        #expect(dock.last == "1")
    }

    @Test("Steam running: Install asks before closing it, and runs only after Yes")
    func asksAboutSteam() async {
        let log = Log()
        let model = MainModel(badge: BadgeStore(defaults: defaults(), dock: { _ in }))
        model.steps = { _, _ in [step(.steam, log)] }
        model.probe = { (false, true) }
        model.findUpdates = { _ in UpdatePlan() }

        await model.pressInstall()
        #expect(model.question == .closeSteam(.install))
        #expect(await log.ran.isEmpty)

        await model.confirmCloseSteam(.install)
        #expect(await log.ran == [.steam])
    }

    @Test("A running game stops every flow with a plain sentence; Retry goes on once it is closed")
    func gameRunning() async {
        let log = Log()
        let game = GameSwitch()
        let model = MainModel(badge: BadgeStore(defaults: defaults(), dock: { _ in }))
        model.steps = { _, _ in [step(.steam, log)] }
        model.probe = { (await game.running, true) }
        model.findUpdates = { _ in UpdatePlan() }

        await model.pressUpdate()
        guard case .failed(.update, 0, 2, _, let problem)? = model.runner.state else {
            Issue.record("not refused: \(String(describing: model.runner.state))"); return
        }
        #expect(problem.cause == .gameRunning)
        #expect(await log.ran.isEmpty)

        await model.retry()
        #expect(await log.ran.isEmpty)

        await game.quit()
        await model.retry()
        #expect(model.runner.state == .finished(.update))
        #expect(await log.ran == [.steam])
    }

    @Test("Update closes Steam only when the engine or the Steam patch changes")
    func updateClosesSteam() {
        var plan = UpdatePlan()
        plan.app = "1.2.0"
        #expect(!MainModel.closesSteam(.update, plan: plan))
        plan.steamPatch = true
        #expect(MainModel.closesSteam(.update, plan: plan))
        #expect(MainModel.closesSteam(.install, plan: nil))
        #expect(!MainModel.closesSteam(.rollbackBridge, plan: nil))
    }

    @Test("Update's steps: only what is new, the bridge checked again after an engine")
    func updateSteps() {
        var plan = UpdatePlan()
        #expect(SetupSteps.update(plan).map(\.id) == [.signatures])
        plan.steamPatch = true
        plan.app = "1.2.0"
        #expect(SetupSteps.update(plan).map(\.id) == [.signatures, .steam, .app])
        plan.engine = release
        #expect(SetupSteps.update(plan).map(\.id) == [.signatures, .engine, .bridge, .steam, .app])
    }

    @Test("Install is the onboarding: Rosetta, engine, bridge, signatures, Steam")
    func installOrder() {
        #expect(SetupSteps.install().map(\.id) == [.rosetta, .engine, .bridge, .signatures, .steam])
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
        // A new start of the app keeps it off.
        #expect(!BadgeStore(defaults: store, dock: { _ in }).isShowing)
    }

    @Test("The model lights the Steam updates row only the one time")
    func modelHighlight() {
        let store = defaults()
        let model = MainModel(badge: BadgeStore(defaults: store, dock: { _ in }))
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

    @Test("Delete asks with the prefixes box off")
    func asksWithBoxOff() {
        let model = MainModel(badge: BadgeStore(defaults: defaults(), dock: { _ in }))
        model.deletePrefixes = true
        model.pressDelete()
        #expect(model.question == .delete)
        #expect(!model.deletePrefixes)
        #expect(!MainModel.realSteps(.delete, model).map(\.id).contains(.removePrefixes))
    }

    @Test("Game prefixes go only when the box is ticked")
    func prefixesOnlyWhenTicked() {
        #expect(SetupSteps.delete(prefixes: false).map(\.id) == [.removeSteam, .removeFiles])
        #expect(SetupSteps.delete(prefixes: true).map(\.id) == [.removeSteam, .removeFiles, .removePrefixes])
    }

    @Test("Delete keeps game settings, the toolkit, Steam's backups and the logs")
    func keeps() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "np-delete-\(UUID().uuidString)")
        let support = root.appending(path: "notproton")
        let caches = root.appending(path: "caches")
        defer { try? FileManager.default.removeItem(at: root) }
        let names = ["runners", "bridge", "bridges", "signatures", "manifests", "mullion", "renderers",
                     "settings", "d3dmetal", "backups", "app.log", "notproton.log", "overlay-shim.dylib"]
        for name in names {
            let url = support.appending(path: name)
            if name.contains(".") {
                try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
                try Data("x".utf8).write(to: url)
            } else {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
        }
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)

        let targets = Deletion.targets(support: support, caches: caches)
        try Deletion.removeFiles(targets)

        let left = Set(try FileManager.default.contentsOfDirectory(atPath: support.path(percentEncoded: false)))
        #expect(left == ["settings", "d3dmetal", "backups", "app.log", "notproton.log"])
        #expect(!FileManager.default.fileExists(atPath: caches.path(percentEncoded: false)))
        // Prefixes live in Steam's libraries, never under notproton/.
        #expect(targets.allSatisfy { !$0.path(percentEncoded: false).contains("compatdata") })
    }
}
