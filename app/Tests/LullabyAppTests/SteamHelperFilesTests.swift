import Foundation
import Testing

@testable import LullabyApp

@Suite("Steam Helper name and icon files")
struct SteamHelperFilesTests {

    /// A fake Steam Helper.app and Steam.app in a temporary folder; the real Steam is never touched.
    private struct Fixture {
        let root = URL.temporaryDirectory.appending(path: "np-helperfiles-\(UUID().uuidString)")
        var helper: URL { root.appending(path: "Steam Helper.app") }
        var steamApp: URL { root.appending(path: "Steam.app") }
        var resources: URL { helper.appending(path: "Contents/Resources") }

        init(helper present: Bool = true) throws {
            let fm = FileManager.default
            try fm.createDirectory(at: steamApp.appending(path: "Contents/Resources"), withIntermediateDirectories: true)
            try Data("car".utf8).write(to: steamApp.appending(path: "Contents/Resources/Assets.car"))
            try Data("icns".utf8).write(to: steamApp.appending(path: "Contents/Resources/Steam.icns"))
            guard present else { return }
            try fm.createDirectory(at: resources, withIntermediateDirectories: true)
            try Data("<plist/>".utf8).write(to: helper.appending(path: "Contents/Info.plist"))
            try Data("cfg".utf8).write(to: resources.appending(path: "crash_reporter.cfg"))
        }

        func exists(_ relative: String) -> Bool {
            FileManager.default.fileExists(atPath: helper.appending(path: relative).path(percentEncoded: false))
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

    private final class Calls: @unchecked Sendable {
        var registered: [URL] = []
    }

    @Test("Apply adds the Steam name per language and the icon, lists them, and is idempotent")
    func applyAndAgain() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let calls = Calls()

        let changed = try SteamHelperFiles.apply(
            helper: f.helper, steamApp: f.steamApp, languages: ["en", "uk"],
            register: { calls.registered.append($0) })
        #expect(changed)
        for lang in ["en", "uk"] {
            let file = f.resources.appending(path: "\(lang).lproj/InfoPlist.strings")
            #expect(try String(contentsOf: file, encoding: .utf8) == SteamHelperFiles.strings)
        }
        let list = SteamHelperFiles.added(f.helper)
        #expect(list.contains("Contents/Resources/en.lproj/InfoPlist.strings"))
        #expect(list.contains("Contents/Resources/uk.lproj"))
        #expect(list.contains("icon"))
        #expect(f.exists("Icon\r"))
        #expect(calls.registered == [f.helper])

        let again = try SteamHelperFiles.apply(
            helper: f.helper, steamApp: f.steamApp, languages: ["en", "uk"],
            register: { calls.registered.append($0) })
        #expect(again == false)
        #expect(calls.registered.count == 1)
    }

    @Test("Remove takes away only what apply added and keeps Steam's own files")
    func removeOnlyOurs() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        // Valve's own localisation in a language folder that also holds other files.
        let valveDir = f.resources.appending(path: "en.lproj")
        try FileManager.default.createDirectory(at: valveDir, withIntermediateDirectories: true)
        try Data("valve".utf8).write(to: valveDir.appending(path: "InfoPlist.strings"))
        let deDir = f.resources.appending(path: "de.lproj")
        try FileManager.default.createDirectory(at: deDir, withIntermediateDirectories: true)
        try Data("other".utf8).write(to: deDir.appending(path: "Localizable.strings"))

        try SteamHelperFiles.apply(helper: f.helper, steamApp: f.steamApp,
                                   languages: ["en", "de", "uk"], register: { _ in })
        #expect(try String(contentsOf: valveDir.appending(path: "InfoPlist.strings"), encoding: .utf8) == "valve")
        #expect(f.exists("Contents/Resources/de.lproj/InfoPlist.strings"))

        let removed = SteamHelperFiles.remove(helper: f.helper, steamApp: f.steamApp, register: { _ in })
        #expect(removed)
        #expect(try String(contentsOf: valveDir.appending(path: "InfoPlist.strings"), encoding: .utf8) == "valve")
        #expect(f.exists("Contents/Resources/de.lproj/Localizable.strings"))
        #expect(!f.exists("Contents/Resources/de.lproj/InfoPlist.strings"))
        #expect(!f.exists("Contents/Resources/uk.lproj"))
        #expect(!f.exists("Icon\r"))
        #expect(!f.exists("Contents/Resources/\(SteamHelperFiles.markerName)"))
        #expect(f.exists("Contents/Resources/crash_reporter.cfg"))
        #expect(f.exists("Contents/Info.plist"))

        #expect(SteamHelperFiles.remove(helper: f.helper, steamApp: f.steamApp, register: { _ in }) == false)
    }

    @Test("Copies of Steam.app's icon files go only when byte-identical")
    func leftovers() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        try Data("car".utf8).write(to: f.resources.appending(path: "Assets.car"))
        try Data("something else".utf8).write(to: f.resources.appending(path: "Steam.icns"))

        #expect(SteamHelperFiles.remove(helper: f.helper, steamApp: f.steamApp, register: { _ in }))
        #expect(!f.exists("Contents/Resources/Assets.car"))
        #expect(f.exists("Contents/Resources/Steam.icns"))
    }

    @Test("A marker naming paths outside Resources removes nothing there")
    func unsafeMarker() throws {
        let f = try Fixture()
        defer { f.cleanUp() }
        let list = ["Contents/Info.plist", "Contents/Resources/../Info.plist", "/etc/hosts"]
        try JSONEncoder().encode(list).write(
            to: f.resources.appending(path: SteamHelperFiles.markerName))

        SteamHelperFiles.remove(helper: f.helper, steamApp: f.steamApp, register: { _ in })
        #expect(f.exists("Contents/Info.plist"))
        #expect(!f.exists("Contents/Resources/\(SteamHelperFiles.markerName)"))
    }

    @Test("Without Steam Helper.app nothing is written")
    func noHelper() throws {
        let f = try Fixture(helper: false)
        defer { f.cleanUp() }
        #expect(try SteamHelperFiles.apply(helper: f.helper, steamApp: f.steamApp,
                                           languages: ["en"], register: { _ in }) == false)
        #expect(!FileManager.default.fileExists(atPath: f.helper.path(percentEncoded: false)))
        #expect(SteamHelperFiles.remove(helper: f.helper, steamApp: f.steamApp, register: { _ in }) == false)
    }
}
