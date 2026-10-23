// Keeps the Steam client off builds Lullaby has no signatures for (Phase 5,
// DECISIONS P5-4). The lever is Valve's own: BootStrapperInhibitUpdateOnLaunch in
// steam.cfg (UpdateBlock), which the bootstrapper reads when Steam starts.
//
// Automatic mode holds the block by default and lifts it only while Valve offers a
// build that signatures-manifest.json lists and whose database is on disk. Steam
// then updates on its next start, and lullaby.dylib, once the client is up,
// writes the block back (steam/hook/feats/updategate.c), so the build after that waits
// again even when Lullaby.app is not open. Manual mode ("Block Steam client
// updates") holds the block whatever Valve offers.
//
// lullaby/steam-update-gate holds the mode, one word. Without it, a block that
// is already in steam.cfg counts as the person's own (manual), as before Phase 5.

import Foundation

enum SteamBuild {
    static let manifestHost = "https://client-update.akamai.steamstatic.com/"

    /// The client Steam installed: the version in the newest steam_client*_osx.manifest.
    static func installed(package: URL = SupportPaths.Steam.package) -> UInt64? {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: package.path(percentEncoded: false))) ?? []
        let newest = names
            .filter { $0.hasPrefix("steam_client") && $0.hasSuffix("_osx.manifest") }
            .compactMap { name -> (date: Date, build: UInt64)? in
                let url = package.appending(path: name)
                guard let text = try? String(contentsOf: url, encoding: .utf8), let build = version(in: text) else {
                    return nil
                }
                let date = (try? fm.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.modificationDate] as? Date
                return (date ?? .distantPast, build)
            }
            .max { ($0.date, $0.build) < ($1.date, $1.build) }
        return newest?.build
    }

    /// The client beta Steam follows (package/beta), or nil for the public client.
    static func beta(package: URL = SupportPaths.Steam.package) -> String? {
        guard let text = try? String(contentsOf: package.appending(path: "beta"), encoding: .utf8) else { return nil }
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.wholeMatch(of: /[A-Za-z0-9_-]{1,64}/) != nil ? name : nil
    }

    static func manifestURL(beta: String?) -> URL {
        URL(string: manifestHost + "steam_client\(beta.map { "_\($0)" } ?? "")_osx")!
    }

    /// The first `"version" "N"` of a Valve package manifest (VDF).
    static func version(in text: String) -> UInt64? {
        guard let match = text.firstMatch(of: /"version"\s+"([0-9]{1,20})"/) else { return nil }
        return UInt64(match.1)
    }

    /// What Valve offers this Mac now.
    static func offered(beta: String?, transport: any EngineTransport) async throws -> UInt64 {
        let url = manifestURL(beta: beta)
        let data = try await transport.fetch(url, limit: 1 << 20)
        guard let build = version(in: String(decoding: data, as: UTF8.self)) else {
            throw TransportFailure(detail: "\(url.lastPathComponent) names no version.")
        }
        return build
    }
}

enum SteamGateMode: String, Sendable {
    case auto
    case manual
}

enum SteamGateState: Sendable, Equatable {
    case manual(installed: UInt64?)
    /// Valve offers what is installed.
    case current(build: UInt64, supported: Bool)
    /// Valve offers a build with signatures: the block is lifted for it.
    case updateAllowed(from: UInt64?, to: UInt64)
    /// Valve offers a build without signatures: the block holds.
    case waiting(offered: UInt64, installed: UInt64?)
    /// Valve's version could not be read: the block holds.
    case unknown(installed: UInt64?, reason: String)

    var summary: String {
        switch self {
        case .manual(let installed): "manual block, installed \(installed.map(String.init) ?? "unknown")"
        case .current(let build, let supported): "current \(build), supported=\(supported)"
        case .updateAllowed(let from, let to): "update allowed \(from.map(String.init) ?? "unknown") → \(to)"
        case .waiting(let offered, let installed):
            "waiting: Valve offers \(offered), installed \(installed.map(String.init) ?? "unknown")"
        case .unknown(let installed, let reason): "unknown (\(reason)), installed \(installed.map(String.init) ?? "unknown")"
        }
    }
}

struct SteamGateDecision: Sendable, Equatable {
    let block: Bool
    let state: SteamGateState
}

struct SteamUpdateGate: Sendable {
    static let step = "Steam updates"

    var file: URL = SupportPaths.steamUpdateGate
    var blockPaths: [URL] = UpdateBlock.paths
    var package: URL = SupportPaths.Steam.package
    var signatures: URL = SupportPaths.signatures
    var transport: any EngineTransport = URLSessionEngineTransport()
    var support: @Sendable () -> SignatureSupport = { SignatureUpdater().support() }

    var mode: SteamGateMode {
        if let text = try? String(contentsOf: file, encoding: .utf8),
           let mode = SteamGateMode(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            return mode
        }
        return UpdateBlock.isPresent(at: blockPaths) ? .manual : .auto
    }

    func setMode(_ mode: SteamGateMode) throws {
        try atomicReplace(file, with: Data("\(mode.rawValue)\n".utf8), step: Self.step)
        AppLog.note("steam gate: mode \(mode.rawValue)")
    }

    /// The rule, apart from any file or network.
    static func decide(
        mode: SteamGateMode, installed: UInt64?, offered: UInt64?, offeredError: String? = nil,
        supported: (UInt64) -> Bool
    ) -> SteamGateDecision {
        if mode == .manual { return SteamGateDecision(block: true, state: .manual(installed: installed)) }
        guard let offered else {
            return SteamGateDecision(
                block: true, state: .unknown(installed: installed, reason: offeredError ?? "no answer from Valve"))
        }
        if offered == installed {
            return SteamGateDecision(block: true, state: .current(build: offered, supported: supported(offered)))
        }
        if supported(offered) {
            return SteamGateDecision(block: false, state: .updateAllowed(from: installed, to: offered))
        }
        return SteamGateDecision(block: true, state: .waiting(offered: offered, installed: installed))
    }

    /// Reads both builds, decides, and writes steam.cfg when it has to change.
    func evaluate() async -> SteamGateDecision {
        let mode = mode
        let installed = SteamBuild.installed(package: package)
        var offered: UInt64?
        var problem: String?
        if mode == .auto {
            do {
                offered = try await SteamBuild.offered(beta: SteamBuild.beta(package: package), transport: transport)
            } catch {
                problem = "Valve's Steam version could not be read: \(error.localizedDescription)"
            }
        }
        let support = support()
        let signatures = signatures
        let decision = Self.decide(
            mode: mode, installed: installed, offered: offered, offeredError: problem,
            supported: { support.supports($0, installedIn: signatures) })
        apply(decision, mode: mode)
        return decision
    }

    func apply(_ decision: SteamGateDecision, mode: SteamGateMode) {
        if (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
            != mode.rawValue
        {
            try? setMode(mode)
        }
        let present = UpdateBlock.isPresent(at: blockPaths)
        do {
            if decision.block, !present {
                try UpdateBlock.write(to: blockPaths)
                AppLog.note("steam gate: block written (\(decision.state.summary))")
            } else if !decision.block, present {
                try UpdateBlock.remove(from: blockPaths)
                AppLog.note("steam gate: block lifted (\(decision.state.summary))")
            } else {
                AppLog.note("steam gate: \(decision.state.summary), block \(present ? "kept" : "stays off")")
            }
        } catch {
            AppLog.note("steam gate: steam.cfg could not be changed: \(error.localizedDescription)")
        }
    }
}
