// What the main window shows, worked out from plain values (ROADMAP §9.1), so each of
// its states (not installed, installing, installed, update available, updating, error)
// is a value the tests can make and check without Steam or a network.

import Foundation

/// NotProton's place on this Mac, read from Status's snapshot.
enum InstallState: Equatable, Sendable {
    case checking
    case steamMissing
    case notInstalled
    /// Steam has NotProton but something is missing (no engine, another account's copy).
    case incomplete
    /// Steam carries another add-on in NotProton's place.
    case foreign
    case installed(engine: String?)

    static func from(_ snapshot: StatusSnapshot?) -> InstallState {
        guard let snapshot else { return .checking }
        let engine: String? = if case .engine(let version) = snapshot.runner {
            EngineStore.displayName(version)
        } else { nil }
        switch snapshot.steam {
        case .steamMissing: return .steamMissing
        case .notInstalled: return .notInstalled
        case .foreign: return .foreign
        case .installed, .outdated:
            return engine == nil || !snapshot.payload.isComplete ? .incomplete : .installed(engine: engine)
        }
    }

    var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }
}

struct MainScreen: Equatable {
    enum Primary: Equatable { case install, delete }
    enum Tone: Equatable { case normal, attention, problem }

    enum Message: Equatable {
        case none
        case progress(title: String, detail: String?, step: Int, of: Int)
        case problem(FlowProblem)
        case done(String, openSteam: Bool)
    }

    var status: String
    var tone: Tone
    var primary: Primary
    var primaryEnabled: Bool
    /// Update is shown once NotProton is installed, and pressable when there is something.
    var showsUpdate: Bool
    var updateEnabled: Bool
    var message: Message
    var gearEnabled: Bool

    static func make(install: InstallState, plan: UpdatePlan?, flow: FlowState?) -> MainScreen {
        let busy: Bool = if case .running? = flow { true } else { false }
        let installed = install.isInstalled
        var screen = MainScreen(
            status: statusLine(install, plan: plan),
            tone: tone(install, plan: plan),
            primary: installed || install == .foreign ? .delete : .install,
            primaryEnabled: !busy && install != .checking,
            showsUpdate: installed,
            updateEnabled: !busy && installed && plan?.isEmpty == false,
            message: .none,
            gearEnabled: !busy
        )
        switch flow {
        case .running(let kind, let step, let count, let title, let detail)?:
            screen.status = runningLine(kind)
            screen.tone = .normal
            screen.message = .progress(title: title, detail: detail?.isEmpty == true ? nil : detail,
                                       step: step, of: count)
        case .failed(_, _, _, _, let problem)?:
            screen.tone = .problem
            screen.message = .problem(problem)
        case .finished(let kind)?:
            screen.message = .done(doneLine(kind), openSteam: kind == .install || kind == .reinstall)
        case nil:
            break
        }
        return screen
    }

    static func statusLine(_ install: InstallState, plan: UpdatePlan?) -> String {
        switch install {
        case .checking: tr("Checking…")
        case .steamMissing: tr("Steam isn't installed")
        case .notInstalled: tr("Not installed")
        case .incomplete: tr("Not fully installed. Press Install to finish.")
        case .foreign: tr("Steam has another add-on installed")
        case .installed(let engine):
            if let plan, !plan.isEmpty {
                tr("Update available: \(plan.parts.formatted(.list(type: .and)))")
            } else if let engine {
                tr("Installed · \(engine)")
            } else {
                tr("Installed")
            }
        }
    }

    private static func tone(_ install: InstallState, plan: UpdatePlan?) -> Tone {
        switch install {
        case .steamMissing, .foreign, .incomplete: .problem
        case .installed: plan?.isEmpty == false ? .attention : .normal
        default: .normal
        }
    }

    static func runningLine(_ kind: FlowKind) -> String {
        switch kind {
        case .install: tr("Installing…")
        case .update: tr("Updating…")
        case .reinstall: tr("Reinstalling…")
        case .delete: tr("Deleting…")
        case .rollbackEngine, .rollbackBridge: tr("Rolling back…")
        case .addToolkit: tr("Adding the Game Porting Toolkit…")
        case .steamUpdates: tr("Changing Steam updates…")
        }
    }

    static func doneLine(_ kind: FlowKind) -> String {
        switch kind {
        case .install: tr("Done! Open Steam and start a Windows game.")
        case .update: tr("Everything is up to date.")
        case .reinstall: tr("Reinstalled.")
        case .delete: tr("NotProton is deleted. Steam is back to how it was.")
        case .rollbackEngine: tr("Back on the previous engine.")
        case .rollbackBridge: tr("Back on the previous Steam bridge.")
        case .addToolkit: tr("Game Porting Toolkit added. Pick D3DMetal in a game's settings in Steam.")
        case .steamUpdates: tr("Saved.")
        }
    }
}
