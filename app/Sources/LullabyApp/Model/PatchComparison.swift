// What Steam and the support folder carry versus what this app ships, by content. The
// version number alone said "Installed (1.0.2)" over a dylib from an older build of 1.0.2.

import Foundation

enum PatchPart: String, Sendable, CaseIterable {
    case dylib
    case runScript
    case bridge
    case components

    var label: String {
        switch self {
        case .dylib: "Steam patch"
        case .runScript: "run script"
        case .bridge: "bridge"
        case .components: "support components"
        }
    }
}

struct InstalledPatch: Sendable, Equatable {
    /// The arm64 LC_UUID prefix of the dylib inside Steam.app.
    var build: String?
    /// The same for the dylib this app ships.
    var shippedBuild: String?
    /// When the dylib inside Steam.app was written.
    var installedAt: Date?
    /// Parts whose installed copy differs from the shipped one, in PatchPart order.
    var stale: [PatchPart]

    var isCurrent: Bool { stale.isEmpty }
}

enum PatchComparison {

    struct Installed: Sendable {
        var dylib: URL
        var runScript: URL
        var bridge: URL
        var overlayShim: URL
        var iconmaker: URL
        var appinfo: URL
        var nvapiShim: URL
        var windowState: URL
        var glFixes: URL
        var pacer: URL
        var settingsCLI: URL
        var signatures: URL

        static var live: Installed {
            Installed(
                dylib: SupportPaths.Steam.deployedDylib,
                runScript: SupportPaths.Steam.compatTool.appending(path: "run"),
                bridge: SupportPaths.bridge,
                overlayShim: SupportPaths.overlayShim,
                iconmaker: SupportPaths.iconmaker,
                appinfo: SupportPaths.appinfo,
                nvapiShim: SupportPaths.nvapiShim,
                windowState: SupportPaths.windowState,
                glFixes: SupportPaths.glFixes,
                pacer: SupportPaths.pacer,
                settingsCLI: SupportPaths.settingsCLI,
                signatures: SupportPaths.signatures
            )
        }
    }

    /// nil when the app carries no payload to compare with (a development build).
    static func inspect(installed: Installed = .live) -> InstalledPatch? {
        guard let payload = try? InstallPayload.locate(),
            let bridge = try? BridgePayload.active()
        else { return nil }
        return compare(payload: payload, bridgePayload: bridge, installed: installed)
    }

    static func compare(
        payload: InstallPayload.Located,
        bridgePayload: BridgePayload.Located,
        installed: Installed
    ) -> InstalledPatch {
        var stale: [PatchPart] = []

        if !sameBuild(installed.dylib, payload.dylib) { stale.append(.dylib) }

        // The dylib rewrites the run script on every game launch, so a missing one only means
        // no game has started yet. A different one means an older dylib wrote it.
        if let present = Digest.sha256IfPresent(installed.runScript),
            present != Digest.sha256IfPresent(payload.runScript)
        {
            stale.append(.runScript)
        }

        let bridgeDiffers = bridgePayload.sources.contains { entry in
            let shipped = Digest.sha256IfPresent(entry.source)
            return entry.bridgePaths.contains {
                Digest.sha256IfPresent(installed.bridge.appending(path: $0)) != shipped
            }
        }
        if bridgeDiffers { stale.append(.bridge) }

        var pairs: [(installed: URL, shipped: URL)] = [
            (installed.overlayShim, payload.overlayShim),
            (installed.iconmaker, payload.iconmaker),
            (installed.appinfo, payload.appinfo),
            (installed.nvapiShim, payload.nvapiShim),
            (installed.windowState, payload.windowState),
            (installed.glFixes, payload.glFixes),
            (installed.pacer, payload.pacer),
            (installed.settingsCLI, payload.settingsCLI),
        ]
        // A database the feed revised (signatures-manifest.json) is current, not stale.
        let known = SignatureUpdater(signatures: installed.signatures).support()
        pairs += payload.signatures.compactMap {
            let target = installed.signatures.appending(path: $0.lastPathComponent)
            if let have = Digest.sha256IfPresent(target), known.accepted($0.lastPathComponent).contains(have) {
                return nil
            }
            return (target, $0)
        }
        if pairs.contains(where: { Digest.sha256IfPresent($0.installed) != Digest.sha256IfPresent($0.shipped) }) {
            stale.append(.components)
        }

        let attributes = try? FileManager.default.attributesOfItem(
            atPath: installed.dylib.path(percentEncoded: false)
        )
        return InstalledPatch(
            build: MachOBuild.shortBuild(of: installed.dylib),
            shippedBuild: MachOBuild.shortBuild(of: payload.dylib),
            installedAt: attributes?[.modificationDate] as? Date,
            stale: stale
        )
    }

    /// Signing rewrites the dylib's bytes, so a Mach-O is compared by LC_UUID. Anything that
    /// has none (or is not there) falls back to its hash.
    static func sameBuild(_ installed: URL, _ shipped: URL) -> Bool {
        if let a = MachOBuild.identity(of: installed), let b = MachOBuild.identity(of: shipped) {
            return a == b
        }
        guard let a = Digest.sha256IfPresent(installed) else { return false }
        return a == Digest.sha256IfPresent(shipped)
    }
}
