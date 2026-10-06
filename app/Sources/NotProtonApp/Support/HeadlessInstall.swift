// `NotProtonApp --install-into-steam`: what the Install button does, without the window,
// for setting a machine up while nobody is at it (Phase 1). The CrossOver runner step is
// left out: the engine is Dormison, installed by `--engine install` (HeadlessEngine). Prints each step
// and exits 0 when NotProton is in Steam and every component is in place, 1 otherwise.
// With --reinstall it patches Steam again even when it already carries this build.

import Foundation

enum HeadlessInstall {
    static let flag = "--install-into-steam"
    static let reinstallFlag = "--reinstall"

    private final class ExitCode: @unchecked Sendable {
        var value: Int32 = 1
    }

    static func runIfRequested(arguments: [String] = CommandLine.arguments) {
        guard arguments.contains(flag) else { return }

        let force = arguments.contains(reinstallFlag)
        let code = ExitCode()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let result = try SteamInstaller.run(
                    force: force, report: { print("install: \($0.label)") }
                )
                print("install: NotProton \(result.version) in Steam, Steam was "
                    + "\(result.stoppedClient ? "stopped" : "not running"), "
                    + "\(result.bridgeStaged) bridge file(s) staged, "
                    + "\(result.signatureDatabases) signature database(s), "
                    + "build \(result.build ?? "unknown")")

                if PayloadInspector.inspect().missing.contains(where: { $0.origin.isFetchable }) {
                    print("install: downloading Valve components")
                    _ = try await ValveFetcher.run { print("install: \($0.label)") }
                }

                let payload = PayloadInspector.inspect()
                if payload.isComplete {
                    print("install: components complete (\(payload.present) of \(payload.expected))")
                    code.value = 0
                } else {
                    print("install: components incomplete, missing "
                        + payload.missing.map(\.path).joined(separator: ", "))
                }
            } catch {
                print("install failed: \(error.localizedDescription)")
            }
            done.signal()
        }
        done.wait()
        exit(code.value)
    }
}
