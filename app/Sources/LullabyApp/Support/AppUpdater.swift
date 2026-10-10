import AppKit
import Sparkle

// Updates of Lullaby.app itself, through Sparkle (Phase 6, docs/RELEASING.md).
//
// The feed and the EdDSA key come from Info.plist (SUFeedURL, SUPublicEDKey), which
// `make app SPARKLE_FEED=… SPARKLE_KEY=…` fills; the release workflow passes the
// owner's. Without both, or with a TEST key in a release build, the updater is never
// started and "Check for Updates…" stays off: upstream's feed would offer upstream's
// CrossOver build (DECISIONS B4), and a TEST key signs anything anyone wants.
//
// Pre-release versions (tags like v1.1.0-pre.1) are published on Sparkle's "beta"
// channel and offered only after "Pre-release versions" in Status is turned on.
//
// A private release repository (release/feed.json "access": "private", ROADMAP §3):
// Sparkle sends the Keychain token through SPUUpdater.httpHeaders with
// Accept: application/octet-stream, and the appcast's address is resolved through
// GitHub's API before every check, since each release uploads it anew. The
// appcast's enclosures are API asset addresses (release.yml writes them so).
@MainActor
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    static let shared = AppUpdater()

    nonisolated static let feedKey = "SUFeedURL"
    nonisolated static let keyKey = "SUPublicEDKey"
    nonisolated static let prereleaseDefault = "LullabyPrereleaseUpdates"
    nonisolated static let prereleaseChannel = "beta"

    enum Setup: Equatable, Sendable {
        case ready
        /// Why the updater is off, in words for Status.
        case off(String)
    }

    private(set) var setup: Setup
    private var controller: SPUStandardUpdaterController?
    /// Private mode: the feed's transport and the appcast's API address once resolved.
    private var privateFeed: GitHubAssetTransport?
    private var resolvedAppcast: URL?

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
            return .off("This build of Lullaby has no update feed, so it does not update itself.")
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
        setup = .off("")
        super.init()
        start()
    }

    /// Reads the configuration again (a token added or removed) and starts Sparkle if it can.
    func start() {
        let info = Bundle.main.infoDictionary ?? [:]
        let feedText = info[Self.feedKey] as? String
        setup = Self.setup(feed: feedText, key: info[Self.keyKey] as? String, kind: .current)
        privateFeed = nil
        if case .ready = setup, (info[ReleaseAccess.infoKey] as? String) == "private" {
            let repository = info[ReleaseAccess.repositoryKey] as? String ?? ""
            if let token = ReleaseToken.read(repository: repository),
               let base = (info[ReleaseFeed.urlKey] as? String).flatMap(URL.init(string:)) {
                privateFeed = GitHubAssetTransport(base: base, repository: repository, token: token)
            } else {
                setup = .off(ReleaseAccess.needsToken)
            }
        }
        if case .off(let reason) = setup {
            // A token removed in ⚙︎ must not stay in Sparkle's headers.
            controller?.updater.httpHeaders = nil
            AppLog.note("app updates: off, \(reason)")
            return
        }
        if controller == nil {
            controller = SPUStandardUpdaterController(
                startingUpdater: privateFeed == nil, updaterDelegate: self, userDriverDelegate: nil)
            // No background checks (ROADMAP §9.5): the window looks when it opens.
            controller?.updater.automaticallyChecksForUpdates = false
            controller?.updater.automaticallyDownloadsUpdates = false
        }
        if let privateFeed {
            controller?.updater.httpHeaders = [
                "Authorization": "Bearer \(privateFeed.token)",
                "Accept": "application/octet-stream",
                "X-GitHub-Api-Version": "2022-11-28",
            ]
            Task { await resolveAppcast(then: { [weak self] in
                guard let self, let controller = self.controller else { return }
                if !controller.updater.sessionInProgress { controller.startUpdater() }
            }) }
        }
        AppLog.note("app updates: on, \(version), \(privateFeed == nil ? "public" : "private") releases, "
            + "pre-releases \(Self.prereleases ? "on" : "off")")
    }

    /// Private mode: the appcast's current API address, from its public-style one.
    private func resolveAppcast(then done: @escaping @MainActor () -> Void) async {
        guard let privateFeed,
              let text = Bundle.main.object(forInfoDictionaryKey: Self.feedKey) as? String,
              let url = URL(string: text), let (tag, file) = privateFeed.asset(of: url)
        else { return }
        do {
            resolvedAppcast = try await privateFeed.assetURL(tag: tag, file: file)
            done()
        } catch {
            AppLog.note("app updates: the private appcast cannot be reached: \(error.localizedDescription)")
        }
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
        if privateFeed != nil {
            Task { await resolveAppcast(then: { [weak self] in
                guard let controller = self?.controller else { return }
                if !controller.updater.canCheckForUpdates { controller.startUpdater() }
                controller.checkForUpdates(nil)
            }) }
            return
        }
        controller.checkForUpdates(nil)
    }

    var isPrivate: Bool {
        (Bundle.main.object(forInfoDictionaryKey: ReleaseAccess.infoKey) as? String) == "private"
    }

    var repository: String {
        Bundle.main.object(forInfoDictionaryKey: ReleaseAccess.repositoryKey) as? String ?? ""
    }

    private var probeWaiter: CheckedContinuation<String?, Never>?

    /// The newer version Sparkle finds, without showing anything (the window's Update).
    /// nil when there is none, when updates are off, or when the check does not answer.
    func probe(timeout: Duration = .seconds(20)) async -> String? {
        guard let controller, isAvailable, probeWaiter == nil else { return nil }
        if privateFeed != nil {
            await resolveAppcast(then: {})
            guard resolvedAppcast != nil else { return nil }
            if !controller.updater.canCheckForUpdates { controller.startUpdater() }
        }
        return await withCheckedContinuation { waiter in
            probeWaiter = waiter
            controller.updater.checkForUpdateInformation()
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.answerProbe(nil, why: "no answer in time")
            }
        }
    }

    private func answerProbe(_ version: String?, why: String) {
        guard let waiter = probeWaiter else { return }
        probeWaiter = nil
        AppLog.note("app updates: probe, \(version ?? why)")
        waiter.resume(returning: version)
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        resolvedAppcast?.absoluteString
    }

    var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UserDefaults.standard.bool(forKey: Self.prereleaseDefault) ? [Self.prereleaseChannel] : []
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        answerProbe(item.displayVersionString, why: "")
        AppLog.note("app updates: found \(item.displayVersionString) (\(item.versionString))\(item.channel.map { ", channel \($0)" } ?? "")")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        answerProbe(nil, why: "no newer version")
        AppLog.note("app updates: no newer version")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        answerProbe(nil, why: "stopped")
        AppLog.note("app updates: stopped, \(error.localizedDescription)")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        AppLog.note("app updates: installing \(item.displayVersionString) (\(item.versionString))")
        AppLog.flush()
    }
}
