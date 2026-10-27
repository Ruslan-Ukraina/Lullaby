import Foundation
import Testing

@testable import LullabyApp

// Run against a real pinned Valve bundle staged into scratch, not /Applications/Steam.app.
// The chain seals a dylib inside a bundle inside another signature. Serialized, one cache.
@Suite("Steam installer", .serialized, .enabled(if: StagedPayload.present, StagedPayload.reason))
struct SteamInstallerTests {

    private func scratch() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "np-install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func stockBundle(into work: URL) async throws -> URL {
        let manifest = try ValvePackageManifest.bundled()
        let bundle = try #require(manifest.bundle)
        return try await SteamRepair.stage(
            bundle,
            bases: manifest.bases,
            downloads: TestCache.valvePackages,
            work: work.appending(path: "staging")
        )
    }

    // A stand-in payload rather than the shipped one, so the tests do not depend on make
    // having been run. The dylib has to be a real Mach-O because it gets signed.
    private func payload(in work: URL) throws -> InstallPayload.Located {
        let root = work.appending(path: "payload")
        let signatureDir = root.appending(path: "signatures/macos.arm64")
        try FileManager.default.createDirectory(at: signatureDir, withIntermediateDirectories: true)

        let source = work.appending(path: "probe.c")
        try Data("int lb_probe(void) { return 1; }\n".utf8).write(to: source)

        let dylib = root.appending(path: SupportPaths.dylibName)
        try Shell.check("/usr/bin/clang", [
            "-dynamiclib", "-o", dylib.path(percentEncoded: false), source.path(percentEncoded: false),
        ])

        let shim = root.appending(path: "overlay-shim.dylib")
        try FileManager.default.copyItem(at: dylib, to: shim)

        let iconmaker = root.appending(path: "iconmaker")
        try FileManager.default.copyItem(at: dylib, to: iconmaker)

        let appinfo = root.appending(path: "appinfo")
        try FileManager.default.copyItem(at: dylib, to: appinfo)
        try FileManager.default.copyItem(at: dylib, to: root.appending(path: SupportPaths.nvapiShimName))
        try FileManager.default.copyItem(at: dylib, to: root.appending(path: SupportPaths.windowStateName))
        try FileManager.default.copyItem(at: dylib, to: root.appending(path: SupportPaths.glFixesName))
        try FileManager.default.copyItem(at: dylib, to: root.appending(path: SupportPaths.pacerName))
        try FileManager.default.copyItem(at: dylib, to: root.appending(path: SupportPaths.settingsCLIName))

        try Data("#!/bin/sh\necho shipped\n".utf8)
            .write(to: root.appending(path: InstallPayload.runScriptName))

        try Data("{}".utf8).write(to: signatureDir.appending(path: "1788400362.json"))
        try Data("{}".utf8).write(to: signatureDir.appending(path: "1788652215.json"))

        return try InstallPayload.locate(root: root)
    }

    private struct Fixture {
        let work: URL
        let app: URL
        let payload: InstallPayload.Located
        let support: URL

        var plist: URL { app.appending(path: "Contents/Info.plist") }
        var deployedDylib: URL { app.appending(path: "Contents/MacOS/\(SupportPaths.dylibName)") }
        var signatures: URL { support.appending(path: "signatures/macos.arm64") }
        var overlayShim: URL { support.appending(path: "overlay-shim.dylib") }
        var iconmaker: URL { support.appending(path: "iconmaker") }
        var appinfo: URL { support.appending(path: "appinfo") }
        var nvapiShim: URL { support.appending(path: SupportPaths.nvapiShimName) }
        var windowState: URL { support.appending(path: SupportPaths.windowStateName) }
        var glFixes: URL { support.appending(path: SupportPaths.glFixesName) }
        var pacer: URL { support.appending(path: SupportPaths.pacerName) }
        var settingsCLI: URL { support.appending(path: SupportPaths.settingsCLIName) }
        var deployedVersion: URL { support.appending(path: "dylib.version") }
        var backups: URL { support.appending(path: "backups") }
        var bridge: URL { support.appending(path: "bridge") }
        var toolFolder: URL { work.appending(path: "compatibilitytools.d/lullaby") }
        var runScript: URL { toolFolder.appending(path: "run") }
    }

    private func fixture(into work: URL) async throws -> Fixture {
        Fixture(
            work: work,
            app: try await stockBundle(into: work),
            payload: try payload(in: work),
            support: work.appending(path: "support")
        )
    }

    // The registrar and stopper a test uses: record the call, do nothing.
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var registered: [URL] = []
        func register(_ url: URL) { lock.lock(); registered.append(url); lock.unlock() }
        var registrations: [URL] { lock.lock(); defer { lock.unlock() }; return registered }
    }

    private func install(
        _ fixture: Fixture,
        version: String = "9.9.9-test",
        force: Bool = false,
        calls: Calls = Calls(),
        stopped: Bool = false,
        gameRunning: Bool = false
    ) throws -> InstallOutcome {
        try SteamInstaller.run(
            payload: fixture.payload,
            version: version,
            force: force,
            app: fixture.app,
            bridge: fixture.bridge,
            signatures: fixture.signatures,
            overlayShim: fixture.overlayShim,
            iconmaker: fixture.iconmaker,
            appinfo: fixture.appinfo,
            nvapiShim: fixture.nvapiShim,
            windowState: fixture.windowState,
            glFixes: fixture.glFixes,
            pacer: fixture.pacer,
            settingsCLI: fixture.settingsCLI,
            deployedVersion: fixture.deployedVersion,
            backups: fixture.backups,
            runScript: fixture.runScript,
            gameIsRunning: { gameRunning },
            stopClient: { _, onStopping in if stopped { onStopping() }; return stopped },
            register: { calls.register($0) }
        )
    }

    @Test("A full install puts every artifact in place and declares the insert")
    func installsEverything() async throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let fixture = try await self.fixture(into: work)
        let calls = Calls()

        let outcome = try install(fixture, calls: calls)

        #expect(outcome.version == "9.9.9-test")
        #expect(outcome.signatureDatabases == 2)
        #expect(outcome.backedUpPlist)
        #expect(!outcome.stoppedClient)

        let files = FileManager.default
        #expect(files.fileExists(atPath: fixture.deployedDylib.path(percentEncoded: false)))
        #expect(files.fileExists(atPath: fixture.overlayShim.path(percentEncoded: false)))
        #expect(files.fileExists(atPath: fixture.iconmaker.path(percentEncoded: false)))
        #expect(files.fileExists(atPath: fixture.appinfo.path(percentEncoded: false)))
        #expect(
            try String(contentsOf: fixture.deployedVersion, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines) == "9.9.9-test"
        )

        // Both databases, and the arch component preserved: the dylib builds that path
        // itself, so a database one level up resolves nothing.
        let installed = try files.contentsOfDirectory(atPath: fixture.signatures.path(percentEncoded: false))
        #expect(installed.sorted() == ["1788400362.json", "1788652215.json"])

        #expect(
            SteamBundle.currentInsert(at: fixture.plist)
                == fixture.deployedDylib.path(percentEncoded: false)
        )
        #expect(calls.registrations == [fixture.app], "the bundle was not re-registered")
    }

    @Test("Setting the insert keeps the rest of Valve's environment")
    func preservesValveEnvironment() async throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let fixture = try await self.fixture(into: work)

        // What Valve actually ships, asserted before the install rather than assumed.
        let before = try #require(SteamBundle.readInfoPlist(at: fixture.plist))
        let stock = try #require(before[SteamBundle.environmentKey] as? [String: Any])
        #expect(stock["LC_ALL"] as? String == "en_US.UTF-8")

        _ = try install(fixture)

        let after = try #require(SteamBundle.readInfoPlist(at: fixture.plist))
        let environment = try #require(after[SteamBundle.environmentKey] as? [String: Any])
        #expect(environment["LC_ALL"] as? String == "en_US.UTF-8", "LC_ALL is Valve's and has to survive")
        #expect(
            Set(environment.keys) == ["LC_ALL", SteamBundle.insertKey, SteamBundle.controllerBlockKey],
            "only the insert and the controller block list should have been added")
        #expect(after["CFBundleVersion"] as? String == "6.1", "the rest of the plist was disturbed")
    }

    @Test("The bundle is signed inner to outer, so every seal verifies afterwards")
    func signsInnerToOuter() async throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let fixture = try await self.fixture(into: work)

        _ = try install(fixture)

        // The outer seal covers the executable and the dylib is sealed in its own right, so
        // signing outer first would leave the bundle describing files that changed afterwards.
        for target in [fixture.deployedDylib, fixture.app.appending(path: "Contents/MacOS/steam_osx"), fixture.app] {
            let result = try Shell.run("/usr/bin/codesign", ["--verify", "--strict", target.path(percentEncoded: false)])
            #expect(result.succeeded, "\(target.lastPathComponent) does not verify: \(result.stderr)")
        }

        // Valve's authority is gone, which is the whole reason repair replaces the bundle
        // rather than editing it back.
        let described = try Shell.run("/usr/bin/codesign", ["-dvv", fixture.app.path(percentEncoded: false)])
        #expect(!(described.stdout + described.stderr).contains("TeamIdentifier=MXGJJ98X76"))
    }

    @Test("An insert belonging to something else stops the install and is left alone")
    func refusesForeignInsert() async throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let fixture = try await self.fixture(into: work)

        let foreign = "/Applications/Steam.app/Contents/MacOS/somethingelse.dylib"
        try SteamInstaller.setInsert(at: fixture.plist, to: URL(filePath: foreign))

        do {
            _ = try install(fixture)
            Issue.record("an install over a foreign insert was allowed")
        } catch let failure as StepFailure {
                #expect(failure.detail.contains("Repair your Steam install"))
        }

        #expect(SteamBundle.currentInsert(at: fixture.plist) == foreign, "the foreign insert was modified")
        #expect(
            !FileManager.default.fileExists(atPath: fixture.deployedDylib.path(percentEncoded: false)),
            "the dylib was copied in despite the refusal"
        )
    }

    @Test("Installing over an existing install is allowed and refreshes it")
    func reinstallIsAllowed() async throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let fixture = try await self.fixture(into: work)

        _ = try install(fixture, version: "1.0.0")
        let second = try install(fixture, version: "2.0.0")

        #expect(second.version == "2.0.0")
        #expect(
            try String(contentsOf: fixture.deployedVersion, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines) == "2.0.0"
        )
        // Taken by the first install, and not retaken: a backup of what Lullaby itself
        // left behind is not a backup of the original.
        #expect(second.backedUpPlist == false)
    }

    @Test("A failure while signing puts the plist back, so the bundle still starts")
    func revertsInsertWhenSigningFails() async throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let fixture = try await self.fixture(into: work)

        let before = try Data(contentsOf: fixture.plist)

        // Signing walks inner to outer with the client executable second, so removing it fails
        // between the insert and the signature. That window left a Steam its own seal misses.
        try FileManager.default.removeItem(at: fixture.app.appending(path: "Contents/MacOS/steam_osx"))

        let failure = try #require(throws: StepFailure.self) { try install(fixture) }

        // Asserting where the failure came from, because a test that stopped earlier
        // than the signing step would pass on a plist that was never touched.
        #expect(
            failure.detail.contains("could not be signed"),
            "the install failed before the window this test is about: \(failure.detail)"
        )
        #expect(
            try Data(contentsOf: fixture.plist) == before,
            "the plist kept the insert, so the executable no longer matches its signature"
        )
        #expect(SteamBundle.currentInsert(at: fixture.plist) == nil)
    }

    @Test("The plist backup records the state before the first install only")
    func backsUpOriginalPlistOnce() async throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let fixture = try await self.fixture(into: work)

        _ = try install(fixture)

        let backup = fixture.backups.appending(path: "Info.plist.before-lullaby")
        let saved = try #require(SteamBundle.readInfoPlist(at: backup))
        let environment = try #require(saved[SteamBundle.environmentKey] as? [String: Any])
        #expect(environment[SteamBundle.insertKey] == nil, "the backup already carries an insert")
        #expect(environment["LC_ALL"] as? String == "en_US.UTF-8")
    }

    @Test("A missing Steam bundle is reported as its own condition")
    func reportsMissingBundle() async throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        var fixture = try await self.fixture(into: work)
        fixture = Fixture(
            work: work,
            app: work.appending(path: "nothing-here/Steam.app"),
            payload: fixture.payload,
            support: fixture.support
        )

        do {
            _ = try install(fixture)
            Issue.record("an install into a bundle that is not there was allowed")
        } catch let failure as StepFailure {
            #expect(failure.detail.contains("is not there"))
        }
    }

    // Straight at the probe, so neither of these needs a Valve bundle to be fetched first.
    private func bundle(writable: Bool) throws -> URL {
        let app = try scratch().appending(path: "Steam.app")
        try FileManager.default.createDirectory(
            at: app.appending(path: "Contents/MacOS"), withIntermediateDirectories: true
        )
        if !writable {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o500],
                ofItemAtPath: app.appending(path: "Contents/MacOS").path(percentEncoded: false)
            )
        }
        return app
    }

    @Test("A bundle that refuses the probe is reported as a refused write")
    func probeRefusalIsARefusal() throws {
        let app = try bundle(writable: false)
        let inside = app.appending(path: "Contents/MacOS").path(percentEncoded: false)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: inside)
            try? FileManager.default.removeItem(at: app.deletingLastPathComponent())
        }

        let refusal = try #require(throws: WriteRefused.self) {
            try SteamInstaller.assertBundleIsWritable(app)
        }

        #expect(refusal.path == inside)
    }

    // The probe used to call every failure a refused write, so anything that stopped it sent
    // the user to grant a permission that had nothing to do with it.
    @Test("A probe that fails for another reason keeps that reason")
    func probeFailureKeepsItsOwnReason() throws {
        let app = try scratch().appending(path: "Steam.app")
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

        let failure = try #require(throws: StepFailure.self) {
            try SteamInstaller.assertBundleIsWritable(app)
        }

        #expect(failure.detail.contains("could not be written"))
        #expect(
            failure.detail.contains("App Management") == false,
            "a bundle that is not there was reported as a permission to grant"
        )
    }

    @Test("A bundle that takes the probe is left exactly as it was")
    func probeLeavesNothingBehind() throws {
        let app = try bundle(writable: true)
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }

        try SteamInstaller.assertBundleIsWritable(app)

        let left = try FileManager.default.contentsOfDirectory(
            atPath: app.appending(path: "Contents/MacOS").path(percentEncoded: false)
        )
        #expect(left.isEmpty, "the probe file was left in the bundle")
    }

    @Test("A second account installs its own components without touching a patched Steam")
    func secondAccountLeavesTheBundleAlone() async throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let fixture = try await self.fixture(into: work)
        let files = FileManager.default

        _ = try install(fixture)

        let pinned = Date(timeIntervalSince1970: 1_000_000)
        try files.setAttributes(
            [.modificationDate: pinned],
            ofItemAtPath: fixture.deployedDylib.path(percentEncoded: false)
        )
        try files.removeItem(at: fixture.support)

        let outcome = try install(fixture, stopped: true)

        #expect(!outcome.stoppedClient, "Steam was stopped for an install that changed nothing")
        #expect(!outcome.backedUpPlist)
        #expect(outcome.signatureDatabases == 2)

        let untouched = try files.attributesOfItem(
            atPath: fixture.deployedDylib.path(percentEncoded: false)
        )[.modificationDate] as? Date
        #expect(untouched == pinned, "the deployed dylib was rewritten")

        #expect(files.fileExists(atPath: fixture.overlayShim.path(percentEncoded: false)))
        #expect(files.fileExists(atPath: fixture.iconmaker.path(percentEncoded: false)))
        #expect(files.fileExists(atPath: fixture.appinfo.path(percentEncoded: false)))
        #expect(
            try files.contentsOfDirectory(atPath: fixture.signatures.path(percentEncoded: false))
                .sorted() == ["1788400362.json", "1788652215.json"]
        )
        #expect(
            try String(contentsOf: fixture.deployedVersion, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines) == "9.9.9-test"
        )
    }

    @Test("A Steam carrying a different build of the dylib is patched again")
    func differentBuildIsPatched() async throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let fixture = try await self.fixture(into: work)

        _ = try install(fixture)
        #expect(
            try !SteamInstaller.needsPatching(
                plist: fixture.plist,
                dylib: fixture.deployedDylib,
                shipping: fixture.payload.dylib,
                app: fixture.app
            )
        )

        try Data("a different build".utf8).write(to: fixture.deployedDylib)

        #expect(
            try SteamInstaller.needsPatching(
                plist: fixture.plist,
                dylib: fixture.deployedDylib,
                shipping: fixture.payload.dylib,
                app: fixture.app
            )
        )
    }

    @Test("Install keeps the generic Steam Controller copy away from Steam, and a Steam without that is patched again")
    func controllerBlockIsDeployed() async throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let fixture = try await self.fixture(into: work)

        _ = try install(fixture)
        #expect(SteamBundle.currentControllerBlock(at: fixture.plist) == SteamBundle.controllerBlockValue)
        #expect(SteamBundle.currentInsert(at: fixture.plist) == fixture.deployedDylib.path(percentEncoded: false))

        // A Steam patched by an older Lullaby: the same dylib, no block list.
        var dict = try #require(SteamBundle.readInfoPlist(at: fixture.plist))
        var environment = try #require(dict[SteamBundle.environmentKey] as? [String: Any])
        environment.removeValue(forKey: SteamBundle.controllerBlockKey)
        dict[SteamBundle.environmentKey] = environment
        try SteamBundle.writeInfoPlist(dict, at: fixture.plist)

        #expect(
            try SteamInstaller.needsPatching(
                plist: fixture.plist,
                dylib: fixture.deployedDylib,
                shipping: fixture.payload.dylib,
                app: fixture.app
            )
        )
    }

    @Test("A payload with nothing in it stops the install before anything is touched")
    func refusesEmptyPayload() async throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let fixture = try await self.fixture(into: work)

        let empty = work.appending(path: "empty-payload")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        #expect(throws: StepFailure.self) { try InstallPayload.locate(root: empty) }
        #expect(SteamBundle.currentInsert(at: fixture.plist) == nil)
    }

    @Test("Reinstall patches Steam again even when it already carries this build")
    func reinstallForcesPatching() async throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let fixture = try await self.fixture(into: work)
        let files = FileManager.default

        _ = try install(fixture)
        let pinned = Date(timeIntervalSince1970: 1_000_000)
        try files.setAttributes(
            [.modificationDate: pinned],
            ofItemAtPath: fixture.deployedDylib.path(percentEncoded: false)
        )

        let plain = try install(fixture, stopped: true)
        #expect(!plain.stoppedClient, "a plain install stopped Steam for the same build")

        let forced = try install(fixture, force: true, stopped: true)
        #expect(forced.stoppedClient, "reinstall did not stop Steam")
        let rewritten = try files.attributesOfItem(
            atPath: fixture.deployedDylib.path(percentEncoded: false)
        )[.modificationDate] as? Date
        #expect(rewritten != pinned, "reinstall left the deployed dylib alone")
        #expect(forced.build == MachOBuild.shortBuild(of: fixture.payload.dylib))
        #expect(
            SteamBundle.currentInsert(at: fixture.plist)
                == fixture.deployedDylib.path(percentEncoded: false)
        )
    }

    @Test("The run script is written into Steam's tool folder, executable, when the folder exists")
    func writesRunScript() async throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let fixture = try await self.fixture(into: work)
        let files = FileManager.default

        _ = try install(fixture)
        #expect(
            !files.fileExists(atPath: fixture.toolFolder.path(percentEncoded: false)),
            "the installer created the dylib's tool folder"
        )

        try files.createDirectory(at: fixture.toolFolder, withIntermediateDirectories: true)
        try Data("#!/bin/sh\necho old\n".utf8).write(to: fixture.runScript)
        _ = try install(fixture)

        #expect(try Data(contentsOf: fixture.runScript) == Data(contentsOf: fixture.payload.runScript))
        let mode = try files.attributesOfItem(
            atPath: fixture.runScript.path(percentEncoded: false)
        )[.posixPermissions] as? Int
        #expect(mode == 0o755)
    }

    @Test("A running game stops an install that would close Steam, before Steam is touched")
    func refusesWhileGameRuns() async throws {
        let work = try scratch()
        defer { try? FileManager.default.removeItem(at: work) }
        let fixture = try await self.fixture(into: work)
        let before = try Data(contentsOf: fixture.plist)

        do {
            _ = try install(fixture, stopped: true, gameRunning: true)
            Issue.record("the install went ahead under a running game")
        } catch let failure as StepFailure {
            #expect(failure.detail == SteamInstaller.gameRunning)
        }
        #expect(try Data(contentsOf: fixture.plist) == before)
        #expect(!FileManager.default.fileExists(atPath: fixture.deployedDylib.path(percentEncoded: false)))

        // Nothing to patch: a running game does not matter, Steam is not stopped.
        _ = try install(fixture)
        let outcome = try install(fixture, stopped: true, gameRunning: true)
        #expect(!outcome.stoppedClient)
    }
}
