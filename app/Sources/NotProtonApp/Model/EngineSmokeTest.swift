// Before an engine becomes current it has to start: `wine --version`, then
// `wineboot --init` in a throwaway prefix, whose system32 and syswow64 must then
// carry the B1 ntdll.dll. The prefix and its wineserver are gone afterwards.

import Foundation

enum EngineSmokeTest {
    static let step = "Test the engine"

    /// Returns a one-line summary for the log, throws with the tail of Wine's output.
    static func run(engine: URL, timeout: TimeInterval = 300) throws -> String {
        let fm = FileManager.default
        let wine = engine.appending(path: "wine/bin/wine")
        let wineserver = engine.appending(path: "wine/bin/wineserver")
        let scratch = fm.temporaryDirectory.appending(path: "notproton-engine-test-\(UUID().uuidString)")
        let prefix = scratch.appending(path: "pfx")
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }

        var environment = ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("WINE") && !$0.key.hasPrefix("SEVO_") && !$0.key.hasPrefix("DYLD_")
        }
        environment["WINEPREFIX"] = prefix.path(percentEncoded: false)
        environment["WINEDEBUG"] = "-all"
        environment["WINEMSYNC"] = "1"
        environment["WINEDLLOVERRIDES"] = "mscoree,mshtml=;winemenubuilder.exe=d"
        environment["SEVO_QUIET"] = "1"
        // Never reach Sevoflurane from here (docs/DECISIONS.md S1).
        environment["SEVO_CLI"] = SupportPaths.sevoCLI.path(percentEncoded: false)
        environment["SEVO_LOADER_TREE"] = engine.path(percentEncoded: false)

        let version = try execute(wine, ["--version"], environment: environment, timeout: 60,
                                  log: scratch.appending(path: "version.log"))
        let versionLine = version.trimmingCharacters(in: .whitespacesAndNewlines)
        // Dormison prints its own name, e.g. "dormison-b1 (Staging)".
        guard !versionLine.isEmpty, !versionLine.contains("\n") else {
            throw StepFailure(step: step, detail: "wine --version printed \"\(versionLine.prefix(80))\".")
        }

        defer {
            _ = try? execute(wineserver, ["-k"], environment: environment, timeout: 30,
                             log: scratch.appending(path: "kill.log"))
            waitForQuiet(engine)
        }
        _ = try execute(wine, ["wineboot", "--init"], environment: environment, timeout: timeout,
                        log: scratch.appending(path: "wineboot.log"))
        _ = try? execute(wineserver, ["-w"], environment: environment, timeout: 60,
                         log: scratch.appending(path: "wait.log"))

        let system32 = prefix.appending(path: "drive_c/windows/system32")
        guard fm.fileExists(atPath: system32.appending(path: "kernel32.dll").path(percentEncoded: false)) else {
            throw StepFailure(step: step, detail: "wineboot did not create a Windows folder.")
        }
        for folder in ["system32", "syswow64"] {
            let ntdll = prefix.appending(path: "drive_c/windows/\(folder)/ntdll.dll")
            guard EngineSupport.carriesB1(ntdll) else {
                throw StepFailure(step: step, detail: "The test prefix did not get the patched \(folder)\\ntdll.dll.")
            }
        }
        return "\(versionLine), wineboot created a prefix with the B1 ntdll.dll (x86_64 and i386)"
    }

    /// Output goes to a file: wineserver can inherit a pipe and hold it open.
    @discardableResult
    static func execute(
        _ executable: URL, _ arguments: [String], environment: [String: String],
        timeout: TimeInterval, log: URL
    ) throws -> String {
        FileManager.default.createFile(atPath: log.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        let name = ([executable.lastPathComponent] + arguments.prefix(1)).joined(separator: " ")
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 1)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            AppLog.note("engine test: \(name) timed out after \(Int(timeout)) s: \(tail(output))")
            throw StepFailure(step: step, detail: "\(name) did not finish within \(Int(timeout)) seconds.")
        }
        guard process.terminationStatus == 0 else {
            AppLog.note("engine test: \(name) exited \(process.terminationStatus): \(tail(output))")
            throw StepFailure(
                step: step, detail: "\(name) failed with status \(process.terminationStatus). \(tail(output))")
        }
        return output
    }

    private static func tail(_ text: String) -> String {
        text.split(separator: "\n").suffix(3).joined(separator: " | ")
    }

    /// Nothing started from the tested tree may outlive the test: the updater
    /// treats a process running from runners/ as a game.
    private static func waitForQuiet(_ engine: URL) {
        let path = engine.path(percentEncoded: false)
        for _ in 0..<100 where Shell.processIsRunning(commandLineContaining: path) {
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
}
