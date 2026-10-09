// Steam app bundle patching component

import AppKit
import Foundation

enum SteamDeployment: Sendable, Equatable {
    case steamMissing
    case notInstalled
    case installed(version: String?)
    /// A different version, or the same version with parts whose content differs.
    case outdated(deployed: String?, bundled: String, stale: [PatchPart])
    // If the user has something else installed, maybe let's not deploy?
    case foreign(insert: String)
}

// Reading and writing the injection
enum SteamBundle {

    static let insertKey = "DYLD_INSERT_LIBRARIES"
    /// Keeps Steam from seeing a second, generic copy of the Steam Controller, which doubled
    /// its input (upstream NotProton 1.1.x, "Fixes Steam Input issues"). Steam's children
    /// lose it with the insert (hook_spawn.c).
    static let controllerBlockKey = "SDL_JOYSTICK_BLACKLIST_DEVICES"
    static let controllerBlockValue = "0x05ac/0x0004"

    static let plistBackupName = "Info.plist.before-notproton"
    static let environmentKey = "LSEnvironment"

    static var isPresent: Bool {
        FileManager.default.fileExists(atPath: SupportPaths.Steam.app.path(percentEncoded: false))
    }

    static var isRunning: Bool {

        Shell.processIsRunning(named: "steam_osx")
    }

    /// Wine of ours: an engine from notproton/runners or a game bundle from
    /// notproton/launchers. Other Wine on the Mac (Sevoflurane bottles) does not count.
    static var gameIsRunning: Bool {
        [SupportPaths.runners, SupportPaths.launchers].contains {
            Shell.processIsRunning(commandLineContaining: $0.path(percentEncoded: false))
        }
    }

    static func deployment(
        bundledVersion: String,
        stale: [PatchPart] = [],
        app: URL = SupportPaths.Steam.app,
        versionFile: URL = SupportPaths.deployedVersion
    ) -> SteamDeployment {
        let files = FileManager.default
        guard files.fileExists(atPath: app.path(percentEncoded: false)) else { return .steamMissing }

        let plist = SupportPaths.Steam.infoPlist(inBundle: app)
        guard let insert = currentInsert(at: plist), !insert.isEmpty else { return .notInstalled }

        let deployedDylib = SupportPaths.Steam.deployedDylib(inBundle: app)
            .path(percentEncoded: false)
        let components = insert.split(separator: ":").map(String.init)
        guard components.contains(deployedDylib) else { return .foreign(insert: insert) }

        guard files.fileExists(atPath: deployedDylib) else { return .notInstalled }

        let deployed = deployedVersion(at: versionFile)
        if !stale.isEmpty { return .outdated(deployed: deployed, bundled: bundledVersion, stale: stale) }
        guard let deployed else { return .installed(version: nil) }
        if deployed == bundledVersion { return .installed(version: deployed) }
        return .outdated(deployed: deployed, bundled: bundledVersion, stale: [])
    }

    static func currentInsert(at url: URL = SupportPaths.Steam.infoPlist) -> String? {
        guard let dict = readInfoPlist(at: url),
              let environment = dict[environmentKey] as? [String: Any]
        else { return nil }
        return environment[insertKey] as? String
    }

    static func currentControllerBlock(at url: URL = SupportPaths.Steam.infoPlist) -> String? {
        guard let dict = readInfoPlist(at: url),
              let environment = dict[environmentKey] as? [String: Any]
        else { return nil }
        return environment[controllerBlockKey] as? String
    }

    static func deployedVersion(at url: URL = SupportPaths.deployedVersion) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func stopClient(
        app: URL = SupportPaths.Steam.app,
        helpers: [URL] = [SupportPaths.Steam.innerApp],
        step: String,
        onStopping: () -> Void = {}
    ) throws -> Bool {
        guard isRunning else { return false }
        onStopping()

        _ = try? Shell.run("/usr/bin/pkill", ["-x", "steam_osx"])
        for _ in 0..<60 where isRunning {
            Thread.sleep(forTimeInterval: 0.5)
        }

        if isRunning {
            _ = try? Shell.run("/usr/bin/pkill", ["-9", "-x", "steam_osx"])
            Thread.sleep(forTimeInterval: 1)
        }

        guard !isRunning else {
            throw StepFailure(
                step: step,
                detail: "Steam is running, please close Steam."
            )
        }

        for pattern in sweepPatterns(app: app, helpers: helpers) {
            _ = try? Shell.run("/usr/bin/pkill", ["-f", pattern])
        }
        return true
    }

