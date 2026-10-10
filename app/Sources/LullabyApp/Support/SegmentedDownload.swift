// A large download as several HTTP Range requests at once. GitHub's release
// downloads are capped per connection on some routes (measured 2026-10-10: about
// 0.1-0.2 MB/s for one connection, 1.5 MB/s for sixteen, on a 3.8 MB/s line), so
// the engine tarball took half an hour over one (DECISIONS P8-18).
//
// Layout: the bytes before the pieces stay in <part> (an older single-stream
// download, or pieces already put together); each piece is <part>.pieces/<start>-<end>.
// A stopped download continues piece by piece. When every piece is complete they
// are appended to <part> in order, each deleted once it is in, so the piece
// boundaries of a later try are the same. The caller checks size, sha256 and the
// signature of <part> as before.

import Foundation
import Synchronization

/// The server answered a Range request with the whole file.
struct RangeUnsupported: Error {}

struct SegmentedDownload: Sendable {
    /// Bytes `range` of the file, appended to `file`, which already holds the first
    /// bytes of the range when a piece is continued (the range then starts after them).
    /// `progress` gets the size of `file` as it grows.
    typealias FetchRange = @Sendable (
        _ range: ClosedRange<Int64>, _ file: URL, _ progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> Void

    var connections = 12
    /// 4 MB: the last pieces go one per connection, so smaller ones end sooner
    /// (8 MB left a slow last half-minute on a capped route).
    var pieceSize: Int64 = 4 << 20
    /// Tries per piece in one run; HTTP/2 streams to the CDN break now and then.
    var attempts = 3

    struct Piece: Sendable, Equatable {
        let start: Int64
        let end: Int64
        var length: Int64 { end - start + 1 }
        var name: String { "\(start)-\(end)" }
    }

    static func piecesDirectory(for part: URL) -> URL {
        part.deletingLastPathComponent().appending(path: part.lastPathComponent + ".pieces")
    }

    func plan(from base: Int64, total: Int64) -> [Piece] {
        stride(from: base, to: total, by: Int(pieceSize)).map { Piece(start: $0, end: min($0 + pieceSize, total) - 1) }
    }

    func run(
        part: URL, total: Int64, fetch: @escaping FetchRange, progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let fm = FileManager.default
        let base = Self.size(of: part)
        guard base < total else { return }
        let directory = Self.piecesDirectory(for: part)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let pieces = plan(from: base, total: total)
        let names = Set(pieces.map(\.name))
        for name in (try? fm.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
        where !names.contains(name) {
            try? fm.removeItem(at: directory.appending(path: name))
        }

        let sizes = Mutex([String: Int64]())
        for piece in pieces {
            let file = directory.appending(path: piece.name)
            if Self.size(of: file) > piece.length { try? fm.removeItem(at: file) }
            let have = Self.size(of: file)
            sizes.withLock { $0[piece.name] = have }
        }
        let report: @Sendable (String, Int64) -> Void = { name, size in
            let sum = sizes.withLock { all -> Int64 in
                all[name] = size
                return all.values.reduce(0, +)
            }
            progress(base + sum)
        }
        report(pieces[0].name, sizes.withLock { $0[pieces[0].name] ?? 0 })

        let pending = pieces.filter { Self.size(of: directory.appending(path: $0.name)) < $0.length }
        try await withThrowingTaskGroup(of: Void.self) { group in
            var queue = pending[...]
            for _ in 0..<max(connections, 1) {
                guard let piece = queue.popFirst() else { break }
                group.addTask { try await self.fetchPiece(piece, in: directory, fetch: fetch, report: report) }
            }
            while try await group.next() != nil {
                guard let piece = queue.popFirst() else { continue }
                group.addTask { try await self.fetchPiece(piece, in: directory, fetch: fetch, report: report) }
            }
        }

        let handle = try FileHandle(forWritingTo: part.creatingIfMissing())
        defer { try? handle.close() }
        try handle.seekToEnd()
        for piece in pieces {
            let file = directory.appending(path: piece.name)
            guard Self.size(of: file) == piece.length else {
                throw TransportFailure(detail: "A part of the download is incomplete.")
            }
            try handle.write(contentsOf: try Data(contentsOf: file, options: .mappedIfSafe))
            try handle.synchronize()
            try fm.removeItem(at: file)
        }
        try? fm.removeItem(at: directory)
    }

    private func fetchPiece(
        _ piece: Piece, in directory: URL, fetch: FetchRange, report: @escaping @Sendable (String, Int64) -> Void
    ) async throws {
        let file = directory.appending(path: piece.name)
        var lastError: Error?
        for _ in 0..<attempts {
            try Task.checkCancellation()
            let have = Self.size(of: file)
            if have == piece.length { return }
            do {
                try await fetch((piece.start + have)...piece.end, file) { report(piece.name, $0) }
                if Self.size(of: file) == piece.length { return }
                lastError = TransportFailure(detail: "A part of the download stopped early.")
            } catch is RangeUnsupported {
                throw RangeUnsupported()
            } catch {
                if Task.isCancelled { throw error }
                lastError = error
            }
        }
        throw lastError ?? TransportFailure(detail: "A part of the download failed.")
    }

    static func size(of url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.size] as? NSNumber)?
            .int64Value ?? 0
    }
}

private extension URL {
    func creatingIfMissing() -> URL {
        if !FileManager.default.fileExists(atPath: path(percentEncoded: false)) {
            FileManager.default.createFile(atPath: path(percentEncoded: false), contents: nil)
        }
        return self
    }
}
