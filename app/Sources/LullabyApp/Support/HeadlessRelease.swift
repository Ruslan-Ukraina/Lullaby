// `LullabyApp --release <command>`: the Phase 5 buttons without the window.
//
//   --release check             new signature databases, the Steam gate, the bridge offer
//   --release gate              the Steam gate only
//   --release bridge-install    install the bridge revision on offer
//   --release bridge-rollback   switch back to the previous bridge
//   --release plan              what the window's Update would install, and its status
//                               line in en, uk and ru (Phase 8); installs nothing
//   --release update            the window's Update: the plan, then its steps, in turn
//   --release onboarding        the window's Install without its Steam step: Rosetta,
//                               engine, bridge, signatures (Phase 8)
// (Install and Update run the same steps; update starts from the plan.)
// update and onboarding run only on a scratch tree (--support, and --steam for the gate).
// Options for a scratch tree, never the real one:
//   --support DIR      a lullaby folder: runners/, bridge/, bridges/, manifests/,
//                      signatures/macos.arm64/, steam-update-gate
//   --steam DIR        stands for ~/Library/Application Support/Steam: steam.cfg and
//                      Steam.AppBundle/…/package (with Steam's manifests, if any)
//   --feed URL --key BASE64   a test feed and its key; only with --support
//   --repository OWNER/NAME   with --feed: a private feed, read through GitHub's API
//                             with the token in NP_RELEASE_TOKEN (never an argument)
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
        /// Both --support and --steam given: nothing real is written.
        var scratch = false
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
                let repository = option("--repository")
                let configured = ReleaseFeed.setup(
                    url: feed, key: key, access: repository == nil ? "public" : "private",
                    repository: repository ?? "", token: ProcessInfo.processInfo.environment["NP_RELEASE_TOKEN"],
                    manifestTag: option("--manifest-tag"))
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
        setup.scratch = option("--support") != nil && option("--steam") != nil
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
        case "plan":
            var plan = UpdatePlan()
            let bridge = try await setup.bridge.check()
            print("release: bridge \(bridge.summary)")
            if case .available(let release, _) = bridge { plan.bridge = release }
            var engine = EngineUpdater()
            engine.runners = setup.bridge.runners
            engine.support = { [bridgeUpdater = setup.bridge] in bridgeUpdater.catalog() }
            engine.refreshBridges = {}
            do {
                let check = try await engine.check(channel: EngineChannel.preferred)
                print("release: engine \(check.summary)")
                if case .available(let release) = check { plan.engine = release }
            } catch {
                print("release: engine check failed: \(error.localizedDescription)")
            }
            print("release: update plan \(plan.isEmpty ? "nothing" : plan.parts.joined(separator: ", ")); "
                + "steps \(SetupSteps.setup(plan).map(\.id.rawValue).joined(separator: " ")); "
                + "closes Steam \(plan.closesSteam)")
            for language in ["en", "uk", "ru"] {
                print("release: status [\(language)] \(statusLine(plan, language: language))")
            }
            return 0
        case "update", "onboarding":
            guard setup.scratch else {
                print("release: \(command) runs only on a scratch tree (--support and --steam)")
                return 1
            }
            var env = SetupEnvironment(bridge: setup.bridge, signatures: setup.signatures, gate: setup.gate)
            env.engine = scratchEngine(setup)
            let steps: [FlowStep]
            if command == "update" {
                var plan = UpdatePlan()
                if case .available(let release, _) = try await setup.bridge.check() { plan.bridge = release }
                if case .available(let release)? = try? await env.engine.check(channel: EngineChannel.preferred) {
                    plan.engine = release
                }
                print("release: update plan \(plan.isEmpty ? "nothing" : plan.parts.joined(separator: ", "))")
                steps = SetupSteps.setup(plan, env)
            } else {
                steps = Array(SetupSteps.setup(nil, env).dropLast())
            }
            return await runSteps(steps)
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
            print("release: unknown command \(command); use check, plan, gate, bridge-install or bridge-rollback")
            return 1
        }
    }

    /// EngineUpdater on the scratch tree: never quits Steam, reads the scratch bridge list.
    private static func scratchEngine(_ setup: Setup) -> EngineUpdater {
        var engine = EngineUpdater()
        let bridge = setup.bridge
        engine.runners = bridge.runners
        engine.bridge = bridge.store.live
        engine.bridges = bridge.store.store
        engine.cache = bridge.runners.deletingLastPathComponent().appending(path: "cache/engine")
        engine.feed = bridge.feed
        engine.support = { bridge.catalog() }
        engine.refreshBridges = { try? await bridge.refreshManifest() }
        engine.steamIsRunning = { false }
        engine.quitSteam = { false }
        return engine
    }

    /// The steps one after another, as FlowRunner runs them in the window; a failure
    /// prints the window's sentence for it.
    private static func runSteps(_ steps: [FlowStep]) async -> Int32 {
        for (index, step) in steps.enumerated() {
            print("release: step \(index + 1)/\(steps.count) \(step.id.rawValue) — \(step.title)")
            do {
                try await step.run { detail in if !detail.isEmpty { print("release:   \(detail)") } }
            } catch {
                let problem = FlowProblem(error, step: step.id)
                print("release: failed at \(step.id.rawValue): \(problem.cause)")
                print("release: window says: \(problem.message)")
                print("release: log says: \(problem.detail)")
                return 1
            }
        }
        print("release: all \(steps.count) steps done")
        return 0
    }

    /// The window's status line for `plan`, read from the catalog of one language.
    private static func statusLine(_ plan: UpdatePlan, language: String) -> String {
        guard let path = Bundle.module.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return "(no \(language).lproj)" }
        func text(_ key: String) -> String { bundle.localizedString(forKey: key, value: key, table: "Localizable") }
        guard !plan.isEmpty else { return text("Installed") }
        var parts: [String] = []
        if let engine = plan.engine { parts.append(EngineStore.displayName(engine.version)) }
        if plan.bridge != nil { parts.append(text("Steam bridge")) }
        if plan.steamPatch { parts.append(text("Steam patch")) }
        if let app = plan.app { parts.append("NotProton \(app)") }
        let list = parts.formatted(.list(type: .and).locale(Locale(identifier: language)))
        return String(format: text("Update available: %@"), list)
    }
}