    static let bundleIdentifier = "com.valvesoftware.steam"

    /// How long Install, Update and Reinstall wait for Steam to quit on its own.
    static let quitTimeout: TimeInterval = 45

    /// Steam left running after the soft quit. The person closes it and presses Retry.
    struct StillRunning: LocalizedError, Equatable {
        let seconds: Int
        var errorDescription: String? {
            "Steam did not quit within \(seconds) seconds. Quit Steam yourself "
                + "(Steam → Quit Steam, or ⌘Q), then press Retry."
        }
    }

    /// Asks Steam to quit the way a person would, so it saves its state: steam://exit first
    /// (Steam's own exit command), then the Quit Apple event if it is still up halfway. No
    /// signals: SIGTERM is ignored by steam_osx, and SIGKILL loses Steam's unsaved state.
    /// Returns false when Steam was not running. Used by Install, Update and Reinstall;
    /// Repair and Remove keep stopClient.
    static func quitClient(
        app: URL = SupportPaths.Steam.app,
        helpers: [URL] = [SupportPaths.Steam.innerApp],
        timeout: TimeInterval = quitTimeout,
        poll: TimeInterval = 0.5,
        isRunning running: () -> Bool = { isRunning },
        openExitURL: () -> Void = requestExitURL,
        sendQuitEvent: () -> Void = requestQuitEvent,
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        sweep: ([String]) -> Void = sweepHelpers,
        onStopping: () -> Void = {}
    ) throws -> Bool {
        guard running() else { return false }
        onStopping()

        AppLog.note("steam quit: steam://exit")
        openExitURL()
        var waited: TimeInterval = 0
        var sentEvent = false
        while running() {
            guard waited < timeout else {
                AppLog.note("steam quit: still running after \(Int(timeout)) s")
                throw StillRunning(seconds: Int(timeout))
            }
            if !sentEvent, waited >= timeout / 2 {
                AppLog.note("steam quit: Quit Apple event")
                sendQuitEvent()
                sentEvent = true
            }
            sleep(poll)
            waited += poll
        }
        AppLog.note("steam quit: closed after \(Int(waited)) s")

        sweep(sweepPatterns(app: app, helpers: helpers))
        return true
    }

    static func requestExitURL() {
        _ = try? Shell.run("/usr/bin/open", ["-g", "steam://exit"])
    }

    static func requestQuitEvent() {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
            app.terminate()
        }
    }

    /// Helpers (ipcserver, Steam Helper) can outlive steam_osx for a moment; Steam is gone,
    /// so ending them loses nothing.
    static func sweepHelpers(_ patterns: [String]) {
        for pattern in patterns {
            _ = try? Shell.run("/usr/bin/pkill", ["-f", pattern])
        }
    }

    static func sweepPatterns(app: URL, helpers: [URL]) -> [String] {
        ([app] + helpers).map { $0.path(percentEncoded: false) + "/" }
    }

    static func register(_ app: URL = SupportPaths.Steam.app) {
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks"
            + "/LaunchServices.framework/Support/lsregister"
        _ = try? Shell.run(lsregister, ["-f", app.path(percentEncoded: false)])
    }

    static func readInfoPlist(at url: URL = SupportPaths.Steam.infoPlist) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return nil }
        return object as? [String: Any]
    }

    static func writeInfoPlist(_ dict: [String: Any], at url: URL = SupportPaths.Steam.infoPlist) throws {
        var format = PropertyListSerialization.PropertyListFormat.xml
        if let data = try? Data(contentsOf: url) {
            _ = try? PropertyListSerialization.propertyList(from: data, format: &format)
        }

        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: format, options: 0)
        try WriteRefused.catching(url) { try data.write(to: url, options: .atomic) }
    }
}
