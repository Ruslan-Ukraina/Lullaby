// What the main window shows, worked out from plain values (ROADMAP §9.1), so each of
// its states (not installed, installing, installed, update available, updating, error)
// is a value the tests can make and check without Steam or a network.

import Foundation

/// Lullaby's place on this Mac, read from Status's snapshot.
enum InstallState: Equatable, Sendable {
    case checking
    case steamMissing
    case notInstalled
    /// Steam has Lullaby but something is missing (no engine, another account's copy).
    case incomplete
    /// Steam carries another add-on in Lullaby's place.
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

/// The window's one button and the line under the name (owner's edit to Phase 8): not
/// installed → Install, an update → Update, everything current → Delete. Delete is not
/// offered while there is an update, nor while the window still looks for one.
struct MainScreen: Equatable {
    enum Button: Equatable {
        case install, update, delete

        var kind: FlowKind {
            switch self {
            case .install: .install
            case .update: .update
            case .delete: .delete
            }
        }
    }

    enum Tone: Equatable { case normal, attention, problem }

    var status: String
    var tone: Tone
    var button: Button
    var buttonEnabled: Bool
    /// The running step: its place in the flow, shown as a bar under the button.
    var progress: (step: Int, of: Int)?
    /// A failed flow, shown as a system alert; pressing the button again retries it.
    var problem: FlowProblem?
    var problemKind: FlowKind?
    var gearEnabled: Bool

    static func == (a: MainScreen, b: MainScreen) -> Bool {
        a.status == b.status && a.tone == b.tone && a.button == b.button && a.buttonEnabled == b.buttonEnabled
            && a.progress?.step == b.progress?.step && a.progress?.of == b.progress?.of
            && a.problem == b.problem && a.problemKind == b.problemKind && a.gearEnabled == b.gearEnabled
    }

    static func make(install: InstallState, plan: UpdatePlan?, flow: FlowState?, checking: Bool = false) -> MainScreen {
        let busy: Bool = if case .running? = flow { true } else { false }
        let button: Button = switch install {
        case .installed: plan?.isEmpty == false ? .update : .delete
        case .foreign: .delete
        default: .install
        }
        var screen = MainScreen(
            status: statusLine(install, plan: plan, checking: checking),
            tone: tone(install, plan: plan),
            button: button,
            buttonEnabled: !busy && install != .checking
                && !(button == .delete && install != .foreign && (checking || plan == nil)),
            progress: nil,
            problem: nil,
            problemKind: nil,
            gearEnabled: !busy
        )
        switch flow {
        case .running(let kind, let step, let count, let title, let detail)?:
            screen.button = Self.button(for: kind, else: button)
            screen.status = detail.map { $0.isEmpty ? title : "\(title) · \($0)" } ?? title
            screen.tone = .normal
            screen.progress = (step, count)
        case .failed(let kind, _, _, _, let problem)?:
            screen.problem = problem
            screen.problemKind = kind
        case .finished, nil:
            break
        }
        return screen
    }

    /// While a flow runs, the button keeps the name of what it does.
    private static func button(for kind: FlowKind, else fallback: Button) -> Button {
        switch kind {
        case .install, .reinstall: .install
        case .update: .update
        case .delete: .delete
        case .addToolkit, .steamUpdates: fallback
        }
    }

    static func statusLine(_ install: InstallState, plan: UpdatePlan?, checking: Bool = false) -> String {
        switch install {
        case .checking: tr("Checking…")
        case .steamMissing: tr("Steam isn't installed")
        case .notInstalled: tr("Not installed")
        case .incomplete: tr("Not fully installed. Press Install to finish.")
        case .foreign: tr("Steam has another add-on installed")
        case .installed(let engine):
            if let plan, !plan.isEmpty {
                tr("Update available: \(plan.parts.formatted(.list(type: .and)))")
            } else if checking {
                tr("Checking for updates…")
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

    static func label(_ button: Button) -> String {
        switch button {
        case .install: tr("Install")
        case .update: tr("Update")
        case .delete: tr("Delete…")
        }
    }
}
