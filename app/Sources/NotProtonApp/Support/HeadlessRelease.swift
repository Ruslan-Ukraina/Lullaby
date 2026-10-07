// `NotProtonApp --release <command>`: the Phase 5 buttons without the window.
//
//   --release check             new signature databases, the Steam gate, the bridge offer
//   --release gate              the Steam gate only
//   --release bridge-install    install the bridge revision on offer
//   --release bridge-rollback   switch back to the previous bridge
// Options for a scratch tree, never the real one:
//   --support DIR      a notproton folder: runners/, bridge/, bridges/, manifests/,
//                      signatures/macos.arm64/, steam-update-gate
//   --steam DIR        stands for ~/Library/Application Support/Steam: steam.cfg and
//                      Steam.AppBundle/…/package (with Steam's manifests, if any)
//   --feed URL --key BASE64   a test feed and its key; only with --support
// Exits 0 on success, 1 otherwise.

import Foundation

enum HeadlessRelease {
    static let flag = "--release"

    private final class ExitCode: @unchecked Sendable {
        var value: Int32 = 1
    }

    struct Setup: Sendable {
        var bridge = BridgeUpdater()
        var signatures = SignatureUpdater()
        var gate = SteamUpdateGate()
    }

    static func runIfRequested(arguments: [String] = CommandLine.arguments) {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return }
        let command = arguments[index + 1]
        func option(_ name: String) -> String? {
            arguments.firstIndex(of: name).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        }
        var setup = Setup()
        if let dir = option("--support") {
            let support = URL(filePath: dir)
            setup.bridge.store = BridgeStore(
                store: support.appending(path: "bridges"), live: support.appending(path: "bridge"),
                downloads: support.appending(path: "cache/bridge"))
            setup.bridge.runners = support.appending(path: "runners")
            setup.bridge.manifests = support.appending(path: "manifests")
            setup.bridge.gameIsRunning = { Shell.processIsRunning(commandLineContaining: support.path(percentEncoded: false)) }
            setup.signatures.signatures = support.appending(path: "signatures/macos.arm64")
            setup.signatures.manifests = support.appending(path: "manifests")
            setup.gate.file = support.appending(path: "steam-update-gate")
            setup.gate.signatures = setup.signatures.signatures
            if let feed = option("--feed"), let key = option("--key") {
                let configured = ReleaseFeed.setup(url: feed, key: key)
                setup.bridge.feed = configured
                setup.signatures.feed = configured
            }
        } else if option("--feed") != nil || option("--key") != nil {
            print("release: --feed and --key need --support (a scratch tree)")
            exit(1)
        }
        if let dir = option("--steam") {
            let steam = URL(filePath: dir)
            setup.gate.blockPaths = [
                steam.appending(path: "steam.cfg"),
                steam.appending(path: "Steam.AppBundle/Steam/Contents/MacOS/steam.cfg"),
            ]
            setup.gate.package = steam.appending(path: "Steam.AppBundle/Steam/Contents/MacOS/package")
        }
        let signatures = setup.signatures
        setup.gate.support = { signatures.support() }
        let configured = setup

        let code = ExitCode()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                code.value = try await run(command, configured)
            } catch {
                print("release: failed: \(error.localizedDescription)")
            }
            done.signal()
        }
        done.wait()
        AppLog.flush()
        exit(code.value)
    }

    private static func run(_ command: String, _ setup: Setup) async throws -> Int32 {
        switch command {
        case "check":
            let outcome = try await setup.signatures.update()
            print("release: signatures installed \(outcome.installed.isEmpty ? "none" : outcome.installed.joined(separator: " ")); "
                + "supported builds \(outcome.supportedBuilds.map(String.init).joined(separator: " "))")
            let decision = await setup.gate.evaluate()
            print("release: gate \(decision.state.summary), block=\(decision.block)")
            print("release: bridge \(try await setup.bridge.check().summary)")
            print("release: bridge rollback target \(setup.bridge.rollbackTarget?.id ?? "none")")
            return 0
        case "gate":
            let decision = await setup.gate.evaluate()
            print("release: gate mode \(setup.gate.mode.rawValue), \(decision.state.summary), block=\(decision.block)")
            return 0
        case "bridge-install":
            let check = try await setup.bridge.check()
            print("release: bridge \(check.summary)")
            guard case .available(let release, _) = check else { return 1 }
            let outcome = try await setup.bridge.install(release) { print("release: \($0.label)") }
            print("release: bridge now \(outcome.id), previous \(outcome.previous ?? "none")")
            return 0
        case "bridge-rollback":
            let outcome = try setup.bridge.rollback()
            print("release: bridge back on \(outcome.id), from \(outcome.previous ?? "none")")
            return 0
        default:
            print("release: unknown command \(command); use check, gate, bridge-install or bridge-rollback")
            return 1
        }
    }
}
