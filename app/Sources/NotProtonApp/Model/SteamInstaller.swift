// 'Install' logic for the Steam patch componen

import Foundation

enum InstallPhase: Sendable {
    case checkingPayload
    case stagingBridge
    case preflight
    case stoppingClient
    case copyingDylib
    case installingSignatures
    case installingOverlayShim
    case settingInsert
    case signing
    case registering
    case finished

    var label: String {
        switch self {
        case .checkingPayload: "Preparing"
        case .stagingBridge: "Staging components"
        case .preflight: "Checking Steam"
        case .stoppingClient: "Stopping Steam"
        case .copyingDylib: "Installing"
        case .installingSignatures: "Installing signatures"
        case .installingOverlayShim: "Installing components"
        case .settingInsert: "Configuring Steam"
        case .signing: "Signing"
        case .registering: "Finishing up"
        case .finished: "Done"
        }
    }
}

struct InstallOutcome: Sendable {
    let stoppedClient: Bool
    let version: String
    let signatureDatabases: Int
    let backedUpPlist: Bool
    let bridgeStaged: Int
    let build: String?
}

enum SteamInstaller {
    static let step = "Install NotProton"

    typealias ClientStopper = @Sendable (URL, () -> Void) throws -> Bool
    typealias BundleRegistrar = @Sendable (URL) -> Void

    static let stopTheClient: ClientStopper = { app, onStopping in
        try SteamBundle.quitClient(app: app, onStopping: onStopping)
    }

    static func run(
        payload suppliedPayload: InstallPayload.Located? = nil,
        bridgePayload suppliedBridge: BridgePayload.Located? = nil,
        version: String = AppVersion.bundled,
        force: Bool = false,
        app: URL = SupportPaths.Steam.app,
        bridge: URL = SupportPaths.bridge,
        signatures: URL = SupportPaths.signatures,
        overlayShim: URL = SupportPaths.overlayShim,
        iconmaker: URL = SupportPaths.iconmaker,
        appinfo: URL = SupportPaths.appinfo,
        deployedVersion: URL = SupportPaths.deployedVersion,
        backups: URL = SupportPaths.backups,
        runScript: URL = SupportPaths.Steam.compatTool.appending(path: "run"),
        gameIsRunning: @Sendable () -> Bool = { SteamBundle.gameIsRunning },
        stopClient: ClientStopper = stopTheClient,
        register: BundleRegistrar = { SteamBundle.register($0) },
        report: @escaping @Sendable (InstallPhase) -> Void = { _ in }
    ) throws -> InstallOutcome {
        AppLog.note("install: begin\(force ? " (reinstall)" : "") version=\(version)")
        report(.checkingPayload)
        let payload = try suppliedPayload ?? InstallPayload.locate()
        let bridgeLocated = try suppliedBridge ?? BridgePayload.active()

        report(.stagingBridge)
        let bridgeResult = try BridgePayload.stage(located: bridgeLocated, bridge: bridge)

        report(.preflight)
        let plist = app.appending(path: "Contents/Info.plist")
        let dylib = app.appending(path: "Contents/MacOS/\(SupportPaths.dylibName)")
        try assertBundleIsPresent(app)
        try assertInsertIsDeployedOrAbsent(at: plist, dylib: dylib)
        let patching = try needsPatching(
            plist: plist, dylib: dylib, shipping: payload.dylib, app: app, force: force
        )

        var stopped = false
        if patching {
            // Stopping Steam under a running game ends it without saving.
            guard !gameIsRunning() else {
                AppLog.note("install: refused, a game is running")
                throw StepFailure(step: step, detail: Self.gameRunning)
            }
            stopped = try stopClient(app) { report(.stoppingClient) }

            report(.copyingDylib)
            try install(payload.dylib, at: dylib)
        }
        try write(version, to: deployedVersion)

        report(.installingSignatures)
        try FileManager.default.createDirectory(at: signatures, withIntermediateDirectories: true)
        let known = SignatureUpdater(signatures: signatures).support()
        for database in payload.signatures {
            let target = signatures.appending(path: database.lastPathComponent)
            // A revision of the same database from NotProton's signed releases stays.
            if let have = Digest.sha256IfPresent(target), have != Digest.sha256IfPresent(database),
               known.accepted(database.lastPathComponent).contains(have)
            {
                continue
            }
            try install(database, at: target)
        }

        report(.installingOverlayShim)
        try install(payload.overlayShim, at: overlayShim)
        try install(payload.iconmaker, at: iconmaker)
        try install(payload.appinfo, at: appinfo)
        try installRunScript(payload.runScript, at: runScript)

        var backedUp = false
        if patching {
            report(.settingInsert)
            backedUp = try backUpPlist(plist, into: backups)

            let priorPlist = try? Data(contentsOf: plist)
            do {
                try setInsert(at: plist, to: dylib)

                report(.signing)
                try adHocSign(dylib)
                try adHocSign(app.appending(path: "Contents/MacOS/steam_osx"))
                try adHocSign(app)
            } catch {
                revertPlist(priorPlist, at: plist, app: app)
                throw error
            }
        }

        report(.registering)
        register(app)

        let landed = SteamBundle.currentInsert(at: plist)
        guard landed == dylib.path(percentEncoded: false) else {
            AppLog.note("install: bundle declares \(landed ?? "no insert")")
            throw StepFailure(
                step: step,
                detail: "Steam is set up to inject a different dylib. Please repair Steam "
                    + "before installing NotProton."
            )
        }

        let build = MachOBuild.shortBuild(of: dylib)
        AppLog.note(
            "install: done version=\(version) build=\(build ?? "unknown") "
                + "patched=\(patching) stoppedSteam=\(stopped) "
                + "bridgeStaged=\(bridgeResult.staged.count) signatures=\(payload.signatures.count)"
        )
        report(.finished)
        return InstallOutcome(
            stoppedClient: stopped,
            version: version,
            signatureDatabases: payload.signatures.count,
            backedUpPlist: backedUp,
            bridgeStaged: bridgeResult.staged.count,
            build: build
        )
    }


