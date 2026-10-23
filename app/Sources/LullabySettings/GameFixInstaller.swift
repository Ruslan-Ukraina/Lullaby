// Puts a catalog fix's files into a game's own folder and takes them out again
// (docs/GAME_FIXES.md §6). Nothing the game ships is lost: a proxy DLL renames the game's
// DLL to <name>_real<ext>, and what was done is written to <game>/.lullaby-fix.json so that
// status and restore know it. A file that changed since the install (a game update, the
// player's hand) is never overwritten or removed: the answer is `modified`.

import CryptoKit
import Foundation

public enum GameFixInstaller {
    public enum State: Equatable, Sendable { case notInstalled, installed(fixID: String), modified }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        case gameRunning, notApplicable(String), outsideGameFolder(String), missing(String)
        case assetMismatch(String), originalMismatch(String), occupied(String), modified(String)

        public var description: String {
            switch self {
            case .gameRunning: "the game is running"
            case .notApplicable(let why): "not applicable: \(why)"
            case .outsideGameFolder(let p): "\(p) is outside the game folder"
            case .missing(let p): "\(p) is missing"
            case .assetMismatch(let a): "asset \(a) does not match its hash"
            case .originalMismatch(let p): "the game's \(p) is not the one this fix was made for"
            case .occupied(let p): "\(p) is already there and is not ours"
            case .modified(let p): "\(p) changed since the install"
            }
        }
    }

    struct Record: Codable, Equatable {
        struct Op: Codable, Equatable {
            var kind: String
            var path: String
            var backup: String?
            var originalSha256: String?
            var installedSha256: String
        }
        var fix: String
        var ops: [Op]
    }

    static let stateName = ".lullaby-fix.json"

    static func sha256(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// A path inside `game`, resolving links, or nil.
    static func inside(_ game: URL, _ relative: String) -> URL? {
        let root = game.resolvingSymlinksInPath().standardizedFileURL
        let url = root.appending(path: relative).standardizedFileURL
        let resolved = url.deletingLastPathComponent().resolvingSymlinksInPath().appending(path: url.lastPathComponent)
        return resolved.path.hasPrefix(root.path + "/") ? resolved : nil
    }

    static func backupName(_ path: String) -> String {
        let url = URL(filePath: path)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        let dir = (path as NSString).deletingLastPathComponent
        let name = ext.isEmpty ? "\(stem)_real" : "\(stem)_real.\(ext)"
        return dir.isEmpty ? name : "\(dir)/\(name)"
    }

    static func record(_ game: URL) -> Record? {
        guard let data = try? Data(contentsOf: game.appending(path: stateName)) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    public static func state(game: URL) -> State {
        guard let rec = record(game) else { return .notInstalled }
        for op in rec.ops {
            guard let target = inside(game, op.path), sha256(target) == op.installedSha256 else { return .modified }
            if let backup = op.backup, !FileManager.default.fileExists(atPath: inside(game, backup)?.path ?? "") {
                return .modified
            }
        }
        return .installed(fixID: rec.fix)
    }

    /// `assets` holds the fix's files by asset name. Nothing is changed unless every check passes.
    public static func install(
        _ fix: GameFix, game: URL, assets: URL, isRunning: () -> Bool = { false }
    ) throws {
        guard fix.verdict == .fits, fix.verifiedOn != nil, !fix.files.isEmpty else {
            throw Failure.notApplicable("the fix is not verified or has no files")
        }
        if isRunning() { throw Failure.gameRunning }
        if let existing = record(game) {
            if existing.fix == fix.id, state(game: game) == .installed(fixID: fix.id) { return }
            throw Failure.occupied(stateName)
        }
        let fm = FileManager.default
        // Checks first, so a refusal leaves the folder as it was.
        var plan: [(GameFix.FileOp, URL, URL, URL?)] = []
        for op in fix.files {
            guard let target = inside(game, op.path) else { throw Failure.outsideGameFolder(op.path) }
            let asset = assets.appending(path: op.asset)
            guard sha256(asset) == op.sha256 else { throw Failure.assetMismatch(op.asset) }
            switch op.kind {
            case .proxy:
                guard fm.fileExists(atPath: target.path) else { throw Failure.missing(op.path) }
                if let want = op.originalSha256, sha256(target) != want { throw Failure.originalMismatch(op.path) }
                guard let backup = inside(game, backupName(op.path)) else { throw Failure.outsideGameFolder(op.path) }
                if fm.fileExists(atPath: backup.path) { throw Failure.occupied(backupName(op.path)) }
                plan.append((op, target, asset, backup))
            case .add:
                if fm.fileExists(atPath: target.path) { throw Failure.occupied(op.path) }
                plan.append((op, target, asset, nil))
            }
        }
        var done: [Record.Op] = []
        func undo() {
            for op in done.reversed() {
                guard let target = inside(game, op.path) else { continue }
                try? fm.removeItem(at: target)
                if let backup = op.backup, let from = inside(game, backup) { try? fm.moveItem(at: from, to: target) }
            }
        }
        do {
            for (op, target, asset, backup) in plan {
                let original = op.kind == .proxy ? sha256(target) : nil
                if let backup { try fm.moveItem(at: target, to: backup) }
                done.append(.init(kind: op.kind.rawValue, path: op.path,
                                  backup: backup == nil ? nil : backupName(op.path),
                                  originalSha256: original, installedSha256: op.sha256))
                try fm.copyItem(at: asset, to: target)
            }
            let data = try JSONEncoder().encode(Record(fix: fix.id, ops: done))
            try data.write(to: game.appending(path: stateName), options: .atomic)
        } catch {
            undo()
            throw error
        }
    }

    /// Puts the game's own files back. A file that is not ours any more is left alone.
    public static func restore(game: URL, isRunning: () -> Bool = { false }) throws {
        if isRunning() { throw Failure.gameRunning }
        guard let rec = record(game) else { return }
        let fm = FileManager.default
        for op in rec.ops {
            guard let target = inside(game, op.path), sha256(target) == op.installedSha256 else {
                throw Failure.modified(op.path)
            }
            if let backup = op.backup, !fm.fileExists(atPath: inside(game, backup)?.path ?? "") {
                throw Failure.missing(backup)
            }
        }
        for op in rec.ops.reversed() {
            guard let target = inside(game, op.path) else { continue }
            try fm.removeItem(at: target)
            if let backup = op.backup, let from = inside(game, backup) { try fm.moveItem(at: from, to: target) }
        }
        try? fm.removeItem(at: game.appending(path: stateName))
    }
}
