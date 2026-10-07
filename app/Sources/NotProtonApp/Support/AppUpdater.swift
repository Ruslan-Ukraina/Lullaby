import AppKit
import Sparkle

// Updates of NotProton.app itself, through Sparkle (Phase 6, docs/RELEASING.md).
//
// The feed and the EdDSA key come from Info.plist (SUFeedURL, SUPublicEDKey), which
// `make app SPARKLE_FEED=… SPARKLE_KEY=…` fills; the release workflow passes the
// owner's. Without both, or with a TEST key in a release build, the updater is never
// started and "Check for Updates…" stays off: upstream's feed would offer upstream's
// CrossOver build (DECISIONS B4), and a TEST key signs anything anyone wants.
//
// Pre-release versions (tags like v1.1.0-pre.1) are published on Sparkle's "beta"
// channel and offered only after "Pre-release versions" in Status is turned on.
@MainActor
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()

    nonisolated static let feedKey = "SUFeedURL"
    nonisolated static let keyKey = "SUPublicEDKey"
    nonisolated static let prereleaseDefault = "NotProtonPrereleaseUpdates"
    nonisolated static let prereleaseChannel = "beta"

    enum Setup: Equatable, Sendable {
        case ready
        /// Why the updater is off, in words for Status.
        case off(String)
    }

    let setup: Setup
    private var controller: SPUStandardUpdaterController?

    var isAvailable: Bool { setup == .ready }

    var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return short == build ? short : "\(short) (\(build))"
    }

    nonisolated static func setup(feed: String?, key: String?, kind: BuildKind) -> Setup {
        let keyText = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let feedText = (feed ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyText.isEmpty, !feedText.isEmpty else {
            return .off("This build of NotProton has no update feed, so it does not update itself.")
        }
        guard let raw = Data(base64Encoded: keyText), raw.count == 32 else {
            return .off("The update key in this build is not a valid EdDSA public key.")
        }
        if kind == .release, TestKeys.isTestKey(keyText) {
            return .off(TestKeys.refused)
        }
        guard let url = URL(string: feedText), url.scheme?.lowercased() == "https"
                || (kind != .release && ["http", "file"].contains(url.scheme?.lowercased() ?? ""))
        else { return .off("The update feed address in this build is not usable.") }
        return .ready
    }

    override init() {
        let info = Bundle.main.infoDictionary ?? [:]
        setup = Self.setup(
            feed: info[Self.feedKey] as? String, key: info[Self.keyKey] as? String, kind: .current)
        super.init()
        if case .off(let reason) = setup {
            AppLog.note("app updates: off, \(reason)")
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        AppLog.note("app updates: on, \(version), pre-releases \(Self.prereleases ? "on" : "off")")
    }

    static var prereleases: Bool {
        UserDefaults.standard.bool(forKey: prereleaseDefault)
    }

    func setPrereleases(_ wanted: Bool) {
        UserDefaults.standard.set(wanted, forKey: Self.prereleaseDefault)
        AppLog.note("app updates: pre-releases \(wanted ? "on" : "off")")
        controller?.updater.resetUpdateCycleAfterShortDelay()
    }

    func check() {
        guard let controller else { return }
        AppLog.note("app updates: check requested")
        controller.checkForUpdates(nil)
    }

    var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UserDefaults.standard.bool(forKey: Self.prereleaseDefault) ? [Self.prereleaseChannel] : []
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        AppLog.note("app updates: found \(item.displayVersionString) (\(item.versionString))\(item.channel.map { ", channel \($0)" } ?? "")")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        AppLog.note("app updates: no newer version")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        AppLog.note("app updates: stopped, \(error.localizedDescription)")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        AppLog.note("app updates: installing \(item.displayVersionString) (\(item.versionString))")
        AppLog.flush()
    }
}
