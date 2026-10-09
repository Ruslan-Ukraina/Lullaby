// D3DMetal from the player's own copy of Apple's Game Porting Toolkit (docs/ROADMAP.md
// section 6). Apple's evaluation environment is not ours to redistribute: the player
// downloads the disk image from Apple and points NotProton at it; nothing of it is in this
// repository or in NotProton's releases.
//
// What lands on disk is what Apple's Read Me says to install, `redist/lib/` with its own
// shape: `d3dmetal/<version>/lib/{external, wine/x86_64-unix, wine/x86_64-windows}` in one
// store under notproton/, kept across engine updates and roll-backs. The `.so` files there
// are symlinks into `../../external/`, so the tree is copied whole with ditto. compat_run.sh
// puts the newest usable version's `lib/external` into the running engine's `wine/lib` at
// each D3DMetal launch (the engine already carries the `.so` links to it), and the Windows
// DLLs reach the one game through a renderer directory, as DXMT's do.
//
// Shaped after Sevoflurane's Core/Setup/D3DMetalInstaller.swift (MIT, Copyright (c) 2026
// kageroumado).

import Foundation

public struct D3DMetalToolkit: Equatable, Sendable, Comparable {
    /// As Apple names it: "3.0", "4.0 beta 2".
    public let version: String
    public let root: URL

    /// Newest last; a beta sorts after the release of its number, the order Apple ships in.
    public static func < (lhs: D3DMetalToolkit, rhs: D3DMetalToolkit) -> Bool {
        lhs.version.compare(rhs.version, options: .numeric) == .orderedAscending
    }

    public var major: Int { Int(version.prefix { $0.isNumber }) ?? 0 }

    /// D3DMetal 4 is built against macOS 27 (docs/ROADMAP.md section 6); 3 runs on 26.
    public var requiredMacOS: Int { major >= 4 ? 27 : 14 }

    public var external: URL { root.appending(path: "lib/external") }
    public var windows: URL { root.appending(path: "lib/wine/x86_64-windows") }
    public var unix: URL { root.appending(path: "lib/wine/x86_64-unix") }
}

public struct D3DMetalStore: Sendable {
    public let root: URL
    /// The macOS major version this Mac runs.
    public var macOS: Int

    public init(root: URL, macOS: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) {
        self.root = root
        self.macOS = macOS
    }

    /// ~/Library/Application Support/notproton/d3dmetal.
    public static var standard: D3DMetalStore {
        D3DMetalStore(root: SettingsPaths.support.appending(path: "d3dmetal"))
    }

    public enum InstallError: Error, Equatable, CustomStringConvertible {
        case notAToolkit(String)
        case attachFailed(String)
        case copyFailed(String)

        public var description: String {
            switch self {
            case let .notAToolkit(path):
                "\(path) does not hold Apple's evaluation environment (no redist/lib/external/D3DMetal.framework)"
            case let .attachFailed(detail): "could not open the disk image: \(detail)"
            case let .copyFailed(detail): "could not install D3DMetal: \(detail)"
            }
        }
    }

    // MARK: - What is installed

