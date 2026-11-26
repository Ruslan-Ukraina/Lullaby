// Components a setting needs and Lullaby downloads when the player turns the setting on (lby-starlight-nss):
// FSR 4 (the prepared fsr4-native-macos component) and ANR frame generation (Apex's FG-V.B20 runtime, prepared for
// Metal). Each is a pinned archive in Lullaby's "components" release: downloaded in the background, its sha256
// checked, unpacked beside the target and moved into place only when complete. The download writes its progress to
// a small file the Steam panel reads through `lullaby-settings`, so the panel can draw a progress line.
//
//   lullaby-settings component status            every component's state as JSON
//   lullaby-settings component install ID        start the background download (returns at once)
//   lullaby-settings component download ID      the download itself (what install starts)

import CryptoKit
import Foundation

public struct ComponentSpec: Sendable, Equatable {
    public let id: String
    public let url: URL
    public let sha256: String
    /// The archive's size in bytes, for the progress line before the server says it.
    public let bytes: Int64
    /// The archive's top directory, moved to `destination` (relative to the components directory).
    public let top: String
    public let destination: String
    /// A file inside `destination` that only a complete install has.
    public let marker: String
    /// A component that must be there first.
    public let requires: String?
}

public enum Components {
    // Pinned with release/components.json (componentcheck compares the two).
    public static let all: [ComponentSpec] = [
        ComponentSpec(
            id: "fsr4", url: URL(string: "https://github.com/Ruslan-Ukraina/Lullaby/releases/download/components-1/lullaby-fsr4-1.tar.xz")!,
            sha256: "45b3c32d088c06a23d9b30c8ffc74e9133f98c75a53b3ed0e0508b3655f3f8c9", bytes: 758_952,
            top: "fsr4", destination: "fsr4", marker: "dist/crossover/libfsr4hook.dylib", requires: nil),
        ComponentSpec(
            id: "anr", url: URL(string: "https://github.com/Ruslan-Ukraina/Lullaby/releases/download/components-1/lullaby-anr-fg-v20-1.tar.xz")!,
            sha256: "b5c963e81c138b4630c540252c37b50c4717ef4ecdf95913bc994f8b4ed4fc86", bytes: 319_556,
            top: "anr_runtime_v20", destination: "fsr4/build/anr_runtime_v20", marker: "manifest.json",
            requires: "fsr4"),
    ]

    public static func spec(_ id: String) -> ComponentSpec? { all.first { $0.id == id } }

    /// The component a setting needs, for the panel.
    public static func needed(by setting: SettingID) -> String? {
        switch setting {
        case .fsr4: "fsr4"
        case .anr: "anr"
        default: nil
        }
    }
}

public struct ComponentStore: Sendable {
    /// ~/Library/Application Support/lullaby/components.
    public let root: URL
    public var specs: [ComponentSpec] = Components.all

    public init(root: URL) { self.root = root }

    public static var standard: ComponentStore {
        ComponentStore(root: SettingsPaths.support.appending(path: "components"))
    }

    public enum ComponentError: Error, CustomStringConvertible {
        case unknown(String)
        case download(String)
        case checksum
        case unpack(String)

        public var description: String {
            switch self {
            case let .unknown(id): "no component \(id)"
            case let .download(why): "download failed: \(why)"
            case .checksum: "the archive does not match its checksum"
            case let .unpack(why): "unpacking failed: \(why)"
            }
        }
    }

    func spec(_ id: String) throws -> ComponentSpec {
        guard let s = specs.first(where: { $0.id == id }) else { throw ComponentError.unknown(id) }
        return s
    }

    var downloads: URL { root.appending(path: ".downloads") }
    func progressFile(_ id: String) -> URL { downloads.appending(path: "\(id).json") }

