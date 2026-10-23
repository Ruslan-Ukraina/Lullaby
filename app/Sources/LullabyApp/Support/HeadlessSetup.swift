// `LullabyApp --setup`: the main window's Install button without the window, the same
// steps in the same order (SetupSteps.setup), on the real system: the move from NotProton
// when it is still there, Rosetta, engine, bridge, Steam support files, Install into
// Steam. Steam is closed the soft way when a step needs it. Prints each step; exits 0
// when every step finished, 1 at the first that failed (run it again to go on).

import Foundation

enum HeadlessSetup {
    static let flag = "--setup"

    private final class ExitCode: @unchecked Sendable {
        var value: Int32 = 1
    }

    static func runIfRequested(arguments: [String] = CommandLine.arguments) {
        guard arguments.contains(flag) else { return }
        let code = ExitCode()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let steps = SetupSteps.setup(nil)
            AppLog.note("setup: headless, steps \(steps.map(\.id.rawValue).joined(separator: " "))")
            var failed = false
            for (index, step) in steps.enumerated() {
                print("setup: [\(index + 1)/\(steps.count)] \(step.id.rawValue): \(step.title)")
                do {
                    try await step.run { detail in print("setup:   \(detail)") }
                } catch {
                    print("setup: \(step.id.rawValue) failed: \(error.localizedDescription)")
                    AppLog.note("setup: \(step.id.rawValue) failed: \(error.localizedDescription)")
                    failed = true
                    break
                }
            }
            if !failed {
                print("setup: done")
                AppLog.note("setup: headless done")
                code.value = 0
            }
            done.signal()
        }
        done.wait()
        AppLog.flush()
        exit(code.value)
    }
}
