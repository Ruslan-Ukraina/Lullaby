// Mullion, the experimental Direct3D 10/11/12 renderer on Metal (docs/ROADMAP.md section 7,
// DECISIONS P7C-*): github.com/dttdrv/mullion, LGPL-2.1-or-later, a fork of DXMT. One pinned
// release, downloaded when the player first picks it and checked against its sha256, unpacked
// into notproton/mullion/<version>/ with its licences and a note of where it came from. Its
// own install.sh is never run: it puts Mullion in place of Wine's Direct3D in the engine.
// compat_run.sh hands it to the one game through a renderer directory, as D3DMetal.
//
// Mullion's winemetal.so finds ntdll.so and winemac.so beside itself (@loader_path/), so its
// x86_64-unix directory carries links to the running engine's (runners/current); dyld
// recognises the engine's own, already loaded files behind them.

import CryptoKit
import Foundation

public struct MullionRelease: Sendable, Equatable {
    public let version: String
    public let url: URL
    public let sha256: String
    public let sizeBytes: Int64
    /// The top directory of the archive.
    public let top: String

    /// The release NotProton offers: v0.1-pre1 (2026-10-05), checked 10.10 on Dormison b2.
    public static let pinned = MullionRelease(
        version: "v0.1-pre1",
        url: URL(string: "https://github.com/dttdrv/mullion/releases/download/v0.1-pre1/mullion-v0.1-pre1.tar.gz")!,
        sha256: "f5c9256164be2e11fd3c83da7927b61627c62111392c808974245ae96a5be43f",
        sizeBytes: 13_861_538,
        top: "mullion-v0.1-pre1")

    /// What a game loads from it.
    public static let windowsFiles = ["d3d10core.dll", "d3d11.dll", "d3d12.dll", "d3d12core.dll", "dxgi.dll", "winemetal.dll"]
    public static let licenceFiles = ["LICENSE", "LICENSE.OLD", "LICENSE-LLVM.txt", "COPYING.LIB", "README.md"]
}

public struct MullionStore: Sendable {
    public let root: URL
    public var release: MullionRelease = .pinned
    /// The engine the unix half links against: runners/current/wine/lib/wine/x86_64-unix.
    public var engineUnix: URL
    public var chip: String
    public var macOS: Int
    /// Downloads `url` to `to`; the default uses URLSession.
    public var download: @Sendable (URL, URL) throws -> Void = MullionStore.urlSessionDownload

    public init(
        root: URL, engineUnix: URL, chip: String = MullionStore.chipName(),
        macOS: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    ) {
        self.root = root
        self.engineUnix = engineUnix
        self.chip = chip
        self.macOS = macOS
    }

    /// ~/Library/Application Support/notproton/mullion.
    public static var standard: MullionStore {
        MullionStore(
            root: SettingsPaths.support.appending(path: "mullion"),
            engineUnix: SettingsPaths.support.appending(path: "runners/current/wine/lib/wine/x86_64-unix"))
    }

    public enum InstallError: Error, Equatable, CustomStringConvertible {
        case unsupportedMac(String)
        case downloadFailed(String)
        case badArchive(String)

        public var description: String {
            switch self {
            case .unsupportedMac(let why): "Mullion needs an M3 or later and macOS 15 or later: \(why)"
            case .downloadFailed(let why): "Mullion could not be downloaded: \(why)"
            case .badArchive(let why): "Mullion's archive is not the one NotProton expects: \(why)"
            }
        }
    }

    // MARK: Which Macs

