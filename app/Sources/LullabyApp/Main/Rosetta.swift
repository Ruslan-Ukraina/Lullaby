// Step 1 of Install (ROADMAP §9.2): Dormison's Wine is an Intel program, so it needs
// Rosetta. Installing Rosetta takes an administrator, which Lullaby never asks for
// itself (CLAUDE.md §3, no sudo): it opens a tiny Intel-only helper app instead, and
// macOS shows its own "install Rosetta?" question. The helper quits as soon as it runs.

import AppKit
import Foundation

enum Rosetta {
    /// Present once Rosetta is installed (the same file `arch -x86_64` needs).
    static let runtime = URL(filePath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime")

    /// The Intel-only helper make puts inside Lullaby.app.
    static var helper: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Helpers/Lullaby Rosetta Check.app")
    }

    static func isInstalled(runtime: URL = runtime) -> Bool {
        FileManager.default.fileExists(atPath: runtime.path(percentEncoded: false))
    }

    /// Returns when Rosetta is there; asks macOS to install it when it is not, and waits
    /// up to `patience` for the player to agree.
    static func ensure(
        runtime: URL = runtime,
        helper: URL = helper,
        patience: Duration = .seconds(600),
        poll: Duration = .seconds(2),
        open: @Sendable (URL) async -> Void = Rosetta.open
    ) async throws {
        if isInstalled(runtime: runtime) { return }
        AppLog.note("rosetta: missing, asking macOS to install it")
        guard FileManager.default.fileExists(atPath: helper.path(percentEncoded: false)) else {
            throw KnownProblem(.rosettaMissing, log: "Rosetta is missing and the helper app is not in this build")
        }
        await open(helper)
        let clock = ContinuousClock()
        let deadline = clock.now + patience
        while clock.now < deadline {
            if isInstalled(runtime: runtime) {
                AppLog.note("rosetta: installed")
                return
            }
            try await Task.sleep(for: poll)
        }
        throw KnownProblem(.rosettaMissing, log: "Rosetta was not installed")
    }

    @Sendable
    static func open(_ helper: URL) async {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: helper, configuration: configuration)
        } catch {
            AppLog.note("rosetta: helper did not start: \(error.localizedDescription)")
        }
    }
}
