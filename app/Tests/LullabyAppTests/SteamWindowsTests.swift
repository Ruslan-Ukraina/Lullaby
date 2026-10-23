import Foundation
import Testing

@testable import LullabyApp

@Suite("Native Steam windows switch")
struct SteamWindowsTests {

    private func file() -> URL {
        URL.temporaryDirectory.appending(path: "np-steamwin-\(UUID().uuidString)/steam-windows")
    }

    @Test("No file means off: Steam stays as shipped")
    func defaultOff() {
        let url = file()
        #expect(SteamWindows.isOn(at: url) == false)
        #expect(SteamWindows.mode(at: url) == "off")
    }

    @Test("On writes the word the dylib reads; off writes off")
    func roundTrip() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try SteamWindows.set(true, at: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "native\n")
        #expect(SteamWindows.isOn(at: url))

        try SteamWindows.set(false, at: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "off\n")
        #expect(SteamWindows.isOn(at: url) == false)
    }

    @Test("Regular-app mode is on, needs the frame, and switching the frame off clears it")
    func regularApp() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try SteamWindows.set(true, regularApp: true, at: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "native-app\n")
        #expect(SteamWindows.isOn(at: url))
        #expect(SteamWindows.isRegularApp(at: url))

        try SteamWindows.set(true, regularApp: false, at: url)
        #expect(SteamWindows.isOn(at: url) && !SteamWindows.isRegularApp(at: url))

        try SteamWindows.set(false, regularApp: true, at: url)
        #expect(!SteamWindows.isOn(at: url) && !SteamWindows.isRegularApp(at: url))
    }

    @Test("The diagnostic log mode is not on, and unknown words are off")
    func otherWords() throws {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        try "log\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(SteamWindows.mode(at: url) == "log")
        #expect(SteamWindows.isOn(at: url) == false)

        try "nativeish please".write(to: url, atomically: true, encoding: .utf8)
        #expect(SteamWindows.mode(at: url) == "off")
    }
}