    public func isInstalled(_ spec: ComponentSpec) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: spec.destination).appending(path: spec.marker)
            .path(percentEncoded: false))
    }

    // MARK: - State

    /// One component's state: installed, idle (not there), or the last download's progress.
    /// A download whose file has not moved for 20 s, or whose process is gone, counts as failed.
    public func status(_ id: String) throws -> JSONValue {
        let spec = try spec(id)
        if isInstalled(spec) { return .object(["state": .string("installed")]) }
        guard let data = try? Data(contentsOf: progressFile(id)), let progress = try? JSONValue.parse(
            String(decoding: data, as: UTF8.self)), var object = progress.object else {
            return .object(["state": .string("idle"), "total": .number(Int(spec.bytes))])
        }
        if object["state"]?.string == "downloading" || object["state"]?.string == "installing" {
            let updated = object["updated"]?.number ?? 0
            let pid = object["pid"]?.number ?? 0
            let age = Int(Date().timeIntervalSince1970) - updated
            // just started (no pid of the download yet) counts as alive for a few seconds
            let alive = pid > 0 ? kill(pid_t(pid), 0) == 0 : age <= 5
            if !alive || age > 20 {
                object["state"] = .string("failed")
                object["error"] = .string("the download stopped")
            }
        }
        return .object(object)
    }

    public func statusJSON() -> JSONValue {
        .object(Dictionary(uniqueKeysWithValues: specs.map { ($0.id, (try? status($0.id)) ?? .null) }))
    }

    // MARK: - Starting a download

    /// Starts `executable component download ID` in a session of its own, so it outlives the
    /// panel's request; nothing happens when the component is there or already downloading.
    public func start(_ id: String, executable: String) throws {
        let spec = try spec(id)
        if isInstalled(spec) { return }
        if let state = try status(id).object?["state"]?.string, state == "downloading" || state == "installing" { return }
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try write(id, ["state": .string("downloading"), "received": .number(0), "total": .number(Int(spec.bytes)),
                       "pid": .number(0)])
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        // its own session (the panel's request ends at once), and no descriptor of ours (the bridge's pipe) open in it
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))
        defer { posix_spawnattr_destroy(&attributes) }
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        defer { posix_spawn_file_actions_destroy(&actions) }
        let arguments = [executable, "--components", root.path(percentEncoded: false), "component", "download", id]
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        var envp: [UnsafeMutablePointer<CChar>?] = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var pid: pid_t = 0
        let rc = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
        guard rc == 0 else {
            try write(id, ["state": .string("failed"), "error": .string("could not start the download (\(rc))")])
            throw ComponentError.download("posix_spawn \(rc)")
        }
        // the download's own pid at once, unless it has already written its first progress
        if let object = try? JSONValue.parse(String(decoding: Data(contentsOf: progressFile(id)), as: UTF8.self)).object,
           (object["pid"]?.number ?? 0) == 0 {
            try? write(id, ["state": .string("downloading"), "received": .number(0), "total": .number(Int(spec.bytes)),
                            "pid": .number(Int(pid))])
        }
    }

    // MARK: - The download

    /// Downloads and installs `id`, and first what it requires; blocks until done. Progress (bytes,
    /// speed, time left) goes to the progress file of `id`, covering the whole chain.
    public func download(_ id: String) throws {
        let target = try spec(id)
        var chain = [target]
        var next = target.requires
        while let r = next, let s = specs.first(where: { $0.id == r }), !isInstalled(s) {
            chain.insert(s, at: 0); next = s.requires
        }
        chain = chain.filter { !isInstalled($0) }
        let total = chain.reduce(Int64(0)) { $0 + $1.bytes }
        var done: Int64 = 0
        let started = Date()
        do {
            for spec in chain {
                let before = done
                let archive = try fetch(spec) { received in
                    let got = before + received
                    let seconds = max(Date().timeIntervalSince(started), 0.001)
                    let speed = Double(got) / seconds
                    let left = speed > 0 ? Double(max(total - got, 0)) / speed : 0
                    try? write(id, ["state": .string("downloading"), "received": .number(Int(got)),
                                    "total": .number(Int(total)), "speed": .number(Int(speed)),
                                    "left": .number(Int(left.rounded(.up)))])
                }
                try write(id, ["state": .string("installing"), "received": .number(Int(done + spec.bytes)),
                               "total": .number(Int(total))])
                try install(spec, archive: archive)
                done += spec.bytes
            }
            try? FileManager.default.removeItem(at: progressFile(id))
        } catch {
            try? write(id, ["state": .string("failed"), "error": .string("\(error)")])
            throw error
        }
    }

    func write(_ id: String, _ fields: [String: JSONValue]) throws {
        var object = fields
        object["updated"] = .number(Int(Date().timeIntervalSince1970))
        if object["pid"] == nil { object["pid"] = .number(Int(getpid())) }
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try Data(JSONValue.object(object).text.utf8).write(to: progressFile(id), options: .atomic)
    }

    /// The archive in a temporary file, its checksum verified.
    func fetch(_ spec: ComponentSpec, progress: @escaping @Sendable (Int64) -> Void) throws -> URL {
        let file = downloads.appending(path: "\(spec.id).partial")
        try? FileManager.default.removeItem(at: file)
        let loader = Loader(progress: progress)
        try loader.load(spec.url, to: file)
        guard try sha256(of: file) == spec.sha256 else {
            try? FileManager.default.removeItem(at: file)
            throw ComponentError.checksum
        }
        return file
    }

    func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Unpacks beside the target and moves the archive's top directory into place; what was there
    /// before (an older or broken copy) is set aside and removed only after the move.
    func install(_ spec: ComponentSpec, archive: URL) throws {
        let fm = FileManager.default
        let unpack = downloads.appending(path: "\(spec.id).unpack")
        try? fm.removeItem(at: unpack)
        try fm.createDirectory(at: unpack, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: unpack); try? fm.removeItem(at: archive) }
        let tar = Process()
        tar.executableURL = URL(filePath: "/usr/bin/tar")
        tar.arguments = ["-xJf", archive.path(percentEncoded: false), "-C", unpack.path(percentEncoded: false)]
        try tar.run()
        tar.waitUntilExit()
        let top = unpack.appending(path: spec.top)
        guard tar.terminationStatus == 0, fm.fileExists(atPath: top.appending(path: spec.marker).path(percentEncoded: false))
        else { throw ComponentError.unpack("tar \(tar.terminationStatus)") }
        let destination = root.appending(path: spec.destination)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var aside: URL?
        if fm.fileExists(atPath: destination.path(percentEncoded: false)) {
            let old = downloads.appending(path: "\(spec.id).old")
            try? fm.removeItem(at: old)
            try fm.moveItem(at: destination, to: old)
            aside = old
        }
        do {
            try fm.moveItem(at: top, to: destination)
        } catch {
            if let aside { try? fm.moveItem(at: aside, to: destination) }
            throw ComponentError.unpack("\(error)")
        }
        if let aside { try? fm.removeItem(at: aside) }
    }
}

/// A URLSession download that reports how many bytes have arrived, waited for synchronously.
final class Loader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Int64) -> Void
    let done = DispatchSemaphore(value: 0)
    var target: URL?
    var failure: Error?
    var lastReport = Date.distantPast

    init(progress: @escaping @Sendable (Int64) -> Void) { self.progress = progress }

    func load(_ url: URL, to file: URL) throws {
        target = file
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        session.downloadTask(with: url).resume()
        done.wait()
        session.finishTasksAndInvalidate()
        if let failure { throw failure }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if Date().timeIntervalSince(lastReport) >= 0.25 { lastReport = Date(); progress(totalBytesWritten) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            failure = ComponentStore.ComponentError.download("HTTP \(http.statusCode)")
            return
        }
        guard let target else { return }
        do { try FileManager.default.moveItem(at: location, to: target) } catch { failure = error }
        progress(downloadTask.countOfBytesReceived)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, failure == nil { failure = ComponentStore.ComponentError.download(error.localizedDescription) }
        done.signal()
    }
}
