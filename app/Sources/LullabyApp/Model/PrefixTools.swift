// Shortcuts to launch the Wine tools (winecfg/regedit/task manager) against
// a selected prefix, opens prefix directory in finder, etc.

import AppKit
import Foundation
import UniformTypeIdentifiers

enum WineTool: String, CaseIterable, Sendable {
    case winecfg
    case regedit
    case taskmgr

    var label: String {
        switch self {
        case .winecfg: "Wine Configuration"
        case .regedit: "Registry Editor"
        case .taskmgr: "Task Manager"
        }
    }
}

enum PrefixTools {

    /// compat_run.sh's rule: msync+ is on, and only a marker that a Dormison run
    /// wrote, which leaves a bottle.env in the prefix, can turn it off.
    static func syncBackend(prefix: WinePrefix) -> String {
        let marker = prefix.root.appending(path: "lullaby-msync")
        let recorded = (try? String(contentsOf: marker, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bottle = prefix.pfx.appending(path: ".sevo/bottle.env")
        let dormisonRun = FileManager.default.fileExists(atPath: bottle.path(percentEncoded: false))
        return dormisonRun && recorded == "0" ? "0" : "1"
    }

    /// What compat_run.sh sets for the engine, for a tool opened on a prefix.
    static func environment(
        prefix: WinePrefix, engine: any EngineProvider = DormisonEngine()
    ) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["WINELOADER"] = engine.wineloader.path(percentEncoded: false)
        environment["WINESERVER"] = engine.wineserver.path(percentEncoded: false)
        environment["WINEDLLPATH"] = SupportPaths.bridge.path(percentEncoded: false)
        environment["WINEPREFIX"] = prefix.pfx.path(percentEncoded: false)
        environment["WINEMSYNC"] = syncBackend(prefix: prefix)
        environment["SEVO_CLI"] = SupportPaths.sevoCLI.path(percentEncoded: false)
        environment["PATH"] = (engine.wineloader.path(percentEncoded: false) as NSString).deletingLastPathComponent
            + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        return environment
    }

    private static func readyLoader(step: String, prefix: WinePrefix, engine: any EngineProvider) throws -> URL {
        let loader = engine.wineloader
        guard FileManager.default.isExecutableFile(atPath: loader.path(percentEncoded: false)) else {
            throw StepFailure(
                step: step,
                detail: "No engine at \(loader.path(percentEncoded: false)). Install an engine first."
            )
        }
        guard FileManager.default.fileExists(atPath: prefix.pfx.path(percentEncoded: false)) else {
            throw StepFailure(
                step: step,
                detail: "\(prefix.title) has no prefix at \(prefix.pfx.path(percentEncoded: false))."
            )
        }
        return loader
    }

    static func launch(_ tool: WineTool, in prefix: WinePrefix, engine: any EngineProvider = DormisonEngine()) throws {
        let loader = try readyLoader(step: "Open \(tool.label)", prefix: prefix, engine: engine)
        try Shell.detach(
            loader.path(percentEncoded: false),
            [tool.rawValue],
            environment: environment(prefix: prefix, engine: engine)
        )
    }

    static func run(
        _ executable: URL,
        in prefix: WinePrefix,
        engine: any EngineProvider = DormisonEngine()
    ) throws {
        let step = "Run \(executable.lastPathComponent)"
        let loader = try readyLoader(step: step, prefix: prefix, engine: engine)
        guard FileManager.default.fileExists(atPath: executable.path(percentEncoded: false)) else {
            throw StepFailure(step: step, detail: "No file at \(executable.path(percentEncoded: false)).")
        }
        guard let arguments = arguments(for: executable) else {
            throw StepFailure(
                step: step,
                detail: "\(executable.lastPathComponent) is not a Windows program. "
                    + "Pick an exe, msi, bat or cmd file."
            )
        }

        try Shell.detach(
            loader.path(percentEncoded: false),
            arguments,
            environment: environment(prefix: prefix, engine: engine),
            currentDirectory: executable.deletingLastPathComponent()
        )
    }

    static func arguments(for executable: URL) -> [String]? {
        let path = executable.path(percentEncoded: false)
        switch executable.pathExtension.lowercased() {
        case "exe", "bat", "cmd": return [path]
        case "msi": return ["msiexec", "/i", path]
        default: return nil
        }
    }

    static var runnableTypes: [UTType] {
        ["exe", "msi", "bat", "cmd"].compactMap { UTType(filenameExtension: $0) }
    }

    static func reveal(_ prefix: WinePrefix) {
        NSWorkspace.shared.selectFile(
            prefix.pfx.path(percentEncoded: false),
            inFileViewerRootedAtPath: prefix.root.path(percentEncoded: false)
        )
    }

    static func reveal(at url: URL) {
        NSWorkspace.shared.selectFile(
            url.path(percentEncoded: false),
            inFileViewerRootedAtPath: url.deletingLastPathComponent().path(percentEncoded: false)
        )
    }

    static func deleteBackup(_ backup: URL) throws {
        try WriteRefused.catching(backup.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: backup)
        }
    }

    static func delete(_ prefix: WinePrefix) throws {
        guard !PrefixStore.isInUse(prefix) else {
            throw StepFailure(
                step: "Delete prefix",
                detail: "\(prefix.title) is running. Quit the game first."
            )
        }
        try WriteRefused.catching(prefix.root) {
            try FileManager.default.removeItem(at: prefix.root)
        }
    }

    /// Dormison runs Windows programs through Rosetta only.
    static func prefixArch() -> PrefixArch { .x86_64 }
}