    public func installed() -> [D3DMetalToolkit] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return entries.filter {
            FileManager.default.fileExists(atPath: $0.appending(path: "lib/external/D3DMetal.framework")
                .path(percentEncoded: false))
                && FileManager.default.fileExists(atPath: $0.appending(path: "lib/wine/x86_64-windows/d3d12.dll")
                    .path(percentEncoded: false))
        }.map { D3DMetalToolkit(version: $0.lastPathComponent, root: $0) }.sorted()
    }

    /// The version a game gets: the newest this macOS can run.
    public func active() -> D3DMetalToolkit? {
        installed().last { $0.requiredMacOS <= macOS }
    }

    /// Installed versions this Mac cannot run, for an honest line in the panel.
    public func unusable() -> [D3DMetalToolkit] {
        installed().filter { $0.requiredMacOS > macOS }
    }

    // MARK: - Installing

    /// Copies D3DMetal out of `source`: the Game Porting Toolkit disk image, the inner
    /// "Evaluation environment" image, a mounted volume, or an unpacked copy of either.
    @discardableResult
    public func install(from source: URL) throws -> D3DMetalToolkit {
        var attached: [URL] = []
        defer { for volume in attached.reversed() { Self.detach(volume) } }

        var searchRoot = source
        if source.pathExtension.lowercased() == "dmg" {
            let volume = try Self.attach(source)
            attached.append(volume)
            searchRoot = volume
        }
        // The download nests one image in another: "Evaluation environment for Windows
        // games <version>.dmg" inside the toolkit's.
        if Self.redistLib(under: searchRoot) == nil, let inner = Self.innerImage(under: searchRoot) {
            let volume = try Self.attach(inner)
            attached.append(volume)
            searchRoot = volume
        }
        guard let lib = Self.redistLib(under: searchRoot) else {
            throw InstallError.notAToolkit(source.path(percentEncoded: false))
        }
        let version = Self.version(ofVolume: searchRoot)
        let destination = root.appending(path: version)
        let staging = root.appending(path: ".\(version).installing")
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            if manager.fileExists(atPath: staging.path(percentEncoded: false)) { try manager.removeItem(at: staging) }
            try manager.createDirectory(at: staging, withIntermediateDirectories: true)
            // Apple's instruction is `ditto redist/lib/ .`: ditto keeps the symlinks as links.
            try Self.run("/usr/bin/ditto", [lib.path(percentEncoded: false),
                                            staging.appending(path: "lib").path(percentEncoded: false)])
            if manager.fileExists(atPath: destination.path(percentEncoded: false)) {
                try manager.removeItem(at: destination)
            }
            try manager.moveItem(at: staging, to: destination)
        } catch {
            try? manager.removeItem(at: staging)
            throw InstallError.copyFailed("\(error)")
        }
        return D3DMetalToolkit(version: version, root: destination)
    }

    static func redistLib(under root: URL) -> URL? {
        let lib = root.appending(path: "redist/lib")
        return FileManager.default.fileExists(atPath: lib.appending(path: "external/D3DMetal.framework")
            .path(percentEncoded: false)) ? lib : nil
    }

    static func innerImage(under root: URL) -> URL? {
        ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .first { $0.pathExtension.lowercased() == "dmg"
                && $0.lastPathComponent.localizedCaseInsensitiveContains("evaluation") }
    }

    /// Apple writes the version into the volume's name: "Evaluation environment for
    /// Windows games 4.0 beta 2" (a second mount of it gets " 1" after it).
    public static func version(ofVolume volume: URL) -> String {
        let name = volume.lastPathComponent
        guard let range = name.range(of: #"[0-9]+\.[0-9]+( beta [0-9]+)?"#, options: .regularExpression)
        else { return "unknown" }
        return String(name[range])
    }

    /// Mounts an image and answers its volume. A volume that was mounted before (the player
    /// opened the image in Finder) is answered too, but is not ours to unmount afterwards.
    static func attach(_ image: URL) throws -> URL {
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? [])
        let volume = try attachVolume(image)
        if before.contains(volume.lastPathComponent) { preexisting.insert(volume.path(percentEncoded: false)) }
        return volume
    }

    nonisolated(unsafe) static var preexisting: Set<String> = []

    static func attachVolume(_ image: URL) throws -> URL {
        let output = try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-plist",
                                                   image.path(percentEncoded: false)])
        guard let plist = try? PropertyListSerialization.propertyList(from: Data(output.utf8), format: nil)
                as? [String: Any],
            let entities = plist["system-entities"] as? [[String: Any]],
            let mount = entities.compactMap({ $0["mount-point"] as? String }).first
        else { throw InstallError.attachFailed(String(output.suffix(200))) }
        return URL(filePath: mount)
    }

    /// Waits: the images are nested, the outer one comes down after the inner one.
    static func detach(_ volume: URL) {
        guard preexisting.remove(volume.path(percentEncoded: false)) == nil else { return }
        _ = try? run("/usr/bin/hdiutil", ["detach", "-quiet", volume.path(percentEncoded: false)])
    }

    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw InstallError.attachFailed("\(tool) \(arguments.first ?? ""): \(text.suffix(300))")
        }
        return text
    }

    // MARK: - Asynchronous install for the Steam panel

    /// The panel's request comes and goes within seconds; choosing and copying a toolkit
    /// takes longer. The CLI starts an install in the background and records how it went
    /// here, and the panel reads it with the game's state.
    public var statusURL: URL { root.appending(path: ".install-status.json") }

    public func status() -> JSONValue? {
        guard let data = try? Data(contentsOf: statusURL) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    public func setStatus(_ value: JSONValue) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? Data(value.text.utf8).write(to: statusURL, options: .atomic)
    }

    /// What the panel shows about D3DMetal.
    public func stateJSON() -> JSONValue {
        var object: [String: JSONValue] = [
            "installed": .array(installed().map { .string($0.version) }),
            "macOS": .number(macOS),
        ]
        if let active = active() { object["active"] = .string(active.version) }
        let blocked = unusable()
        if !blocked.isEmpty {
            object["unusable"] = .array(blocked.map {
                .object(["version": .string($0.version), "requires": .number($0.requiredMacOS)])
            })
        }
        if let status = status() { object["status"] = status }
        return .object(object)
    }
}
