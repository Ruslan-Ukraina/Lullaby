// The Update button does everything in one go, but Lullaby's own update ends with a restart, and the patch
// Steam gets belongs to the version that comes up. So the old app does not put its own patch into Steam (it
// would be stale the moment it is installed, and the window would ask for a second press); it leaves this
// note, and the new version, finding it, goes on with the patch by itself. A note from a flow whose restart
// never happened (the version is the same) is dropped, and so is one that is old.

import Foundation

enum UpdateContinuation {
    struct Marker: Codable, Equatable {
        let from: String
        let at: Date
    }

    static var url: URL { SupportPaths.support.appending(path: "update-continues.json") }

    /// Left by the step that downloaded the new version, which is waiting for its restart.
    static func note(from version: String, now: Date = Date(), at url: URL = url) {
        let marker = Marker(from: version, at: now)
        guard let data = try? JSONEncoder().encode(marker) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Reads the note and removes it: it is good for one start.
    static func take(now: Date = Date(), maxAge: TimeInterval = 2 * 3600, at url: URL = url) -> Marker? {
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url), let marker = try? JSONDecoder().decode(Marker.self, from: data),
              now.timeIntervalSince(marker.at) <= maxAge, marker.at <= now.addingTimeInterval(60)
        else { return nil }
        return marker
    }

    /// The new version goes on only when it really is another one.
    static func shouldContinue(_ marker: Marker?, bundled: String) -> Bool {
        guard let marker else { return false }
        return marker.from != bundled
    }
}
