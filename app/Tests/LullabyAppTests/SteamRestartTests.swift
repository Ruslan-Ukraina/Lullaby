import Foundation
import Testing

@testable import LullabyApp

// Owner, 11.10: after an app update Lullaby asked to close Steam for the "Steam patch",
// he agreed, and Steam did not come back. The patch was only the recorded version (the
// dylib was the same), and nothing opened Steam again.

@MainActor
@Suite("Steam closed by a flow")
struct SteamRestartTests {
    @Test("Only the version differing does not close Steam; a new dylib does")
    func versionOnly() {
        var plan = UpdatePlan()
        plan.steamPatch = true
        plan.steamPatchQuits = false
        #expect(!plan.closesSteam)
        #expect(!MainModel.closesSteam(.update, plan: plan, legacy: false))
        plan.steamPatchQuits = true
        #expect(plan.closesSteam)
    }

    func model(steamAfter: Bool) -> (MainModel, Box) {
        let name = "lullaby-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let model = MainModel(badge: BadgeStore(defaults: defaults, dock: { _ in }))
        let box = Box()
        model.findUpdates = { _ in UpdatePlan() }
        model.probe = { (false, steamAfter) }
        model.steps = { _, _ in [FlowStep(.steam, "steam") { _ in }] }
        model.openSteam = { box.opened += 1 }
        return (model, box)
    }

    final class Box { var opened = 0 }

    @Test("Steam closed with the owner's yes opens again when the flow is done")
    func reopens() async {
        let (model, box) = model(steamAfter: false)
        await model.confirmCloseSteam(.reinstall)
        #expect(box.opened == 1)
    }

    @Test("Steam already open again is left alone")
    func alreadyOpen() async {
        let (model, box) = model(steamAfter: true)
        await model.confirmCloseSteam(.reinstall)
        #expect(box.opened == 0)
    }

    @Test("A flow that never asked does not open Steam")
    func notAsked() async {
        let (model, box) = model(steamAfter: false)
        await model.pressReinstall()
        #expect(box.opened == 0)
    }
}