    static func assertBundleIsPresent(_ app: URL) throws {
        guard FileManager.default.fileExists(atPath: app.path(percentEncoded: false)) else {
            throw StepFailure(
                step: step,
                detail: "\(app.path(percentEncoded: false)) is not there, so there is nothing to install into."
            )
        }
    }

    static func assertInsertIsDeployedOrAbsent(at plist: URL, dylib: URL) throws {
        guard let insert = SteamBundle.currentInsert(at: plist), !insert.isEmpty else { return }

        let deployed = dylib.path(percentEncoded: false)
        let foreign = insert.split(separator: ":").map(String.init).filter { $0 != deployed }
        guard foreign.isEmpty else {
            throw StepFailure(
                step: step,
                detail: "Another dylib is present. Repair your Steam install before "
                    + "installing NotProton."
            )
        }
    }

    static func needsPatching(
        plist: URL, dylib: URL, shipping: URL, app: URL, force: Bool = false
    ) throws -> Bool {
        let deployed = SteamBundle.currentInsert(at: plist) == dylib.path(percentEncoded: false)
        if !force, deployed, let installed = MachOBuild.identity(of: dylib),
            let current = MachOBuild.identity(of: shipping), installed == current
        {
            AppLog.note("install: Steam already carries this dylib, installing for this account only")
            return false
        }

        do {
            try assertBundleIsWritable(app)
        } catch let refusal as WriteRefused where refusal.remedy == .otherAccount {
            throw StepFailure(
                step: step,
                detail: deployed ? Self.mismatchAcrossAccounts : Self.unpatchedAcrossAccounts
            )
        }
        return true
    }

    static let gameRunning =
        "A game is running under NotProton. Quit the game, then try again."

    private static let mismatchAcrossAccounts =
        "Steam has a different copy of NotProton, installed by another account on this Mac. "
        + "Update NotProton from that account, then try again."

    private static let unpatchedAcrossAccounts =
        "Steam has not been set up for NotProton, and this account cannot change it. "
        + "Install from the account that owns Steam."

    static func assertBundleIsWritable(_ app: URL) throws {
        let directory = app.appending(path: "Contents/MacOS")
        let probe = directory.appending(path: ".notproton-write-probe")
        do {
            try Data("probe".utf8).write(to: probe)
            try FileManager.default.removeItem(at: probe)
        } catch let error as NSError where error.code == NSFileWriteNoPermissionError {
            throw WriteRefused(path: directory.path(percentEncoded: false))
        } catch {
            throw StepFailure(
                step: step,
                detail: "\(directory.path(percentEncoded: false)) could not be written. "
                    + error.localizedDescription
            )
        }
    }

    static func install(_ source: URL, at destination: URL) throws {
        let files = FileManager.default
        try WriteRefused.catching(destination) {
            try files.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? files.removeItem(at: destination)
            try files.copyItem(at: source, to: destination)
        }
    }

    /// The dylib writes the run script into Steam's compatibility tool folder at every game
    /// launch. Writing it here too means Steam has the new one before the next launch. The
    /// folder belongs to the dylib (it writes the .vdf files next to it), so a folder that is
    /// not there yet is left for the dylib to create.
    static func installRunScript(_ source: URL, at destination: URL) throws {
        let folder = destination.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
        try install(source, at: destination)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: destination.path(percentEncoded: false)
        )
    }

    static func write(_ version: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("\(version)\n".utf8).write(to: url)
    }

    static func backUpPlist(_ plist: URL, into backups: URL) throws -> Bool {
        let destination = backups.appending(path: SteamBundle.plistBackupName)
        let files = FileManager.default
        guard !files.fileExists(atPath: destination.path(percentEncoded: false)) else { return false }
        guard files.fileExists(atPath: plist.path(percentEncoded: false)) else { return false }

        try files.createDirectory(at: backups, withIntermediateDirectories: true)
        try files.copyItem(at: plist, to: destination)
        return true
    }

    static func revertPlist(_ bytes: Data?, at plist: URL, app: URL) {
        guard let bytes else { return }
        try? bytes.write(to: plist)
        try? adHocSign(app)
    }

    static func setInsert(at plist: URL, to dylib: URL) throws {
        guard var dict = SteamBundle.readInfoPlist(at: plist) else {
            throw StepFailure(
                step: step,
                detail: "\(plist.path(percentEncoded: false)) could not be read as a property list."
            )
        }

        var environment = dict[SteamBundle.environmentKey] as? [String: Any] ?? [:]
        environment[SteamBundle.insertKey] = dylib.path(percentEncoded: false)
        dict[SteamBundle.environmentKey] = environment
        try SteamBundle.writeInfoPlist(dict, at: plist)
    }

    static func adHocSign(_ url: URL, step: String = step) throws {
        let path = url.path(percentEncoded: false)
        let result = try Shell.run("/usr/bin/codesign", ["-f", "-s", "-", path])
        guard result.succeeded else {
            throw StepFailure(
                step: step,
                detail: "\(path) could not be signed. "
                    + result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

}
