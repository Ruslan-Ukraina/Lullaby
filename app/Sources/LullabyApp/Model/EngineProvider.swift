// Where the Wine engine lives and what it can do. Everything that needs the
// loader, the server or the DLL directories asks an EngineProvider instead of
// building paths, so the layout is written down in one place.

import Foundation

enum EngineArch: String, Sendable {
    case x86_64
    case i386

    var windowsDirectory: String { "\(rawValue)-windows" }
}

protocol EngineProvider: Sendable {
    var root: URL { get }
    /// Name of the installed build, e.g. "dormison-b1".
    var version: String { get }
    /// The front door of the engine, `wine/bin/wine`.
    var wineloader: URL { get }
    var wineserver: URL { get }
    /// The loader proper: the one the engine re-executes every Windows program
    /// through, and the one a game's bundle carries a copy of.
    var unixLoader: URL { get }
    func dllPaths(arch: EngineArch) -> [URL]
    var unixDirectory: URL { get }
    var capabilities: EngineCapabilities { get }
}

struct EngineCapabilities: Sendable, Equatable {
    var commit: String?
    var wine: String?
    var sync: String?
    var renderers: [String] = []
    var features: [String] = []
}

/// The Dormison engine unpacked under runners/<tag>.
struct DormisonEngine: EngineProvider {

    let root: URL

    init(root: URL = SupportPaths.currentRunner) { self.root = root }

    var version: String {
        if let info = Self.info(at: root), let version = info["version"] as? String { return version }
        return root.resolvingSymlinksInPath().lastPathComponent
    }

    var wineloader: URL { root.appending(path: "wine/bin/wine") }
    var wineserver: URL { root.appending(path: "wine/bin/wineserver") }
    var unixDirectory: URL { root.appending(path: "wine/lib/wine/x86_64-unix") }
    var unixLoader: URL { unixDirectory.appending(path: "wine") }

    func dllPaths(arch: EngineArch) -> [URL] {
        [root.appending(path: "wine/lib/wine/\(arch.windowsDirectory)")]
    }

    var capabilities: EngineCapabilities {
        guard let info = Self.info(at: root) else { return EngineCapabilities() }
        return EngineCapabilities(
            commit: info["commit"] as? String, wine: info["wine"] as? String,
            sync: info["sync"] as? String, renderers: info["renderers"] as? [String] ?? [],
            features: info["features"] as? [String] ?? [])
    }

    /// Both executables are in place: what "an engine is installed" means.
    var isUsable: Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: wineloader.path(percentEncoded: false))
            && fm.isExecutableFile(atPath: wineserver.path(percentEncoded: false))
    }

    private static func info(at root: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: root.appending(path: "engine-info.json")) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: lullaby-engine.env

    static let envFileName = "lullaby-engine.env"

    /// What compat_run.sh sources. One NAME='value' per line, single-quoted so the
    /// shell never expands anything.
    var environmentFile: String {
        let dllPath = { (arch: EngineArch) in
            dllPaths(arch: arch).map { $0.path(percentEncoded: false) }.joined(separator: ":")
        }
        let pairs: [(String, String)] = [
            ("LB_ENGINE_VERSION", version),
            ("LB_ENGINE_COMMIT", capabilities.commit ?? ""),
            ("LB_ENGINE_WINELOADER", wineloader.path(percentEncoded: false)),
            ("LB_ENGINE_WINESERVER", wineserver.path(percentEncoded: false)),
            ("LB_ENGINE_UNIX_DIR", unixDirectory.path(percentEncoded: false)),
            ("LB_ENGINE_DLLPATH_X86_64", dllPath(.x86_64)),
            ("LB_ENGINE_DLLPATH_I386", dllPath(.i386)),
        ]
        return "# Written by Lullaby for compat_run.sh. Do not edit.\n"
            + pairs.map { "\($0.0)=\(Self.quote($0.1))" }.joined(separator: "\n") + "\n"
    }

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Writes the file into the engine's real directory, with that directory's own
    /// paths, so switching `current` to another engine needs no rewrite.
    @discardableResult
    func writeEnvironmentFile() throws -> URL {
        let real = DormisonEngine(root: root.resolvingSymlinksInPath())
        let url = real.root.appending(path: Self.envFileName)
        try real.environmentFile.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Brings the env file in line with the engine on disk; does nothing when
    /// there is no engine or the file is already right.
    @discardableResult
    func ensureEnvironmentFile() -> Bool {
        let real = DormisonEngine(root: root.resolvingSymlinksInPath())
        guard real.isUsable else { return false }
        let url = real.root.appending(path: Self.envFileName)
        if (try? String(contentsOf: url, encoding: .utf8)) == real.environmentFile { return true }
        return (try? writeEnvironmentFile()) != nil
    }
}
