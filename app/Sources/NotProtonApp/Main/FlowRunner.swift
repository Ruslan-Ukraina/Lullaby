// The steps behind the main window's buttons (Phase 8, ROADMAP §9).
//
// Install, Update, Delete and the actions under ⚙︎ are each a list of steps run in
// turn. The window shows the step that runs; a failure stops the list on that step,
// and Retry runs the list again from it, so a download already done is not repeated.

import Foundation
import Observation

/// What a list of steps is for: the window words its progress and outcome by it.
enum FlowKind: String, Sendable, CaseIterable {
    case install
    case update
    case reinstall
    case delete
    case rollbackEngine
    case rollbackBridge
    case addToolkit
    case steamUpdates
}

/// One step of a flow. `id` names it in the log and the tests; `title` is shown.
struct FlowStep: Identifiable, Sendable {
    enum ID: String, Sendable, CaseIterable {
        case waitForGame, rosetta, engine, bridge, signatures, steam, app
        case quitSteam, removeSteam, removeFiles, removePrefixes
        case rollbackEngine, rollbackBridge, toolkit, steamUpdates
    }

    let id: ID
    let title: String
    let run: @Sendable (_ detail: @escaping @Sendable (String) -> Void) async throws -> Void

    init(
        _ id: ID, _ title: String,
        run: @escaping @Sendable (_ detail: @escaping @Sendable (String) -> Void) async throws -> Void
    ) {
        self.id = id
        self.title = title
        self.run = run
    }
}

/// Where a flow is: running a step, stopped on one, or finished.
enum FlowState: Equatable, Sendable {
    case running(FlowKind, step: Int, of: Int, title: String, detail: String?)
    case failed(FlowKind, step: Int, of: Int, title: String, problem: FlowProblem)
    case finished(FlowKind)
}

@MainActor
@Observable
final class FlowRunner {

    private(set) var state: FlowState?
    private var kind: FlowKind?
    private var steps: [FlowStep] = []
    /// Bumped by every start, so a late progress line of a finished run is dropped.
    private var generation = 0

    var isRunning: Bool {
        if case .running? = state { return true }
        return false
    }

    var canRetry: Bool {
        if case .failed? = state { return true }
        return false
    }

    /// Runs `steps` from the first; returns true when every one finished.
    @discardableResult
    func start(_ kind: FlowKind, _ steps: [FlowStep]) async -> Bool {
        guard !isRunning else {
            AppLog.note("flow: \(kind.rawValue) refused, \(self.kind?.rawValue ?? "?") is running")
            return false
        }
        self.kind = kind
        self.steps = steps
        AppLog.note("flow: \(kind.rawValue) begin, steps \(steps.map(\.id.rawValue).joined(separator: " "))")
        return await run(from: 0)
    }

    /// Runs the failed flow again from the step that failed.
    @discardableResult
    func retry() async -> Bool {
        guard case .failed(_, let step, _, _, _)? = state else { return false }
        AppLog.note("flow: \(kind?.rawValue ?? "?") retry from \(steps[step].id.rawValue)")
        return await run(from: step)
    }

    /// Forgets a finished or failed flow, so the window shows the plain status again.
    func dismiss() {
        guard !isRunning else { return }
        state = nil
    }

    /// Puts the window in a state without running anything: tests and previews.
    func show(_ state: FlowState) {
        self.state = state
    }

    private func run(from first: Int) async -> Bool {
        guard let kind else { return false }
        generation += 1
        let run = generation
        for index in first..<steps.count {
            let step = steps[index]
            state = .running(kind, step: index, of: steps.count, title: step.title, detail: nil)
            AppLog.note("flow: \(kind.rawValue) step \(step.id.rawValue)")
            do {
                try await step.run { [weak self] detail in
                    Task { @MainActor in
                        guard let self, self.generation == run,
                              case .running(let k, let i, let n, let t, _)? = self.state, i == index
                        else { return }
                        self.state = .running(k, step: i, of: n, title: t, detail: detail)
                    }
                }
            } catch {
                let problem = FlowProblem(error, step: step.id)
                AppLog.note("flow: \(kind.rawValue) failed at \(step.id.rawValue): \(error.localizedDescription)")
                state = .failed(kind, step: index, of: steps.count, title: step.title, problem: problem)
                return false
            }
        }
        AppLog.note("flow: \(kind.rawValue) done")
        state = .finished(kind)
        return true
    }
}
