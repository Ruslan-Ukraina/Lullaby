// Which Dormison releases this build of NotProton can run games on. A release
// is supported when the app carries the B1 ntdll.dll pair built from that
// release's commit (docs/DECISIONS.md P3-1) and its bridge (lsteamclient,
// steam.exe) was built against the same commit. The table is engine/support.json,
// copied with the ntdll files into the payload's engine-support/ by
// make app-payload. Until Phase 5 fetches it signed, a new engine waits for an
// app update that carries its row.

import Foundation

struct EngineSupportEntry: Sendable, Equatable {
    struct Ntdll: Sendable, Equatable {
        let arch: String
        /// Inside the engine, e.g. wine/lib/wine/x86_64-windows/ntdll.dll.
        let path: String
        /// The B1 file, relative to the support directory.
        let file: String
        /// The release's own file, as its engine-manifest.json lists it.
        let clean: String
        let b1: String
    }

    let version: String
    let commit: String
    let ntdll: [Ntdll]
}

struct EngineSupport: Sendable {
    static let step = "Check engine support"
    static let directoryName = "engine-support"
    /// The string the B1 hook logs; its presence tells a B1 ntdll.dll from the release's.
    static let b1Marker = Data("lead to lsteamclient".utf8)

    let root: URL
    let bridgeCommits: [String]
    let entries: [EngineSupportEntry]

    static func bundled() throws -> EngineSupport {
        try load(root: try InstallPayload.root().appending(path: directoryName))
    }

    static func load(root: URL) throws -> EngineSupport {
        let file = root.appending(path: "support.json")
        guard let data = try? Data(contentsOf: file),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              json["schema"] as? Int == 1
        else {
            throw StepFailure(
                step: step,
                detail: "This build of NotProton carries no engine support table. Run make app-payload and build the app again.")
        }
        let bridge = json["bridge"] as? [String: Any]
        let entries = (json["engines"] as? [[String: Any]] ?? []).compactMap { row -> EngineSupportEntry? in
            guard let version = row["version"] as? String, let commit = row["commit"] as? String else { return nil }
            let ntdll = (row["ntdll"] as? [[String: Any]] ?? []).compactMap { item -> EngineSupportEntry.Ntdll? in
                guard let arch = item["arch"] as? String, let path = item["path"] as? String,
                      let file = item["file"] as? String, let clean = item["clean"] as? String,
                      let b1 = item["b1"] as? String, Self.isSafeRelative(path), Self.isSafeRelative(file)
                else { return nil }
                return .init(arch: arch, path: path, file: file, clean: clean.lowercased(), b1: b1.lowercased())
            }
            return EngineSupportEntry(version: version, commit: commit, ntdll: ntdll)
        }
        return EngineSupport(
            root: root, bridgeCommits: bridge?["engineCommits"] as? [String] ?? [], entries: entries)
    }

    enum Verdict: Sendable, Equatable {
        case supported(EngineSupportEntry)
        case waiting(reason: String)
    }

    /// Supported needs all three: a row for the version, a bridge built against
    /// its commit, and both B1 files present with the digests the row gives.
    func verdict(for version: String) -> Verdict {
        guard let entry = entries.first(where: { $0.version == version }) else {
            return .waiting(reason: "This NotProton has no Steam bridge for it yet.")
        }
        guard bridgeCommits.contains(entry.commit) else {
            return .waiting(reason: "The Steam bridge has not been built for it yet.")
        }
        let arches = Set(entry.ntdll.map(\.arch))
        guard arches == ["x86_64", "i386"] else {
            return .waiting(reason: "The Steam loader patch for it is incomplete.")
        }
        for item in entry.ntdll where Digest.sha256IfPresent(root.appending(path: item.file)) != item.b1 {
            return .waiting(reason: "The Steam loader patch for it is missing from this build.")
        }
        return .supported(entry)
    }

    static func isSafeRelative(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }

    static func carriesB1(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        return data.range(of: b1Marker) != nil
    }
}
