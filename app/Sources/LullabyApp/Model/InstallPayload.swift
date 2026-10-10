// Deploys Lullaby's components into Steam and lullaby/ (the engine itself is Dormison, set up by EngineUpdater)

import Foundation

enum InstallPayload {
    static let step = "Find Lullaby's components"

    struct Located: Sendable {
        let dylib: URL
        let overlayShim: URL
        let iconmaker: URL
        let appinfo: URL
        /// lullaby-settings: the settings CLI the Steam panel and Dormison's View menu call.
        let settingsCLI: URL
        /// compat_run.sh as the dylib embeds it, to compare with Steam's copy and to write it.
        let runScript: URL

        let signatures: [URL]
    }

    static let runScriptName = "compat_run.sh"

    static func root(in bundle: Bundle = .module) throws -> URL {
        guard let url = bundle.url(forResource: "payload", withExtension: nil) else {
            throw StepFailure(
                step: step,
                detail: "This build of Lullaby carries no components at all."
            )
        }
        return url
    }

    static func locate(in bundle: Bundle = .module) throws -> Located {
        try locate(root: try root(in: bundle))
    }

    static func locate(root: URL) throws -> Located {
        let files = FileManager.default

        let dylib = root.appending(path: SupportPaths.dylibName)
        let shim = root.appending(path: "overlay-shim.dylib")
        let iconmaker = root.appending(path: "iconmaker")
        let appinfo = root.appending(path: "appinfo")
        let settingsCLI = root.appending(path: SupportPaths.settingsCLIName)
        let runScript = root.appending(path: runScriptName)

        var missing: [String] = []
        if !files.fileExists(atPath: dylib.path(percentEncoded: false)) {
            missing.append(SupportPaths.dylibName)
        }
        if !files.fileExists(atPath: shim.path(percentEncoded: false)) {
            missing.append("overlay-shim.dylib")
        }
        if !files.fileExists(atPath: iconmaker.path(percentEncoded: false)) {
            missing.append("iconmaker")
        }
        if !files.fileExists(atPath: appinfo.path(percentEncoded: false)) {
            missing.append("appinfo")
        }
        if !files.fileExists(atPath: settingsCLI.path(percentEncoded: false)) {
            missing.append(SupportPaths.settingsCLIName)
        }
        if !files.fileExists(atPath: runScript.path(percentEncoded: false)) {
            missing.append(runScriptName)
        }

        let signatureDir = root.appending(path: "signatures/macos.arm64")
        let signatures = ((try? files.contentsOfDirectory(
            at: signatureDir, includingPropertiesForKeys: nil
        )) ?? []).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        if signatures.isEmpty { missing.append("signatures/macos.arm64/*.json") }

        guard missing.isEmpty else {
            throw StepFailure(
                step: step,
                detail: "These components are missing: \(missing.joined(separator: ", ")). "
                    + "Run make app-payload and build the app again."
            )
        }

        return Located(
            dylib: dylib, overlayShim: shim, iconmaker: iconmaker,
            appinfo: appinfo, settingsCLI: settingsCLI, runScript: runScript, signatures: signatures
        )
    }
}
