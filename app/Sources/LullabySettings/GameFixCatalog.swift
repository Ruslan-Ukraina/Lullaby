// The catalog of game fixes (docs/GAME_FIXES.md): declarative data per Steam app id or
// executable. Only data lives here: no scripts, no files for the game's folder, nothing
// for the game's own settings or registry (CLAUDE.md §8). The signature is checked by the
// app (ReleaseFeed.verify) before the bytes reach `decode`; one bad entry rejects the file.

import Foundation

public struct GameFix: Sendable, Equatable {
    public enum Verdict: String, Sendable { case fits, notNeeded = "not_needed", unfit }

    public struct RegistryValue: Sendable, Equatable {
        public let key: String
        public let name: String
        public let type: String
        public let value: String
    }

    /// A file the fix puts into the game's own folder (docs/GAME_FIXES.md §6): `proxy` renames
    /// the game's DLL to <name>_real<ext> and puts ours under its name; `add` puts a new file.
    public struct FileOp: Sendable, Equatable {
        public enum Kind: String, Sendable { case proxy, add }
        public let kind: Kind
        /// Relative to the game's install folder.
        public let path: String
        /// The asset's name in the fix bundle, and its hash.
        public let asset: String
        public let sha256: String
        /// For `proxy`: the hash of the game's own file this was made for (nil: any).
        public let originalSha256: String?
    }

    public struct Source: Sendable, Equatable {
        public let kind: String
        public let ref: String
        public let license: String
    }

    public let id: String
    public let name: String
    public let appIDs: [Int]
    /// Lower-case executable names.
    public let exes: [String]
    public let verdict: Verdict
    public let backend: RendererChoice?
    /// The engine tag it needs at least; older engines skip the entry.
    public let needsEngine: String?
    /// The engine tag the fix was checked on; without it the fix is shown, never applied
    /// (a draft from umu-protonfixes or MacGameFix is not proof for this stack).
    public let verifiedOn: String?
    /// From this GPTK version on the fix is not needed.
    public let notNeededFromGPTK: String?
    public let env: [String: String]
    /// umu-protonfixes' `set_cpu_topology_limit`: fewer logical processors for the game,
    /// applied only when the Mac has more (as Proton does), as SEVO_CPU_COUNT.
    public let cpuLimit: Int?
    public let dllOverrides: [String: String]
    public let files: [FileOp]
    public let registry: [RegistryValue]
    public let source: Source
    public let reason: String

    /// The renderer as recipe values (the level between the game's own and for-all-games).
    public var recipeValues: ConfigValues {
        var v = ConfigValues()
        v.renderer = backend
        return v
    }

    /// Lines for the program's .env file, in a fixed order. Registry values are not
    /// lines: they are written into the prefix by the settings service.
    public func envLines(hostProcessors: Int = ProcessInfo.processInfo.processorCount) -> [String] {
        var lines = env.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        if let cpuLimit, cpuLimit < hostProcessors { lines.append("SEVO_CPU_COUNT=\(cpuLimit)") }
        if !dllOverrides.isEmpty {
            lines.append("WINEDLLOVERRIDES=" + dllOverrides.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";"))
        }
        return lines
    }
}

public struct GameFixCatalog: Sendable, Equatable {
    public let serial: Int
    public let entries: [GameFix]

    public struct Invalid: Error, Equatable, CustomStringConvertible {
        public let description: String
    }

    static let sources: Set<String> = ["lullaby", "umu-protonfixes", "macgamefix", "highball"]
    static let overrideModes: Set<String> = ["n", "b", "n,b", "b,n", "d"]
    static let forbiddenEnv: Set<String> = [
        "WINELOADER", "WINESERVER", "WINEPREFIX", "WINEDLLOVERRIDES", "PATH", "HOME", "MTL_HUD_ENABLED",
    ]
    static let forbiddenEnvPrefixes = ["DYLD_", "LD_", "LULLABY_", "SEVO_", "WINEDLLPATH"]
    static let wineKeyPrefix = "HKCU\\Software\\Wine\\"

