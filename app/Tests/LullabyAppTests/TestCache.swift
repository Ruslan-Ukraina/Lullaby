import Foundation

// Valve's real packages, downloaded once and kept for the next run, in the package's
// build folder rather than ~/Library/Caches: a test run must not create the app's own
// cache folder on the developer's Mac (the rename to Lullaby found one made this way).
enum TestCache {
    static let valvePackages = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: ".build/test-caches/valve-packages")
}
