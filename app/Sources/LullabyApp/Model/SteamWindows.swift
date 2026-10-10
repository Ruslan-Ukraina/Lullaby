// "Native Steam windows" (docs/BACKLOG.md 15): the switch notproton.dylib reads in
// Steam Helper and steam_osx when Steam starts. The file holds one word: "native"
// turns the macOS frame on; "native-app" also runs Steam Helper as a regular app,
// so Spaces and Stage Manager treat Steam's windows as app windows (experiment,
// DECISIONS W10 option B); "log" only describes Steam's windows in notproton.log;
// anything else (or no file) leaves Steam as shipped. Off by default.

import Foundation

enum SteamWindows {
    static let step = "Native Steam windows"
    static let on = "native"
    static let regularApp = "native-app"
    static let off = "off"

    static var file: URL { SupportPaths.support.appending(path: "steam-windows") }

    static func mode(at url: URL = file) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return off }
        let word = text.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? off
        return [on, regularApp, "log"].contains(word) ? word : off
    }

    static func isOn(at url: URL = file) -> Bool {
        [on, regularApp].contains(mode(at: url))
    }

    static func isRegularApp(at url: URL = file) -> Bool {
        mode(at: url) == regularApp
    }

    /// Steam picks the change up the next time it starts. `regularApp` only counts
    /// with the frame on.
    static func set(_ enabled: Bool, regularApp asApp: Bool = false, at url: URL = file) throws {
        let word = enabled ? (asApp ? regularApp : on) : off
        try atomicReplace(url, with: Data((word + "\n").utf8), step: step)
        AppLog.note("steam windows: \(word) (applies when Steam starts)")
    }
}
