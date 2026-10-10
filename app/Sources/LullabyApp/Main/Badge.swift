// The red badge after the first install (ROADMAP §9.4): on ⚙︎ and on the Dock icon,
// until the player opens ⚙︎ once. Then it is gone for good; a later Install does not
// bring it back.

import AppKit
import Foundation

@MainActor
final class BadgeStore {
    static let installedKey = "NotProtonFirstInstallDone"
    static let seenKey = "NotProtonSteamUpdatesTipSeen"

    private let defaults: UserDefaults
    private let dock: (String?) -> Void

    init(
        defaults: UserDefaults = .standard,
        dock: @escaping (String?) -> Void = { NSApp?.dockTile.badgeLabel = $0 }
    ) {
        self.defaults = defaults
        self.dock = dock
    }

    var isShowing: Bool {
        defaults.bool(forKey: Self.installedKey) && !defaults.bool(forKey: Self.seenKey)
    }

    /// After a successful Install.
    func installFinished() {
        guard !defaults.bool(forKey: Self.installedKey) else { return }
        defaults.set(true, forKey: Self.installedKey)
        AppLog.note("badge: first install, badge \(isShowing ? "on" : "off")")
        apply()
    }

    /// When ⚙︎ opens. Returns true the one time the tip should be shown.
    func gearOpened() -> Bool {
        guard isShowing else { return false }
        defaults.set(true, forKey: Self.seenKey)
        AppLog.note("badge: seen, removed")
        apply()
        return true
    }

    func apply() {
        dock(isShowing ? "1" : nil)
    }
}
