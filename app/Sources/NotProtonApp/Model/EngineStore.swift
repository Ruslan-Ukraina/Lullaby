// The engines under runners/, which of them is current, and switching between
// them. Installing, reinstalling and rolling back are EngineUpdater's; this looks
// at what is on disk and moves the `current` link.

import Foundation

enum EngineState: Sendable, Equatable {
    case none
    case broken(detail: String)
    case engine(version: String)
}

struct InstalledEngine: Sendable, Equatable, Identifiable {
    /// The directory name under runners/, e.g. "dormison-b1".
    let tag: String
    var id: String { tag }
}

enum EngineStore {

    static let step = "Switch engine"
    static let removeStep = "Remove engine"
    static let prefix = "dormison-"

    static func state(runners: URL = SupportPaths.runners) -> EngineState {
        let fm = FileManager.default
        let current = runners.appending(path: "current")
        let currentPath = current.path(percentEncoded: false)

        guard let attributes = try? fm.attributesOfItem(atPath: currentPath),
              attributes[.type] as? FileAttributeType == .typeSymbolicLink
        else {
            if fm.fileExists(atPath: currentPath) {
                return .broken(detail: "runners/current is not a symlink.")
            }
            return .none
        }
        guard let target = try? fm.destinationOfSymbolicLink(atPath: currentPath) else {
            return .broken(detail: "runners/current cannot be read.")
        }
        let engine = DormisonEngine(root: runners.appending(path: target).standardizedFileURL)
        guard target.hasPrefix(prefix) else {
            return .broken(detail: "runners/current points at \(target), which is not a Dormison engine.")
        }
        guard engine.isUsable else {
            return .broken(detail: "runners/current points at \(target), which has no engine in it.")
        }
        let version = engine.version
        return .engine(version: version.hasPrefix(prefix) ? version : target)
    }

    static func currentTag(runners: URL = SupportPaths.runners) -> String? {
        let current = runners.appending(path: "current").path(percentEncoded: false)
        return try? FileManager.default.destinationOfSymbolicLink(atPath: current)
    }

    /// Complete engines only: a half-unpacked `.partial` folder or a directory
    /// without the executables is not listed.
    static func installed(in runners: URL = SupportPaths.runners) -> [InstalledEngine] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: runners, includingPropertiesForKeys: nil)) ?? []
        return entries
            .filter { $0.lastPathComponent.hasPrefix(prefix) && DormisonEngine(root: $0).isUsable }
            .map { InstalledEngine(tag: $0.lastPathComponent) }
            .sorted { $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
    }

    static func size(of tag: String, runners: URL = SupportPaths.runners) -> Int64 {
        guard let walker = FileManager.default.enumerator(
            at: runners.appending(path: tag),
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: []
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            let values = try? url.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }

    static let currentLink = "current"

    /// Points `current` at another installed engine by renaming a new link over
    /// the old one, so there is no moment without a current engine. The engine it
    /// leaves becomes `previous`, the one Rollback returns to.
    /// `bridge` defaults to the bridge beside `runners` (notproton/bridge).
    static func switchTo(_ tag: String, runners: URL = SupportPaths.runners, bridge: URL? = nil) throws {
        guard tag.hasPrefix(prefix), !tag.contains("/"),
              DormisonEngine(root: runners.appending(path: tag)).isUsable
        else { throw StepFailure(step: step, detail: "\(tag) is not an installed engine.") }
        let old = currentTag(runners: runners)
        DormisonEngine(root: runners.appending(path: tag)).ensureEnvironmentFile()
        try pointLink(currentLink, at: tag, in: runners)
        if let old, old != tag {
            try? pointLink(EngineUpdater.previousLink, at: old, in: runners)
        }
        EngineUpdater.syncBridgeNtdll(
            engine: runners.appending(path: tag),
            bridge: bridge ?? runners.deletingLastPathComponent().appending(path: "bridge"))
    }

    /// runners/<name> -> <target>, replaced by rename.
    static func pointLink(_ name: String, at target: String, in runners: URL) throws {
        let fm = FileManager.default
        let staging = runners.appending(path: ".\(name).new")
        try? fm.removeItem(at: staging)
        try fm.createSymbolicLink(atPath: staging.path(percentEncoded: false), withDestinationPath: target)
        let link = runners.appending(path: name).path(percentEncoded: false)
        if rename(staging.path(percentEncoded: false), link) != 0 {
            let reason = String(cString: strerror(errno))
            try? fm.removeItem(at: staging)
            throw StepFailure(step: step, detail: "Could not point \(name) at \(target). \(reason)")
        }
    }

    static func remove(_ tag: String, runners: URL = SupportPaths.runners) throws {
        let target = runners.appending(path: tag)
        let path = target.path(percentEncoded: false)
        guard tag.hasPrefix(prefix), !tag.contains("/"), FileManager.default.fileExists(atPath: path)
        else { throw StepFailure(step: removeStep, detail: "\(tag) is not installed.") }
        guard currentTag(runners: runners) != tag else {
            throw StepFailure(
                step: removeStep, detail: "\(tag) is the active engine. Switch to another one first.")
        }
        try WriteRefused.catching(path) { try FileManager.default.removeItem(at: target) }
        let previous = runners.appending(path: EngineUpdater.previousLink).path(percentEncoded: false)
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: previous)) == tag {
            try? FileManager.default.removeItem(atPath: previous)
        }
    }

    static func displayName(_ tag: String) -> String {
        tag.hasPrefix(prefix) ? "Dormison " + tag.dropFirst(prefix.count) : tag
    }
}
