import Sparkle

@MainActor
final class AppUpdater {

    private let controller: SPUStandardUpdaterController

    // Off in this fork until it publishes a feed of its own (Phase 6,
    // docs/DECISIONS.md B4). The feed upstream named would offer upstream's
    // CrossOver build as an update to this one, so the updater is never started,
    // never checks on request, and Info.plist carries no feed or key.
    let isAvailable = false

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func check() {
        guard isAvailable else { return }
        controller.checkForUpdates(nil)
    }
}