    /// The cached catalog (written by the app only after its signature was checked);
    /// a missing or invalid file means no catalog, never a partial one.
    public static func load(from url: URL) -> GameFixCatalog? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }

    /// Parses and validates; throws `Invalid` naming the entry and the reason.
    public static func decode(_ data: Data) throws -> GameFixCatalog {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw Invalid(description: "not a JSON object")
        }
        try only(root, ["schema", "serial", "entries"], "catalog")
        guard root["schema"] as? Int == 1 else { throw Invalid(description: "unsupported schema") }
        guard let serial = root["serial"] as? Int, serial > 0 else { throw Invalid(description: "bad serial") }
        guard let raw = root["entries"] as? [[String: Any]] else { throw Invalid(description: "no entries") }
        var seen = Set<String>()
        let entries = try raw.map { entry -> GameFix in
            let fix = try parse(entry)
            guard seen.insert(fix.id).inserted else { throw Invalid(description: "duplicate id \(fix.id)") }
            return fix
        }
        return GameFixCatalog(serial: serial, entries: entries)
    }

    /// The entry of a game: by app id first, then by an executable it runs; entries the
    /// engine or GPTK versions rule out, and `not_needed` ones, are skipped.
    public func fix(appID: Int?, exes: [String]?, engine: String?, gptk: String?) -> GameFix? {
        let usable = entries.filter { fix in
            guard fix.verdict != .notNeeded else { return false }
            if let need = fix.needsEngine, let engine, Self.compare(engine, need) == .orderedAscending { return false }
            if let from = fix.notNeededFromGPTK, let gptk, Self.compare(gptk, from) != .orderedAscending { return false }
            return true
        }
        if let appID, let byID = usable.first(where: { $0.appIDs.contains(appID) }) { return byID }
        let names = Set((exes ?? []).map { $0.lowercased() })
        return usable.first { !$0.exes.isEmpty && !names.isDisjoint(with: $0.exes) }
    }

    /// Who wins when sources disagree: Lullaby's own, then MacGameFix, Highball, umu-protonfixes.
    static let priority = ["lullaby": 0, "macgamefix": 1, "highball": 2, "umu-protonfixes": 3]

    /// What the catalog says for a game, all sources together (docs/ROADMAP.md §14.2). Entries
    /// the versions rule out, `not_needed` ones and unverified ones add nothing; an `unfit` entry
    /// of a source blocks every source below it. The renderer and the processor limit are the
    /// strongest source's; variables, DLL overrides and registry values are united, the stronger
    /// source winning a key (named in `conflicts`); files come from one source only.
    public func resolve(
        appID: Int?, exes: [String]?, engine: String?, gptk: String?
    ) -> (fix: GameFix, conflicts: [String])? {
        let names = Set((exes ?? []).map { $0.lowercased() })
        let matching = entries.filter { fix in
            if let appID, fix.appIDs.contains(appID) { return true }
            return !fix.exes.isEmpty && !names.isDisjoint(with: fix.exes)
        }.filter { fix in
            if let need = fix.needsEngine, let engine, Self.compare(engine, need) == .orderedAscending { return false }
            if let from = fix.notNeededFromGPTK, let gptk, Self.compare(gptk, from) != .orderedAscending { return false }
            return fix.verdict != .notNeeded
        }
        let ordered = matching.enumerated().sorted {
            let a = Self.priority[$0.element.source.kind] ?? 9, b = Self.priority[$1.element.source.kind] ?? 9
            return a != b ? a < b : $0.offset < $1.offset
        }.map(\.element)
        var usable: [GameFix] = []
        for fix in ordered {
            if fix.verdict == .unfit { if usable.isEmpty { return (fix, []) } else { break } }
            if fix.verifiedOn != nil { usable.append(fix) }
        }
        guard let first = usable.first else { return nil }
        var conflicts: [String] = []
        var env: [String: String] = [:], overrides: [String: String] = [:]
        var registry: [String: GameFix.RegistryValue] = [:]
        for fix in usable.reversed() {
            for (k, v) in fix.env.sorted(by: { $0.key < $1.key }) {
                if let old = env[k], old != v { conflicts.append("\(fix.id) overrides env \(k)") }
                env[k] = v
            }
            for (k, v) in fix.dllOverrides.sorted(by: { $0.key < $1.key }) {
                if let old = overrides[k], old != v { conflicts.append("\(fix.id) overrides DLL \(k)") }
                overrides[k] = v
            }
            for r in fix.registry {
                let key = r.key + "\u{0}" + r.name
                if let old = registry[key], old != r { conflicts.append("\(fix.id) overrides registry \(r.name)") }
                registry[key] = r
            }
        }
        let withFiles = usable.filter { !$0.files.isEmpty }
        for other in withFiles.dropFirst() { conflicts.append("files of \(other.id) left out: \(withFiles[0].id) has files") }
        let merged = GameFix(
            id: usable.map(\.id).joined(separator: "+"), name: first.name, appIDs: first.appIDs, exes: first.exes,
            verdict: .fits, backend: usable.compactMap(\.backend).first,
            needsEngine: first.needsEngine, verifiedOn: first.verifiedOn, notNeededFromGPTK: first.notNeededFromGPTK,
            env: env, cpuLimit: usable.compactMap(\.cpuLimit).first, dllOverrides: overrides,
            files: withFiles.first?.files ?? [], registry: registry.values.sorted { ($0.key, $0.name) < ($1.key, $1.name) },
            source: first.source, reason: first.reason)
        return (merged, conflicts)
    }

    /// Compares tags such as "r6", "4.0" or "b2-3" by their numbers.
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        func numbers(_ s: String) -> [Int] {
            s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        }
        let x = numbers(a), y = numbers(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func only(_ dict: [String: Any], _ keys: Set<String>, _ what: String) throws {
        if let extra = Set(dict.keys).subtracting(keys).sorted().first {
            throw Invalid(description: "\(what): unknown field \(extra)")
        }
    }

    private static func matches(_ s: String, _ pattern: String) -> Bool {
        s.range(of: pattern, options: .regularExpression) != nil
    }

    private static func parse(_ e: [String: Any]) throws -> GameFix {
        try only(e, ["id", "name", "match", "verdict", "backend", "needsEngine", "verifiedOn", "notNeededFromGPTK",
                     "env", "cpuLimit", "dllOverrides", "files", "registry", "source", "reason"], "entry")
        guard let id = e["id"] as? String, matches(id, "^[a-z0-9][a-z0-9-]{0,63}$") else {
            throw Invalid(description: "bad entry id")
        }
        func bad(_ why: String) -> Invalid { Invalid(description: "\(id): \(why)") }

        guard let name = e["name"] as? String, !name.isEmpty else { throw bad("no name") }
        guard let match = e["match"] as? [String: Any] else { throw bad("no match") }
        try only(match, ["appIDs", "exes"], id)
        let appIDs = match["appIDs"] as? [Int] ?? []
        let exes = (match["exes"] as? [String] ?? []).map { $0.lowercased() }
        if appIDs.isEmpty && exes.isEmpty { throw bad("match is empty") }
        if appIDs.contains(where: { $0 <= 0 }) { throw bad("bad app id") }
        if exes.contains(where: { !matches($0, "^[a-z0-9_. +'()-]+\\.exe$") }) { throw bad("bad exe name") }

        guard let verdictRaw = e["verdict"] as? String, let verdict = GameFix.Verdict(rawValue: verdictRaw) else {
            throw bad("bad verdict")
        }
        var backend: RendererChoice?
        if let raw = e["backend"] {
            guard let s = raw as? String, let r = RendererChoice(rawValue: s) else { throw bad("bad backend") }
            backend = r
        }
        let needsEngine = e["needsEngine"] as? String
        let verifiedOn = e["verifiedOn"] as? String
        if e["verifiedOn"] != nil && (verifiedOn?.isEmpty ?? true) { throw bad("bad verifiedOn") }
        let notNeeded = e["notNeededFromGPTK"] as? String
        if e["needsEngine"] != nil && needsEngine == nil || e["notNeededFromGPTK"] != nil && notNeeded == nil {
            throw bad("bad version")
        }

        let env = e["env"] as? [String: String] ?? [:]
        if e["env"] != nil && e["env"] as? [String: String] == nil { throw bad("env must hold strings") }
        for (k, v) in env {
            guard matches(k, "^[A-Z][A-Z0-9_]*$"), !forbiddenEnv.contains(k),
                  !forbiddenEnvPrefixes.contains(where: { k.hasPrefix($0) }) else { throw bad("env key \(k) not allowed") }
            guard v.utf8.count <= 256, !v.contains("\n"), !v.contains("\0") else { throw bad("env value of \(k)") }
        }

        var cpuLimit: Int?
        if let raw = e["cpuLimit"] {
            guard let n = raw as? Int, (1...512).contains(n) else { throw bad("bad cpuLimit") }
            cpuLimit = n
        }

        let overrides = e["dllOverrides"] as? [String: String] ?? [:]
        if e["dllOverrides"] != nil && e["dllOverrides"] as? [String: String] == nil { throw bad("dllOverrides must hold strings") }
        for (dll, mode) in overrides {
            guard matches(dll, "^[A-Za-z0-9_.-]+$"), !dll.contains("..") else { throw bad("dll name \(dll)") }
            guard overrideModes.contains(mode) else { throw bad("override mode \(mode)") }
        }

        var files: [GameFix.FileOp] = []
        for item in e["files"] as? [[String: Any]] ?? [] {
            try only(item, ["op", "path", "asset", "sha256", "originalSha256"], id)
            guard let opRaw = item["op"] as? String, let kind = GameFix.FileOp.Kind(rawValue: opRaw),
                  let path = item["path"] as? String, let asset = item["asset"] as? String,
                  let sha = item["sha256"] as? String else { throw bad("bad file item") }
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.hasPrefix("/"), !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
                  matches(path, "^[A-Za-z0-9_. ()+'-]+(/[A-Za-z0-9_. ()+'-]+)*$") else { throw bad("file path \(path)") }
            guard matches(asset, "^[A-Za-z0-9_.-]+$"), matches(sha, "^[0-9a-f]{64}$") else { throw bad("file asset or hash") }
            let original = item["originalSha256"] as? String
            if item["originalSha256"] != nil && !(original.map { matches($0, "^[0-9a-f]{64}$") } ?? false) {
                throw bad("originalSha256")
            }
            if kind == .proxy && !path.lowercased().hasSuffix(".dll") { throw bad("a proxy replaces a DLL") }
            files.append(.init(kind: kind, path: path, asset: asset, sha256: sha, originalSha256: original))
        }
        if files.count > 8 { throw bad("too many files") }

        var registry: [GameFix.RegistryValue] = []
        for item in e["registry"] as? [[String: Any]] ?? [] {
            try only(item, ["key", "name", "type", "value"], id)
            guard let key = item["key"] as? String, let n = item["name"] as? String,
                  let type = item["type"] as? String, let value = item["value"] as? String else { throw bad("bad registry item") }
            guard key.hasPrefix(wineKeyPrefix), !key.contains("..") else { throw bad("registry key outside Software\\Wine") }
            guard type == "REG_SZ" || type == "REG_DWORD" else { throw bad("registry type") }
            if type == "REG_DWORD", UInt32(value) == nil { throw bad("registry dword") }
            guard !n.isEmpty, !n.contains("\0"), !value.contains("\0") else { throw bad("registry text") }
            registry.append(.init(key: key, name: n, type: type, value: value))
        }

        guard let s = e["source"] as? [String: Any] else { throw bad("no source") }
        try only(s, ["kind", "ref", "license"], id)
        guard let kind = s["kind"] as? String, sources.contains(kind) else { throw bad("bad source kind") }
        let ref = s["ref"] as? String ?? "", license = s["license"] as? String ?? ""
        if kind != "lullaby" && (ref.isEmpty || license.isEmpty) { throw bad("foreign source needs ref and license") }

        return GameFix(
            id: id, name: name, appIDs: appIDs, exes: exes, verdict: verdict, backend: backend,
            needsEngine: needsEngine, verifiedOn: verifiedOn, notNeededFromGPTK: notNeeded, env: env, cpuLimit: cpuLimit,
            dllOverrides: overrides, files: files,
            registry: registry, source: .init(kind: kind, ref: ref, license: license),
            reason: e["reason"] as? String ?? "")
    }
}
