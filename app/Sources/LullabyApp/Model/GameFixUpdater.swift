// The catalog of game fixes (docs/GAME_FIXES.md): game-fixes.json in the signed release feed,
// refreshed the way the bridge and signature manifests are. The bytes are used only after the
// signature checked out, the serial did not go down (ReleaseFeed.fetch), and the app's own
// validator accepted every entry; one bad entry refuses the file and the catalog the player
// has stays. The settings read lullaby/settings/game-fixes.json, which only this writes.

import Foundation
import LullabySettings

enum GameFixUpdater {
    static let manifestName = "game-fixes.json"

    enum Outcome: Equatable, Sendable {
        case updated(serial: Int, entries: Int)
        case unchanged(serial: Int)
    }

    /// `cache` is the folder of verified feed copies (lullaby/manifests); `settings` is
    /// lullaby/settings, where the settings service reads the catalog from.
    static func refresh(
        feed: ReleaseFeed, transport: any EngineTransport, cache: URL, settings: URL
    ) async throws -> Outcome {
        let document = try await SignedDocument.fetch(
            feed.gameFixesURL, feed: feed, transport: transport, cache: cache, schema: 1)
        let catalog: GameFixCatalog
        do {
            catalog = try GameFixCatalog.decode(document.data)
        } catch {
            AppLog.note("game fixes: serial \(document.serial) is signed but refused: \(error)")
            throw StepFailure(
                step: ReleaseFeed.step,
                detail: "The game fixes catalog is signed but not usable (\(error)), so Lullaby kept the one it has.")
        }
        let target = settings.appending(path: manifestName)
        if let current = try? Data(contentsOf: target), current == document.data {
            return .unchanged(serial: catalog.serial)
        }
        try FileManager.default.createDirectory(at: settings, withIntermediateDirectories: true)
        try atomicReplace(target, with: document.data, step: ReleaseFeed.step)
        AppLog.note("game fixes: serial \(catalog.serial), \(catalog.entries.count) entries")
        return .updated(serial: catalog.serial, entries: catalog.entries.count)
    }
}

extension GameFixUpdater {
    /// With the app's configured feed. No feed (a build without the release key) or a feed
    /// that has no catalog yet is not a problem for the player: the built-in recipes stay,
    /// and the reason goes to the log only.
    static func refreshConfigured(
        transport base: any EngineTransport = URLSessionEngineTransport(),
        cache: URL = SupportPaths.manifests,
        settings: URL = SettingsPaths.support.appending(path: "settings")
    ) async {
        guard case .ready(let feed) = ReleaseFeed.configured else { return }
        do {
            let outcome = try await refresh(feed: feed, transport: feed.transport(over: base), cache: cache, settings: settings)
            if case .updated(let serial, let entries) = outcome {
                AppLog.note("updates: game fixes serial \(serial), \(entries) entries")
            }
        } catch {
            AppLog.note("updates: game fixes not refreshed: \(error.localizedDescription)")
        }
    }
}
