import CryptoKit
import Foundation
import Testing
@testable import LullabySettings

@Suite("Game fix installer")
struct GameFixInstallerTests {
    static func sha(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// A game folder with bin/NvCloth_x64.dll ("original"), an assets folder with the proxy,
    /// and a catalog fix that proxies the DLL and adds a file.
    struct Rig {
        let game: URL, assets: URL, fix: GameFix
        init(verified: Bool = true, originalHash: String? = GameFixInstallerTests.sha("original")) throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "fixrig-\(UUID().uuidString)")
            game = root.appending(path: "game"); assets = root.appending(path: "assets")
            try FileManager.default.createDirectory(at: game.appending(path: "bin"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
            try Data("original".utf8).write(to: game.appending(path: "bin/NvCloth_x64.dll"))
            try Data("proxy".utf8).write(to: assets.appending(path: "proxy.dll"))
            try Data("extra".utf8).write(to: assets.appending(path: "extra.ini"))
            let original = originalHash.map { #","originalSha256":"\#($0)""# } ?? ""
            let json = """
            {"schema":1,"serial":1,"entries":[{"id":"fx","name":"G","match":{"appIDs":[1]},"verdict":"fits",
             "backend":"d3dmetal"\(verified ? #","verifiedOn":"r6""# : ""),
             "files":[{"op":"proxy","path":"bin/NvCloth_x64.dll","asset":"proxy.dll","sha256":"\(GameFixInstallerTests.sha("proxy"))"\(original)},
                      {"op":"add","path":"bin/fix.ini","asset":"extra.ini","sha256":"\(GameFixInstallerTests.sha("extra"))"}],
             "source":{"kind":"macgamefix","ref":"fixes/install-resonance-fix.sh","license":"GPL-3.0"}}]}
            """
            fix = try GameFixCatalog.decode(Data(json.utf8)).entries[0]
        }
        func text(_ path: String) -> String? { try? String(contentsOf: game.appending(path: path), encoding: .utf8) }
    }

    @Test("Install renames the game's DLL, puts the proxy and the added file, and restore undoes it")
    func roundTrip() throws {
        let r = try Rig()
        try GameFixInstaller.install(r.fix, game: r.game, assets: r.assets)
        #expect(r.text("bin/NvCloth_x64.dll") == "proxy" && r.text("bin/NvCloth_x64_real.dll") == "original")
        #expect(r.text("bin/fix.ini") == "extra")
        #expect(GameFixInstaller.state(game: r.game) == .installed(fixID: "fx"))
        try GameFixInstaller.install(r.fix, game: r.game, assets: r.assets)  // again: nothing more
        try GameFixInstaller.restore(game: r.game)
        #expect(r.text("bin/NvCloth_x64.dll") == "original")
        #expect(r.text("bin/NvCloth_x64_real.dll") == nil && r.text("bin/fix.ini") == nil)
        #expect(GameFixInstaller.state(game: r.game) == .notInstalled)
    }

    @Test("An unverified fix, a running game, a wrong original or a wrong asset change nothing")
    func refusals() throws {
        let unverified = try Rig(verified: false)
        #expect(throws: GameFixInstaller.Failure.self) { try GameFixInstaller.install(unverified.fix, game: unverified.game, assets: unverified.assets) }
        let r = try Rig()
        #expect(throws: GameFixInstaller.Failure.gameRunning) {
            try GameFixInstaller.install(r.fix, game: r.game, assets: r.assets, isRunning: { true })
        }
        let other = try Rig(originalHash: Self.sha("another version"))
        #expect(throws: GameFixInstaller.Failure.originalMismatch("bin/NvCloth_x64.dll")) {
            try GameFixInstaller.install(other.fix, game: other.game, assets: other.assets)
        }
        try Data("tampered".utf8).write(to: r.assets.appending(path: "proxy.dll"))
        #expect(throws: GameFixInstaller.Failure.assetMismatch("proxy.dll")) {
            try GameFixInstaller.install(r.fix, game: r.game, assets: r.assets)
        }
        for rig in [r, other, unverified] {
            #expect(rig.text("bin/NvCloth_x64.dll") == "original" && rig.text("bin/fix.ini") == nil)
        }
    }

    @Test("A failure half way puts everything back")
    func rollback() throws {
        let r = try Rig()
        try Data("occupied".utf8).write(to: r.game.appending(path: "bin/fix.ini"))
        #expect(throws: GameFixInstaller.Failure.occupied("bin/fix.ini")) {
            try GameFixInstaller.install(r.fix, game: r.game, assets: r.assets)
        }
        #expect(r.text("bin/NvCloth_x64.dll") == "original" && r.text("bin/NvCloth_x64_real.dll") == nil)
        #expect(r.text("bin/fix.ini") == "occupied")
    }

    @Test("A game update after the install: status says modified and restore leaves the new file alone")
    func gameUpdated() throws {
        let r = try Rig()
        try GameFixInstaller.install(r.fix, game: r.game, assets: r.assets)
        try Data("updated by Steam".utf8).write(to: r.game.appending(path: "bin/NvCloth_x64.dll"))
        #expect(GameFixInstaller.state(game: r.game) == .modified)
        #expect(throws: GameFixInstaller.Failure.modified("bin/NvCloth_x64.dll")) { try GameFixInstaller.restore(game: r.game) }
        #expect(r.text("bin/NvCloth_x64.dll") == "updated by Steam" && r.text("bin/NvCloth_x64_real.dll") == "original")
    }

    @Test("Paths that leave the game folder are refused by the catalog and by a link")
    func paths() throws {
        let bad = GameFixCatalogTests.entry(more: #","files":[{"op":"add","path":"../x.dll","asset":"a","sha256":"\#(Self.sha("a"))"}]"#)
        #expect(GameFixCatalogTests.rejects(GameFixCatalogTests.catalog(bad), "file path"))
        let proxyNotDLL = GameFixCatalogTests.entry(more: #","files":[{"op":"proxy","path":"a.exe","asset":"a","sha256":"\#(Self.sha("a"))"}]"#)
        #expect(GameFixCatalogTests.rejects(GameFixCatalogTests.catalog(proxyNotDLL), "a proxy replaces a DLL"))
        let r = try Rig()
        let outside = FileManager.default.temporaryDirectory.appending(path: "outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: r.game.appending(path: "link"), withDestinationURL: outside)
        #expect(GameFixInstaller.inside(r.game, "link/x.dll") == nil)
        #expect(GameFixInstaller.inside(r.game, "bin/x.dll") != nil)
    }
}
