import Foundation
import Testing

@testable import LullabyApp

@Suite("Steam bundle")
struct SteamBundleTests {

    // The bug this guards was live: the sweep covered only the bundle being replaced, and the
    // helpers do not run from there, so an ipcserver survived a stop that reported success.
    @Test("The process sweep covers the helpers as well as the bundle being modified")
    func sweepCoversHelpers() {
        let patterns = SteamBundle.sweepPatterns(
            app: SupportPaths.Steam.app, helpers: [SupportPaths.Steam.innerApp]
        )

        #expect(patterns.count == 2)
        #expect(patterns.contains("/Applications/Steam.app/"))
        #expect(
            patterns.contains { $0.hasSuffix("/Steam.AppBundle/Steam/") },
            "the inner bundle, where ipcserver and the helpers actually run, is not swept"
        )
    }

    // Without it, the pattern matches any process whose command line merely mentions the
    // path, including this test runner.
    @Test("Every pattern is directory-scoped")
    func patternsAreDirectoryScoped() {
        let patterns = SteamBundle.sweepPatterns(
            app: URL(filePath: "/tmp/Some.app"), helpers: [URL(filePath: "/tmp/Inner")]
        )

        #expect(patterns.allSatisfy { $0.hasSuffix("/") })
        #expect(patterns == ["/tmp/Some.app/", "/tmp/Inner/"])
    }

    @Test("Sweeping nothing is possible, so a test can stop short of killing helpers")
    func helpersCanBeEmpty() {
        let patterns = SteamBundle.sweepPatterns(app: URL(filePath: "/tmp/A.app"), helpers: [])
        #expect(patterns == ["/tmp/A.app/"])
    }

    private enum Insert {
        case absent
        case own
        case other(String)
    }

    private func stubBundle(insert: Insert, dylib: Bool) throws -> URL {
        let app = URL.temporaryDirectory
            .appending(path: "np-deploy-\(UUID().uuidString)")
            .appending(path: "Steam.app")
        let macOS = app.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)

        var plist: [String: Any] = ["CFBundleIdentifier": "com.valvesoftware.steam"]
        switch insert {
        case .absent:
            break
        case .own:
            let own = SupportPaths.Steam.deployedDylib(inBundle: app)
            plist[SteamBundle.environmentKey] = [
                SteamBundle.insertKey: own.path(percentEncoded: false)
            ]
        case .other(let value):
            plist[SteamBundle.environmentKey] = [SteamBundle.insertKey: value]
        }
        try PropertyListSerialization
            .data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appending(path: "Contents/Info.plist"))

        if dylib {
            try Data("stand-in\n".utf8).write(to: macOS.appending(path: SupportPaths.dylibName))
        }
        return app
    }

    private func versionFile(_ version: String?) throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "np-version-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: "dylib.version")
        if let version { try Data("\(version)\n".utf8).write(to: url) }
        return url
    }

    @Test("A bundle patched for this account with a matching version reads as installed")
    func installedForThisAccount() throws {
        #expect(
            SteamBundle.deployment(
                bundledVersion: "0.2.0",
                app: try stubBundle(insert: .own, dylib: true),
                versionFile: try versionFile("0.2.0")
            ) == .installed(version: "0.2.0")
        )
    }

    @Test("A bundle patched by another account reports no version rather than a clean install")
    func patchedByAnotherAccount() throws {
        #expect(
            SteamBundle.deployment(
                bundledVersion: "0.2.0",
                app: try stubBundle(insert: .own, dylib: true),
                versionFile: try versionFile(nil)
            ) == .installed(version: nil)
        )
    }

    @Test("A plist naming a dylib that is not there reads as not installed")
    func namedDylibMissing() throws {
        #expect(
            SteamBundle.deployment(
                bundledVersion: "0.2.0",
                app: try stubBundle(insert: .own, dylib: false),
                versionFile: try versionFile("0.2.0")
            ) == .notInstalled
        )
    }

    @Test("An older recorded version reads as outdated")
    func outdatedVersion() throws {
        #expect(
            SteamBundle.deployment(
                bundledVersion: "0.2.0",
                app: try stubBundle(insert: .own, dylib: true),
                versionFile: try versionFile("0.1.0")
            ) == .outdated(deployed: "0.1.0", bundled: "0.2.0", stale: [])
        )
    }

    // The bug this guards was live: Status said "Installed (1.0.2)" over a dylib from an
    // older build of 1.0.2, and there was no button to replace it.
    @Test("The same version with a stale part reads as outdated, naming the part")
    func sameVersionStaleContent() throws {
        #expect(
            SteamBundle.deployment(
                bundledVersion: "0.2.0",
                stale: [.dylib, .runScript],
                app: try stubBundle(insert: .own, dylib: true),
                versionFile: try versionFile("0.2.0")
            ) == .outdated(deployed: "0.2.0", bundled: "0.2.0", stale: [.dylib, .runScript])
        )
    }

    @Test("Stale parts on a Steam patched by another account still read as outdated")
    func staleWithoutVersionFile() throws {
        #expect(
            SteamBundle.deployment(
                bundledVersion: "0.2.0",
                stale: [.bridge],
                app: try stubBundle(insert: .own, dylib: true),
                versionFile: try versionFile(nil)
            ) == .outdated(deployed: nil, bundled: "0.2.0", stale: [.bridge])
        )
    }

    @Test("Stale parts do not hide somebody else's insert")
    func staleDoesNotMaskForeign() throws {
        #expect(
            SteamBundle.deployment(
                bundledVersion: "0.2.0",
                stale: [.dylib],
                app: try stubBundle(insert: .other("/opt/other/thing.dylib"), dylib: true),
                versionFile: try versionFile("0.2.0")
            ) == .foreign(insert: "/opt/other/thing.dylib")
        )
    }

    @Test("Somebody else's insert is left alone")
    func foreignInsert() throws {
        #expect(
            SteamBundle.deployment(
                bundledVersion: "0.2.0",
                app: try stubBundle(insert: .other("/opt/other/thing.dylib"), dylib: true),
                versionFile: try versionFile(nil)
            ) == .foreign(insert: "/opt/other/thing.dylib")
        )
    }

    @Test("An unpatched bundle reads as not installed")
    func unpatched() throws {
        #expect(
            SteamBundle.deployment(
                bundledVersion: "0.2.0",
                app: try stubBundle(insert: .absent, dylib: false),
                versionFile: try versionFile(nil)
            ) == .notInstalled
        )
    }

    @Test("A missing bundle reads as Steam missing")
    func steamMissing() throws {
        #expect(
            SteamBundle.deployment(
                bundledVersion: "0.2.0",
                app: URL.temporaryDirectory.appending(path: "np-absent-\(UUID().uuidString).app"),
                versionFile: try versionFile("0.2.0")
            ) == .steamMissing
        )
    }

    // Steam in a test: running until a given number of polls after a quit request.
    private final class FakeSteam {
        var running: Bool
        var pollsToQuit: Int?
        var polls = 0
        var exitURLs = 0
        var quitEvents = 0
        var swept: [String] = []
        var slept: TimeInterval = 0

        init(running: Bool, pollsToQuit: Int?) {
            self.running = running
            self.pollsToQuit = pollsToQuit
        }

        func quit(timeout: TimeInterval = 10) throws -> Bool {
            try SteamBundle.quitClient(
                app: URL(filePath: "/tmp/Steam.app"),
                helpers: [URL(filePath: "/tmp/Inner")],
                timeout: timeout,
                poll: 1,
                isRunning: {
                    guard running, let limit = pollsToQuit, exitURLs > 0 else { return running }
                    if polls >= limit { running = false }
                    return running
                },
                openExitURL: { exitURLs += 1 },
                sendQuitEvent: { quitEvents += 1 },
                sleep: { slept += $0; polls += 1 },
                sweep: { swept = $0 }
            )
        }
    }

    @Test("A Steam that is not running is left alone")
    func quitNotRunning() throws {
        let steam = FakeSteam(running: false, pollsToQuit: nil)
        #expect(try !steam.quit())
        #expect(steam.exitURLs == 0)
        #expect(steam.quitEvents == 0)
        #expect(steam.swept.isEmpty)
    }

    @Test("steam://exit closes Steam: no Quit event, helpers swept afterwards")
    func quitByExitURL() throws {
        let steam = FakeSteam(running: true, pollsToQuit: 3)
        #expect(try steam.quit())
        #expect(steam.exitURLs == 1)
        #expect(steam.quitEvents == 0)
        #expect(steam.swept == ["/tmp/Steam.app/", "/tmp/Inner/"])
    }

    @Test("A Steam slow to quit gets the Quit Apple event halfway through the wait")
    func quitByAppleEvent() throws {
        let steam = FakeSteam(running: true, pollsToQuit: 7)
        #expect(try steam.quit(timeout: 10))
        #expect(steam.exitURLs == 1)
        #expect(steam.quitEvents == 1)
    }

    // The bug this guards was live: Reinstall sent SIGTERM, which steam_osx ignores, and
    // Steam stayed open. Now it asks, waits, and hands the decision back with Retry.
    @Test("A Steam that will not quit is reported, not killed, once the wait is over")
    func quitTimesOut() throws {
        let steam = FakeSteam(running: true, pollsToQuit: nil)
        do {
            _ = try steam.quit(timeout: 10)
            Issue.record("a Steam that never quit was reported as stopped")
        } catch let error as SteamBundle.StillRunning {
            #expect(error == SteamBundle.StillRunning(seconds: 10))
            #expect(error.localizedDescription.contains("Retry"))
        }
        #expect(steam.slept == 10)
        #expect(steam.quitEvents == 1)
        #expect(steam.swept.isEmpty, "helpers were swept while Steam was still up")
    }
}
