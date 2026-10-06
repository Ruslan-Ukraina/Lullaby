import Foundation
import Testing

@testable import NotProtonApp

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
