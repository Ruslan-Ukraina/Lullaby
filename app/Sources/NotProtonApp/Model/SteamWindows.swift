// "Native Steam windows" (docs/BACKLOG.md 15): the switch notproton.dylib reads in
// Steam Helper when Steam starts. The file holds one word: "native" turns the
// macOS frame on, "log" only describes Steam's windows in notproton.log, anything
// else (or no file) leaves Steam as shipped. Off by default.

import Foundation

enum SteamWindows {
    static let step = "Native Steam windows"
    static let on = "native"
    static let off = "off"

    static var file: URL { SupportPaths.support.appending(path: "steam-windows") }

    static func mode(at url: URL = file) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return off }
        let word = text.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? off
        return [on, "log"].contains(word) ? word : off
    }

    static func isOn(at url: URL = file) -> Bool {
        mode(at: url) == on
    }

    /// Steam picks the change up the next time it starts.
    static func set(_ enabled: Bool, at url: URL = file) throws {
        try atomicReplace(url, with: Data(((enabled ? on : off) + "\n").utf8), step: step)
        AppLog.note("steam windows: \(enabled ? on : off) (applies when Steam starts)")
    }
}
