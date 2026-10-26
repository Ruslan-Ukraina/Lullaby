// The window of `lullaby-settings notice`: a system alert (the same NSAlert the app shows), centred
// on the window of another application (Steam) when it has one on screen. It needs no permission:
// CGWindowListCopyWindowInfo gives the owner's name and bounds without Screen Recording.

import AppKit
import LullabySettings

/// What the OK button does: ends the modal session of the alert's window.
final class NoticeButton: NSObject {
    @objc func pressed(_ sender: Any?) { NSApp.stopModal() }
}

enum Notice {
    @MainActor static let button = NoticeButton()

    static func language() -> Language {
        Language(locale: Locale.preferredLanguages.first ?? "en")
    }

    /// The biggest ordinary window of the named application, in screen points with a top-left origin.
    static func bounds(ofApplication name: String) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        var best: CGRect?
        for window in list where window[kCGWindowOwnerName as String] as? String == name
            && window[kCGWindowLayer as String] as? Int == 0 {
            guard let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict), rect.width > 300, rect.height > 200 else { continue }
            if rect.width * rect.height > (best.map { $0.width * $0.height } ?? 0) { best = rect }
        }
        return best
    }

    @MainActor
    static func run(_ arguments: [String]) -> Int32 {
        let request: NoticeRequest
        do {
            request = try NoticeRequest.parse(arguments, language: language())
        } catch {
            FileHandle.standardError.write(Data("lullaby-settings: \(error)\n".utf8))
            return 2
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let alert = NSAlert()
        alert.messageText = request.title
        alert.informativeText = request.message
        let ok = alert.addButton(withTitle: "OK")
        ok.target = button
        ok.action = #selector(NoticeButton.pressed(_:))
        // Lullaby's own icon, as in the app's alerts; the command line tool has none of its own.
        for path in ["/Applications/Lullaby.app", NSHomeDirectory() + "/Applications/Lullaby.app"]
        where FileManager.default.fileExists(atPath: path) {
            alert.icon = NSWorkspace.shared.icon(forFile: path)
            break
        }
        alert.layout()
        let window = alert.window
        if let name = request.centerOn, let target = bounds(ofApplication: name),
           let screen = NSScreen.screens.first {
            var frame = window.frame
            frame.origin.x = target.midX - frame.width / 2
            frame.origin.y = screen.frame.height - target.midY - frame.height / 2
            window.setFrame(frame, display: false)
        } else {
            window.center()
        }
        // The alert ends itself after the timeout, so a notice nobody answers does not stay for ever.
        // The timer runs in the common modes: a modal session does not run the default one.
        let timer = Timer(timeInterval: TimeInterval(request.timeout), repeats: false) { _ in app.stopModal() }
        RunLoop.main.add(timer, forMode: .common)
        // LULLABY_NOTICE_SELFTEST=1: press OK by itself after a second (the test of the button).
        if ProcessInfo.processInfo.environment["LULLABY_NOTICE_SELFTEST"] == "1" {
            let press = Timer(timeInterval: 1, repeats: false) { _ in ok.performClick(nil) }
            RunLoop.main.add(press, forMode: .common)
        }
        app.activate(ignoringOtherApps: true)
        app.runModal(for: window)
        window.orderOut(nil)
        return 0
    }
}
