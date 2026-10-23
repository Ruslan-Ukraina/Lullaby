import Foundation
import Testing

@testable import LullabyApp

@Suite("Going on after Lullaby's own update")
struct UpdateContinuationTests {
    private func temporary() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "continuation-\(UUID().uuidString)/update-continues.json")
    }

    @Test("The note is good for one start")
    func oneStart() {
        let url = temporary()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        UpdateContinuation.note(from: "1.1.0-r2", at: url)
        #expect(UpdateContinuation.take(at: url)?.from == "1.1.0-r2")
        #expect(UpdateContinuation.take(at: url) == nil, "the first read removed it")
    }

    @Test("An old note, or one from the future, is not trusted")
    func staleNotes() {
        let url = temporary()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let now = Date()
        UpdateContinuation.note(from: "1.1.0-r2", now: now.addingTimeInterval(-3 * 3600), at: url)
        #expect(UpdateContinuation.take(now: now, at: url) == nil)
        UpdateContinuation.note(from: "1.1.0-r2", now: now.addingTimeInterval(3600), at: url)
        #expect(UpdateContinuation.take(now: now, at: url) == nil)
    }

    @Test("A damaged note is dropped, not a crash")
    func damaged() throws {
        let url = temporary()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        #expect(UpdateContinuation.take(at: url) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test("The new version goes on only when it is another version than the one that left the note")
    func onlyWhenChanged() {
        let marker = UpdateContinuation.Marker(from: "1.1.0-r2", at: Date())
        #expect(UpdateContinuation.shouldContinue(marker, bundled: "1.1.0-r3"))
        #expect(!UpdateContinuation.shouldContinue(marker, bundled: "1.1.0-r2"), "the restart did not happen")
        #expect(!UpdateContinuation.shouldContinue(nil, bundled: "1.1.0-r3"))
    }
}
