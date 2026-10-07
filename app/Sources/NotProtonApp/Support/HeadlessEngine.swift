// `NotProtonApp --engine <command>`: the Engine section's buttons without the
// window, for checking the updater end to end while nobody is at the Mac.
//
//   --engine check          read the signed list and say what the channel offers
//   --engine install        install the channel's release unless it is current
//   --engine reinstall      install it even when it is current
//   --engine rollback       switch back to the previous engine
// Options: --channel beta|stable, --quit-steam (agree to close Steam), and
// --runners DIR --bridge DIR --cache DIR to work on a scratch tree instead of
// notproton's. With --runners, Steam is not in the way: it never uses that tree.
// Exits 0 on success, 1 otherwise.

import Foundation

enum HeadlessEngine {
    static let flag = "--engine"

    private final class ExitCode: @unchecked Sendable {
        var value: Int32 = 1
    }

    static func runIfRequested(arguments: [String] = CommandLine.arguments) {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return }
        let command = arguments[index + 1]
        func option(_ name: String) -> String? {
            arguments.firstIndex(of: name).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        }
        let channel = option("--channel").flatMap(EngineChannel.init) ?? EngineChannel.preferred
        let mayQuitSteam = arguments.contains("--quit-steam")

        var updater = EngineUpdater()
        if let runners = option("--runners") {
            let root = URL(filePath: runners)
            updater.runners = root
            updater.steamIsRunning = { false }
            updater.gameIsRunning = { Shell.processIsRunning(commandLineContaining: root.path(percentEncoded: false)) }
            // A scratch tree never touches the real bridge unless told to.
            updater.bridge = root.deletingLastPathComponent().appending(path: "bridge")
            updater.bridges = root.deletingLastPathComponent().appending(path: "bridges")
        }
        if let bridge = option("--bridge") { updater.bridge = URL(filePath: bridge) }
        if let cache = option("--cache") { updater.cache = URL(filePath: cache) }
        let configured = updater

        let code = ExitCode()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                code.value = try await run(command, channel: channel, mayQuitSteam: mayQuitSteam, updater: configured)
            } catch {
                print("engine: failed: \(error.localizedDescription)")
            }
            done.signal()
        }
        done.wait()
        AppLog.flush()
        exit(code.value)
    }

    private static func run(
        _ command: String, channel: EngineChannel, mayQuitSteam: Bool, updater: EngineUpdater
    ) async throws -> Int32 {
        let report: @Sendable (EngineUpdatePhase) -> Void = { print("engine: \($0.label)") }
        switch command {
        case "check":
            print("engine: \(try await updater.check(channel: channel).summary)")
            print("engine: rollback target \(updater.rollbackTarget ?? "none")")
            return 0
        case "install", "reinstall":
            let check = try await updater.check(channel: channel)
            print("engine: \(check.summary)")
            let release: EngineRelease
            switch check {
            case .available(let offered):
                release = offered
            case .upToDate(let offered, true) where command == "reinstall":
                release = offered
            case .upToDate:
                print("engine: nothing to install")
                return command == "install" ? 0 : 1
            default:
                return 1
            }
            let started = Date()
            let outcome = try await updater.install(release, mayQuitSteam: mayQuitSteam, report: report)
            print("engine: installed \(outcome.version)\(outcome.reinstalled ? " (reinstall)" : "") "
                + "previous=\(outcome.previous ?? "none") stoppedSteam=\(outcome.stoppedSteam) "
                + "in \(Int(Date().timeIntervalSince(started))) s")
            print("engine: smoke test: \(outcome.smoke)")
            return 0
        case "rollback":
            let outcome = try updater.rollback(mayQuitSteam: mayQuitSteam, report: report)
            print("engine: rolled back from \(outcome.from) to \(outcome.to), stoppedSteam=\(outcome.stoppedSteam)")
            return 0
        default:
            print("engine: unknown command \(command); use check, install, reinstall or rollback")
            return 1
        }
    }
}
