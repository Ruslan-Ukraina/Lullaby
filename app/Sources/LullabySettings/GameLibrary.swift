// Where a game's prefix and files are: Steam libraries from libraryfolders.vdf,
// `steamapps/compatdata/<appid>/pfx` and `steamapps/common/<installdir>`.

import Foundation

public struct GameLibrary: Sendable {
    /// Steam library roots (the folders that hold `steamapps`).
    public let roots: [URL]

    public init(roots: [URL]) {
        self.roots = roots
    }

    /// The libraries Steam lists, the default one first.
    public static func standard(steam: URL = SettingsPaths.steamUserData) -> GameLibrary {
        let vdf = steam.appending(path: "steamapps/libraryfolders.vdf")
        var roots = [steam]
        if let text = try? String(contentsOf: vdf, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                let fields = line.split(separator: "\"").map(String.init)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                guard fields.count >= 2, fields[0] == "path" else { continue }
                roots.append(URL(filePath: fields[1]))
            }
        }
        var seen: Set<String> = []
        return GameLibrary(roots: roots.filter { seen.insert($0.standardizedFileURL.path).inserted })
    }

    /// The game's prefix (`…/compatdata/<appid>/pfx`) in whichever library has one.
    public func prefixes(of appID: Int) -> [URL] {
        roots.map { $0.appending(path: "steamapps/compatdata/\(appID)/pfx") }
            .filter { isDirectory($0) }
    }

    /// Every Lullaby prefix: compatdata entries whose prefix the run script set up
    /// for Dormison (it holds `.sevo`).
    public func allPrefixes() -> [(appID: Int, prefix: URL)] {
        var found: [(Int, URL)] = []
        for root in roots {
            let compat = root.appending(path: "steamapps/compatdata")
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: compat, includingPropertiesForKeys: nil)) ?? []
            for entry in entries {
                guard let id = Int(entry.lastPathComponent), id > 0 else { continue }
                let pfx = entry.appending(path: "pfx")
                if isDirectory(pfx.appending(path: ".sevo")) { found.append((id, pfx)) }
            }
        }
        return found.sorted { $0.0 < $1.0 }
    }

    /// Name and install directory from the app manifest.
    public func installed(_ appID: Int) -> (name: String?, directory: URL)? {
        for root in roots {
            let steamapps = root.appending(path: "steamapps")
            let manifest = steamapps.appending(path: "appmanifest_\(appID).acf")
            guard let text = try? String(contentsOf: manifest, encoding: .utf8),
                let dir = Self.manifestValue("installdir", in: text), !dir.isEmpty, !dir.contains("..")
            else { continue }
            let directory = steamapps.appending(path: "common").appending(path: dir)
            guard isDirectory(directory) else { continue }
            return (Self.manifestValue("name", in: text), directory)
        }
        return nil
    }

    static func manifestValue(_ key: String, in text: String) -> String? {
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: "\"", omittingEmptySubsequences: false).map(String.init)
            // \t"key"\t\t"value"
            guard fields.count >= 5, fields[1] == key else { continue }
            return fields[3]
        }
        return nil
    }

    private func isDirectory(_ url: URL) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &dir)
            && dir.boolValue
    }
}

/// Which executables are a game's own, the way Sevoflurane's Core/GameExecutables.swift
/// (MIT, Copyright (c) 2026 kageroumado) tells them: the install directory to three
/// levels, without the tools games ship beside themselves, and Windows' own programs.
public enum GameExecutables {
    static let maxDepth = 3

    static let excludedFragments = [
        "unins", "crash", "report", "redist", "vc_redist", "vcredist", "dxsetup",
        "directx", "dotnet", "setup", "install", "uninstall", "cleanup", "updater",
        "ue4prereq", "ueprereq", "easyanticheat", "eac", "battleye",
    ]

    /// Windows' and Wine's own programs, and Lullaby's Steam shim: never a game.
    static let windowsTools: Set<String> = [
        "steam.exe", "explorer.exe", "services.exe", "winedevice.exe", "plugplay.exe", "svchost.exe",
        "rpcss.exe", "conhost.exe", "wineboot.exe", "start.exe", "rundll32.exe", "iscriptevaluator.exe",
        "load_steamclient.exe", "tabtip.exe", "winemenubuilder.exe",
        "regsvr32.exe", "msiexec.exe", "cmd.exe", "reg.exe", "regedit.exe", "dllhost.exe",
        "wscript.exe", "cscript.exe", "powershell.exe", "oalinst.exe", "dxwsetup.exe",
        "iexplore.exe", "winebrowser.exe", "mshta.exe", "hh.exe", "dxdiag.exe", "winecfg.exe",
        "control.exe", "taskmgr.exe", "uninstaller.exe", "wmic.exe", "tasklist.exe", "taskkill.exe",
        "schtasks.exe", "sc.exe", "net.exe", "netsh.exe", "ipconfig.exe", "xcopy.exe",
        "icacls.exe", "attrib.exe", "expand.exe", "wusa.exe", "notepad.exe", "wordpad.exe",
    ]

    /// A program's name as the engine finds its env file: the basename, lowercase.
    /// nil for anything that is not a game's own `.exe`.
    public static func recordable(_ program: String) -> String? {
        let base = program.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        let name = base.lowercased()
        guard name.hasSuffix(".exe"), name.count > 4, name.count <= 128,
            !name.contains("\n"), !windowsTools.contains(name)
        else { return nil }
        return name
    }

    public static func isGameLike(_ name: String) -> Bool {
        !excludedFragments.contains { name.contains($0) }
    }

    /// Lowercase exe names in an install directory, shallowest first.
    public static func scan(_ directory: URL) -> [String] {
        var found: [(Int, String)] = []
        var queue: [(URL, Int)] = [(directory, 0)]
        while !queue.isEmpty {
            let (folder, depth) = queue.removeFirst()
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isSymbolicLink == true { continue }
                if values?.isDirectory == true {
                    if depth + 1 <= maxDepth { queue.append((entry, depth + 1)) }
                    continue
                }
                guard let name = recordable(entry.lastPathComponent), isGameLike(name) else { continue }
                found.append((depth, name))
            }
        }
        var seen: Set<String> = []
        return found.sorted { $0.0 < $1.0 }.map(\.1).filter { seen.insert($0).inserted }
    }
}
