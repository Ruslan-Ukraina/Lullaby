import Foundation
import Synchronization
import Testing
@testable import LullabyApp

/// A fake server for SegmentedDownload: serves `body` by range, and can break.
private final class RangeServer: Sendable {
    let body: Data
    /// Piece starts whose first request stops halfway.
    let cutOnce: Mutex<Set<Int64>>
    let requests = Mutex<[ClosedRange<Int64>]>([])
    let inFlight = Mutex(0)
    let peak = Mutex(0)
    let ignoresRanges: Bool

    init(size: Int, cutOnce: Set<Int64> = [], ignoresRanges: Bool = false) {
        body = Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ $0 >> 8) })
        self.cutOnce = Mutex(cutOnce)
        self.ignoresRanges = ignoresRanges
    }

    var fetch: SegmentedDownload.FetchRange {
        { [self] range, file, progress in
            requests.withLock { $0.append(range) }
            let now = inFlight.withLock { $0 += 1; return $0 }
            peak.withLock { $0 = max($0, now) }
            defer { inFlight.withLock { $0 -= 1 } }
            if ignoresRanges { throw RangeUnsupported() }
            try await Task.sleep(for: .milliseconds(2))
            var slice = body[Int(range.lowerBound)...Int(range.upperBound)]
            let cut = cutOnce.withLock { $0.remove(range.lowerBound) != nil }
            if cut { slice = slice.prefix(slice.count / 2) }
            if !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
            }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: slice)
            progress(SegmentedDownload.size(of: file))
            if cut { throw URLError(.networkConnectionLost) }
        }
    }
}

@Suite("Segmented download")
struct SegmentedDownloadTests {
    let dir = URL.temporaryDirectory.appending(path: "np-seg-\(UUID().uuidString)")

    func part() throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "engine.tar.xz.part")
    }

    @Test("Pieces arrive in parallel and are put together in order; the piece folder goes")
    func assembles() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let server = RangeServer(size: 100_003)
        let part = try part()
        let last = Mutex<Int64>(0)
        try await SegmentedDownload(connections: 4, pieceSize: 10_000)
            .run(part: part, total: 100_003, fetch: server.fetch) { size in last.withLock { $0 = max($0, size) } }
        #expect(try Data(contentsOf: part) == server.body)
        #expect(server.requests.withLock { $0.count } == 11)
        #expect(server.peak.withLock { $0 } > 1)
        #expect(server.peak.withLock { $0 } <= 4)
        #expect(last.withLock { $0 } == 100_003)
        #expect(!FileManager.default.fileExists(atPath: SegmentedDownload.piecesDirectory(for: part).path(percentEncoded: false)))
    }

    @Test("A broken piece is asked again from where it stopped")
    func retriesPiece() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let server = RangeServer(size: 50_000, cutOnce: [20_000])
        let part = try part()
        try await SegmentedDownload(connections: 3, pieceSize: 10_000).run(part: part, total: 50_000, fetch: server.fetch) { _ in }
        #expect(try Data(contentsOf: part) == server.body)
        #expect(server.requests.withLock { $0 }.contains(25_000...29_999))
    }

    @Test("A stopped download continues: the older single-stream part and finished pieces are kept")
    func resumes() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        // Pieces count from the 5000 bytes already there: 5000, 15000, 25000, …
        let server = RangeServer(size: 60_000, cutOnce: [15_000])
        let part = try part()
        try server.body.prefix(5_000).write(to: part)
        let download = SegmentedDownload(connections: 1, pieceSize: 10_000, attempts: 1)
        await #expect(throws: (any Error).self) {
            try await download.run(part: part, total: 60_000, fetch: server.fetch) { _ in }
        }
        #expect(SegmentedDownload.size(of: part) == 5_000)
        let before = server.requests.withLock { $0.count }
        try await download.run(part: part, total: 60_000, fetch: server.fetch) { _ in }
        #expect(try Data(contentsOf: part) == server.body)
        let again = server.requests.withLock { Array($0[before...]) }
        // The finished first piece is not asked again; the cut one continues halfway.
        #expect(!again.contains(5_000...14_999))
        #expect(again.first == 20_000...24_999)
        #expect(again.count == 5)  // 20000…24999, then 25000, 35000, 45000, 55000
    }

    @Test("A server that ignores ranges says so, so the caller falls back to one stream")
    func rangesIgnored() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let server = RangeServer(size: 30_000, ignoresRanges: true)
        let part = try part()
        await #expect(throws: RangeUnsupported.self) {
            try await SegmentedDownload(connections: 2, pieceSize: 10_000).run(part: part, total: 30_000, fetch: server.fetch) { _ in }
        }
    }

    @Test("A complete part needs nothing")
    func complete() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let server = RangeServer(size: 20_000)
        let part = try part()
        try server.body.write(to: part)
        try await SegmentedDownload(pieceSize: 10_000).run(part: part, total: 20_000, fetch: server.fetch) { _ in }
        #expect(server.requests.withLock { $0.isEmpty })
    }
}