    /// The chip name as the system gives it: "Apple M4 Pro".
    public static func chipName() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }

    /// The M generation of a chip name, nil for anything else ("Apple M4 Pro" → 4).
    public static func generation(of chip: String) -> Int? {
        guard let range = chip.range(of: #"Apple M(\d+)"#, options: .regularExpression) else { return nil }
        return Int(chip[range].dropFirst("Apple M".count))
    }

    /// Why this Mac cannot run Mullion, or nil when it can (M3 or later, macOS 15 or later).
    public var unsupportedReason: String? {
        guard let generation = Self.generation(of: chip), generation >= 3 else {
            return "this Mac has \(chip.isEmpty ? "an unknown chip" : chip)"
        }
        guard macOS >= 15 else { return "this Mac runs macOS \(macOS)" }
        return nil
    }

    // MARK: On disk

    public var current: URL { root.appending(path: "current") }
    public var directory: URL { root.appending(path: release.version) }

    /// The pinned version, unpacked whole.
    public var installed: Bool {
        let fm = FileManager.default
        return (MullionRelease.windowsFiles.map { "x86_64-windows/\($0)" } + ["x86_64-unix/winemetal.so"]).allSatisfy {
            fm.fileExists(atPath: directory.appending(path: $0).path(percentEncoded: false))
        }
    }

    public func stateJSON() -> JSONValue {
        var object: [String: JSONValue] = [
            "version": .string(release.version),
            "installed": .bool(installed),
            "eligible": .bool(unsupportedReason == nil),
        ]
        if let reason = unsupportedReason { object["reason"] = .string(reason) }
        return .object(object)
    }

    /// Downloads, checks and unpacks the pinned release unless it is in place.
    public func install(log: (String) -> Void = { _ in }) throws {
        if let reason = unsupportedReason { throw InstallError.unsupportedMac(reason) }
        if installed {
            try linkEngine(into: directory)
            try pointCurrent()
            return
        }
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appending(path: ".\(release.top).tar.gz")
        let partial = root.appending(path: ".\(release.version).partial")
        defer {
            try? fm.removeItem(at: archive)
            try? fm.removeItem(at: partial)
        }
        log("mullion: downloading \(release.url.absoluteString)")
        do {
            try download(release.url, archive)
        } catch {
            throw InstallError.downloadFailed("\(error)")
        }
        let data = try Data(contentsOf: archive)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard Int64(data.count) == release.sizeBytes, digest == release.sha256 else {
            throw InstallError.badArchive("\(data.count) bytes, sha256 \(digest)")
        }
        try? fm.removeItem(at: partial)
        try fm.createDirectory(at: partial, withIntermediateDirectories: true)
        let tar = Process()
        tar.executableURL = URL(filePath: "/usr/bin/tar")
        tar.arguments = ["-xzf", archive.path(percentEncoded: false), "-C", partial.path(percentEncoded: false)]
        try tar.run()
        tar.waitUntilExit()
        let unpacked = partial.appending(path: release.top)
        guard tar.terminationStatus == 0 else { throw InstallError.badArchive("tar exited \(tar.terminationStatus)") }
        for name in MullionRelease.windowsFiles {
            guard fm.fileExists(atPath: unpacked.appending(path: "x86_64-windows/\(name)").path(percentEncoded: false)) else {
                throw InstallError.badArchive("no x86_64-windows/\(name)")
            }
        }
        guard fm.fileExists(atPath: unpacked.appending(path: "x86_64-unix/winemetal.so").path(percentEncoded: false)),
              fm.fileExists(atPath: unpacked.appending(path: "LICENSE").path(percentEncoded: false))
        else { throw InstallError.badArchive("no x86_64-unix/winemetal.so or LICENSE") }
        // Its own installer is not ours to run (it replaces the engine's Direct3D).
        try? fm.removeItem(at: unpacked.appending(path: "install.sh"))
        try Data(sourceNote.utf8).write(to: unpacked.appending(path: "SOURCE.txt"))
        try linkEngine(into: unpacked)
        try? fm.removeItem(at: directory)
        try fm.moveItem(at: unpacked, to: directory)
        try pointCurrent()
        log("mullion: \(release.version) installed in \(directory.path(percentEncoded: false))")
    }

    /// Where these files came from, kept beside them (LGPL: version and source).
    public var sourceNote: String {
        """
        Mullion \(release.version) — Direct3D 10/11/12 on Metal, LGPL-2.1-or-later (LICENSE; LICENSE.OLD covers \
        the DXMT code from before April 2026; LICENSE-LLVM.txt for the bundled LLVM).
        Release archive: \(release.url.absoluteString)
        sha256 \(release.sha256), \(release.sizeBytes) bytes. Source: https://github.com/dttdrv/mullion/tree/\(release.version)
        Installed by NotProton unchanged, without its install.sh; x86_64-unix/ntdll.so and winemac.so are links
        to the engine's own files.

        """
    }

    func linkEngine(into dir: URL) throws {
        let fm = FileManager.default
        for name in ["ntdll.so", "winemac.so"] {
            let link = dir.appending(path: "x86_64-unix/\(name)")
            try? fm.removeItem(at: link)
            try fm.createSymbolicLink(at: link, withDestinationURL: engineUnix.appending(path: name))
        }
    }

    func pointCurrent() throws {
        let fm = FileManager.default
        let staging = root.appending(path: ".current.new")
        try? fm.removeItem(at: staging)
        try fm.createSymbolicLink(atPath: staging.path(percentEncoded: false), withDestinationPath: release.version)
        guard rename(staging.path(percentEncoded: false), current.path(percentEncoded: false)) == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    public static func urlSessionDownload(_ url: URL, _ destination: URL) throws {
        final class Box: @unchecked Sendable { var error: Error?; var file: URL? }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.downloadTask(with: url) { file, response, error in
            if let error { box.error = error }
            else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                box.error = URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
            } else if let file {
                let moved = destination.deletingLastPathComponent().appending(path: ".download-\(UUID().uuidString)")
                do { try FileManager.default.moveItem(at: file, to: moved); box.file = moved } catch { box.error = error }
            }
            done.signal()
        }.resume()
        done.wait()
        if let error = box.error { throw error }
        guard let file = box.file else { throw URLError(.cannotCreateFile) }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: file, to: destination)
    }
}

/// The machine a Windows executable is built for, from its PE header: 0x8664 x86-64,
/// 0x14c i386, nil when the file is no PE.
public enum PEMachine {
    public static func of(_ url: URL) -> UInt16? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 64), head.count == 64, head[0] == 0x4d, head[1] == 0x5a else { return nil }
        let offset = UInt64(head[60]) | UInt64(head[61]) << 8 | UInt64(head[62]) << 16 | UInt64(head[63]) << 24
        guard (try? handle.seek(toOffset: offset)) != nil, let pe = try? handle.read(upToCount: 6), pe.count == 6,
              pe[0] == 0x50, pe[1] == 0x45, pe[2] == 0, pe[3] == 0
        else { return nil }
        return UInt16(pe[4]) | UInt16(pe[5]) << 8
    }
}
