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

    /// The biggest ordinary window of the application whose name starts with the given one (Steam's windows
    /// belong to "Steam Helper"),  in screen points with a top-left origin.
    static func bounds(ofApplication name: String) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        var best: CGRect?
        for window in list where (window[kCGWindowOwnerName as String] as? String)?.hasPrefix(name) == true
            && window[kCGWindowLayer as String] as? Int == 0 {
            guard let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict), rect.width > 300, rect.height > 200 else { continue }
            if rect.width * rect.height > (best.map { $0.width * $0.height } ?? 0) { best = rect }
        }
        return best
    }


    /// Text only: the alert's icon (always there, 64 points at the top) is hidden and the window is
    /// shortened by the room it took above the title, nothing else moves.
    @MainActor
    static func removeIcon(of window: NSWindow) {
        guard let content = window.contentView else { return }
        func find(_ view: NSView) -> NSView? {
            if view is NSImageView, view.frame.width == 64, view.frame.height == 64 { return view }
            for sub in view.subviews { if let found = find(sub) { return found } }
            return nil
        }
        guard let icon = find(content) else { return }
        icon.isHidden = true
        let others = content.subviews.filter { $0 !== icon }
        guard let top = others.map({ $0.frame.maxY }).max() else { return }
        let shrink = content.bounds.height - (top + 20)
        guard shrink > 0 else { return }
        for sub in content.subviews { sub.autoresizingMask = [] }
        var frame = window.frame
        frame.size.height -= shrink
        window.setFrame(frame, display: false)
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
        alert.layout()
        let window = alert.window
        Notice.removeIcon(of: window)
        // Where the alert goes: the middle of the other application's window, else the screen's middle.
        // The system seats a modal window itself when it starts, so the place is taken again just after.
        let place = { @MainActor in
            if let name = request.centerOn, let target = bounds(ofApplication: name),
               let screen = NSScreen.screens.first {
                var frame = window.frame
                frame.origin.x = target.midX - frame.width / 2
                frame.origin.y = screen.frame.height - target.midY - frame.height / 2
                window.setFrame(frame, display: true)
            } else {
                window.center()
            }
            window.makeKeyAndOrderFront(nil)
        }
        place()
        for delay in [0.05, 0.25] {
            let again = Timer(timeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { place() } }
            RunLoop.main.add(again, forMode: .common)
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
        window.makeKeyAndOrderFront(nil)
        app.runModal(for: window)
        window.orderOut(nil)
        return 0
    }
}
