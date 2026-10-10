// Steam's windows belong to Steam Helper.app, whose Info.plist says "Steam Helper"
// and has no icon: that is what the Dock tooltip and Stage Manager show. Info.plist
// itself cannot be changed (Steam checks it at every start and reinstalls its package
// when it differs, DECISIONS W15), but Steam does not check files it does not ship.
// With native Steam windows on (and your go-ahead, 2026-10-07), NotProton adds:
//   Resources/<lang>.lproj/InfoPlist.strings  CFBundleName/CFBundleDisplayName "Steam"
//   a custom bundle icon                        Steam.app's icon, as Finder sets one
// Everything added is listed in Resources/.lullaby-added, and only that (plus the
// copies of Steam.app's Assets.car and Steam.icns an earlier attempt left) is
// removed by Repair, Remove Everything and switching native windows off.

import AppKit
import Foundation

enum SteamHelperFiles {
    static let step = "Steam Helper name and icon"
    static let markerName = ".lullaby-added"
    static let strings = "\"CFBundleName\" = \"Steam\";\n\"CFBundleDisplayName\" = \"Steam\";\n"

    static var helper: URL {
        SupportPaths.Steam.innerApp.appending(path: "Contents/Frameworks/Steam Helper.app")
    }

    /// en, uk, ru, Base and the Mac's preferred languages.
    static var languages: [String] {
        var out = ["Base", "en", "uk", "ru"]
        for lang in Locale.preferredLanguages {
            let code = String(lang.prefix { $0 != "-" && $0 != "_" })
            if !code.isEmpty, !out.contains(code) { out.append(code) }
        }
        return out
    }

    private static func marker(_ helper: URL) -> URL {
        helper.appending(path: "Contents/Resources/\(markerName)")
    }

    static func added(_ helper: URL = helper) -> [String] {
        guard let data = try? Data(contentsOf: marker(helper)) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    static func isApplied(_ helper: URL = helper) -> Bool { !added(helper).isEmpty }

    static func exists(_ helper: URL = helper) -> Bool {
        FileManager.default.fileExists(atPath: helper.appending(path: "Contents/Info.plist").path(percentEncoded: false))
    }

    static func steamIcon(_ steamApp: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: steamApp.path(percentEncoded: false))
        icon.size = NSSize(width: 1024, height: 1024)
        return icon
    }

    typealias Registrar = (URL) -> Void

    /// Adds the files; true when something was added.
    @discardableResult
    static func apply(helper: URL = helper, steamApp: URL = SupportPaths.Steam.app,
                      languages: [String] = languages,
                      register: Registrar = { SteamBundle.register($0) }) throws -> Bool {
        let fm = FileManager.default
        guard exists(helper) else { return false }
        let leftovers = removeLeftovers(helper: helper, steamApp: steamApp)
        var list = added(helper)
        let resources = helper.appending(path: "Contents/Resources")
        for lang in languages {
            let dir = resources.appending(path: "\(lang).lproj")
            let file = dir.appending(path: "InfoPlist.strings")
            let relFile = "Contents/Resources/\(lang).lproj/InfoPlist.strings"
            if list.contains(relFile) { continue }
            if fm.fileExists(atPath: file.path(percentEncoded: false)) { continue }  // Valve's own: left alone
            let dirExisted = fm.fileExists(atPath: dir.path(percentEncoded: false))
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(strings.utf8).write(to: file, options: .atomic)
            if !dirExisted { list.append("Contents/Resources/\(lang).lproj") }
            list.append(relFile)
        }
        if !list.contains("icon") {
            if NSWorkspace.shared.setIcon(steamIcon(steamApp), forFile: helper.path(percentEncoded: false)) {
                list.append("icon")
            } else {
                AppLog.note("steam helper: custom icon not set")
            }
        }
        let changed = list != added(helper)
        if changed {
            try JSONEncoder().encode(list).write(to: marker(helper), options: .atomic)
            AppLog.note("steam helper: Steam's name and icon added (\(list.count) entries)")
        }
        if changed || leftovers { register(helper) }
        return changed
    }

    /// Removes what apply added; true when something was removed.
    @discardableResult
    static func remove(helper: URL = helper, steamApp: URL = SupportPaths.Steam.app,
                       register: Registrar = { SteamBundle.register($0) }) -> Bool {
        let fm = FileManager.default
        guard exists(helper) else { return false }
        var removed = removeLeftovers(helper: helper, steamApp: steamApp)
        let list = added(helper)
        // Files before their directories.
        for entry in list.sorted(by: { $0.count > $1.count }) where entry != "icon" {
            guard EngineSupport.isSafeRelative(entry), entry.hasPrefix("Contents/Resources/") else { continue }
            if (try? fm.removeItem(at: helper.appending(path: entry))) != nil { removed = true }
        }
        if list.contains("icon") {
            NSWorkspace.shared.setIcon(nil, forFile: helper.path(percentEncoded: false))
            removed = true
        }
        try? fm.removeItem(at: marker(helper))
        if removed {
            register(helper)
            AppLog.note("steam helper: NotProton's name and icon files removed")
        }
        return removed
    }

    /// Copies of Steam.app's icon files an earlier attempt put in Resources. Steam ships
    /// neither in Steam Helper, so only byte-identical copies are removed.
    private static func removeLeftovers(helper: URL, steamApp: URL) -> Bool {
        var removed = false
        for file in ["Assets.car", "Steam.icns"] {
            let copy = helper.appending(path: "Contents/Resources/\(file)")
            let original = steamApp.appending(path: "Contents/Resources/\(file)")
            if let a = Digest.sha256IfPresent(copy), a == Digest.sha256IfPresent(original),
               (try? FileManager.default.removeItem(at: copy)) != nil {
                AppLog.note("steam helper: removed the copy of \(file)")
                removed = true
            }
        }
        return removed
    }

    /// In line with the native windows switch. Never throws: a failure is logged.
    @discardableResult
    static func sync(wanted: Bool = SteamWindows.isOn()) -> String {
        do {
            if wanted {
                return try apply() ? "added" : "unchanged"
            }
            return remove() ? "removed" : "unchanged"
        } catch {
            AppLog.note("steam helper: \(error.localizedDescription)")
            return "failed"
        }
    }
}
