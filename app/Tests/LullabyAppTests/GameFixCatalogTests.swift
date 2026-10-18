import Foundation
import Testing
@testable import LullabySettings

@Suite("Game fix catalog")
struct GameFixCatalogTests {
    static func catalog(_ entries: String, serial: Int = 1, extra: String = "") -> Data {
        Data("""
        {"schema":1,"serial":\(serial),\(extra)"entries":[\(entries)]}
        """.utf8)
    }

    static func entry(id: String = "peak", match: String = #""appIDs":[3527290],"exes":["PEAK.exe"]"#,
                      more: String = "") -> String {
        """
        {"id":"\(id)","name":"PEAK","match":{\(match)},"verdict":"fits","backend":"dxmt",
         "source":{"kind":"lullaby","ref":"","license":"GPL-3.0"}\(more)}
        """
    }

    static func rejects(_ data: Data, _ part: String) -> Bool {
        do { _ = try GameFixCatalog.decode(data); return false } catch let e as GameFixCatalog.Invalid {
            return e.description.contains(part)
        } catch { return false }
    }

    @Test("A valid catalog is read; exes are lower-cased")
    func decodes() throws {
        let c = try GameFixCatalog.decode(Self.catalog(Self.entry(more: #","env":{"WINE_FOO":"1"},"dllOverrides":{"xaudio2_9":"b"}"#)))
        #expect(c.serial == 1 && c.entries.count == 1)
        #expect(c.entries[0].exes == ["peak.exe"] && c.entries[0].backend == .dxmt)
        #expect(c.entries[0].dllOverrides == ["xaudio2_9": "b"])
    }

    @Test("Lookup by app id first, then by executable")
    func lookup() throws {
        let c = try GameFixCatalog.decode(Self.catalog(Self.entry() + "," + Self.entry(id: "other", match: #""exes":["re9.exe"]"#)))
        #expect(c.fix(appID: 3527290, exes: nil, engine: nil, gptk: nil)?.id == "peak")
        #expect(c.fix(appID: 1, exes: ["RE9.EXE"], engine: nil, gptk: nil)?.id == "other")
        #expect(c.fix(appID: 1, exes: ["x.exe"], engine: nil, gptk: nil) == nil)
    }

    @Test("Engine and GPTK versions filter entries; not_needed is never applied")
    func versions() throws {
        let c = try GameFixCatalog.decode(Self.catalog(Self.entry(more: #","needsEngine":"r6","notNeededFromGPTK":"4.1""#)))
        #expect(c.fix(appID: 3527290, exes: nil, engine: "r5", gptk: nil) == nil)
        #expect(c.fix(appID: 3527290, exes: nil, engine: "r10", gptk: "4.0")?.id == "peak")
        #expect(c.fix(appID: 3527290, exes: nil, engine: "r6", gptk: "4.1") == nil)
        let n = try GameFixCatalog.decode(Self.catalog(Self.entry().replacingOccurrences(of: "\"fits\"", with: "\"not_needed\"")))
        #expect(n.fix(appID: 3527290, exes: nil, engine: nil, gptk: nil) == nil)
    }

    @Test("Unknown fields, such as a script or a proxy DLL, reject the file")
    func unknownFields() {
        #expect(Self.rejects(Self.catalog(Self.entry(more: #","script":"run.py""#)), "unknown field script"))
        #expect(Self.rejects(Self.catalog(Self.entry(more: #","copyToGameFolder":["d3d9.dll"]"#)), "unknown field"))
        #expect(Self.rejects(Self.catalog(Self.entry(), extra: #""hooks":[],"#), "unknown field hooks"))
    }

    @Test("Loader and Lullaby variables are not allowed in env")
    func forbiddenEnv() {
        for key in ["DYLD_INSERT_LIBRARIES", "WINEPREFIX", "WINELOADER", "LULLABY_RENDERER", "SEVO_FPS", "WINEDLLOVERRIDES", "PATH", "lower"] {
            #expect(Self.rejects(Self.catalog(Self.entry(more: #","env":{"\#(key)":"1"}"#)), "not allowed"), "\(key)")
        }
        #expect(Self.rejects(Self.catalog(Self.entry(more: #","env":{"A":"x\ny"}"#)), "env value"))
    }

    @Test("DLL overrides take bare names and known modes only")
    func overrides() {
        #expect(Self.rejects(Self.catalog(Self.entry(more: #","dllOverrides":{"../d3d9":"n"}"#)), "dll name"))
        #expect(Self.rejects(Self.catalog(Self.entry(more: #","dllOverrides":{"d3d9":"x"}"#)), "override mode"))
    }

    @Test("Registry values stay inside HKCU\\Software\\Wine")
    func registry() throws {
        let ok = #","registry":[{"key":"HKCU\\Software\\Wine\\Mac Driver","name":"X","type":"REG_DWORD","value":"1"}]"#
        _ = try GameFixCatalog.decode(Self.catalog(Self.entry(more: ok)))
        let game = #","registry":[{"key":"HKCU\\Software\\SomeStudio\\Game","name":"X","type":"REG_SZ","value":"1"}]"#
        #expect(Self.rejects(Self.catalog(Self.entry(more: game)), "outside Software"))
        let dword = ok.replacingOccurrences(of: #""value":"1""#, with: #""value":"abc""#)
        #expect(Self.rejects(Self.catalog(Self.entry(more: dword)), "registry dword"))
    }

    @Test("A foreign source needs a reference and a license; ids are unique; schema is checked")
    func misc() {
        let foreign = Self.entry().replacingOccurrences(of: #""kind":"lullaby","ref":"""#, with: #""kind":"umu-protonfixes","ref":"""#)
        #expect(Self.rejects(Self.catalog(foreign), "foreign source"))
        #expect(Self.rejects(Self.catalog(Self.entry() + "," + Self.entry()), "duplicate id"))
        #expect(Self.rejects(Data(#"{"schema":2,"serial":1,"entries":[]}"#.utf8), "schema"))
        #expect(Self.rejects(Self.catalog(Self.entry(match: "")), "match is empty"))
        #expect(Self.rejects(Self.catalog(Self.entry(match: #""exes":["a/b.exe"]"#)), "bad exe name"))
    }
}

@Suite("Game fix catalog in the settings")
struct GameFixWiringTests {
    static func store(catalog: String?) throws -> SettingsStore {
        let dir = FileManager.default.temporaryDirectory.appending(path: "fixes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let catalog { try Data(catalog.utf8).write(to: dir.appending(path: "game-fixes.json")) }
        return SettingsStore(root: dir)
    }

    @Test("The catalog's fix becomes the game's recipe and adds its lines to the program's file")
    func applies() throws {
        let entry = GameFixCatalogTests.entry(
            id: "x", match: #""appIDs":[777]"#,
            more: #","env":{"WINE_FOO":"1"},"dllOverrides":{"b_dll":"n","a_dll":"b"}"#)
        let store = try Self.store(catalog: String(decoding: GameFixCatalogTests.catalog(entry), as: UTF8.self))
        let stack = store.stack(for: 777)
        #expect(stack.value(\.renderer) == (.dxmt, .recipe))
        let lines = ConfigMaterializer.gameLines(appID: 777, stack: stack)
        #expect(lines.suffix(2) == ["WINE_FOO=1", "WINEDLLOVERRIDES=a_dll=b;b_dll=n"])
    }

    @Test("No catalog, a broken catalog or an unfit verdict leaves the built-in recipes")
    func fallsBack() throws {
        #expect(try Self.store(catalog: nil).stack(for: 3527290).value(\.renderer) == (.dxmt, .recipe))
        #expect(try Self.store(catalog: "{broken").stack(for: 3527290).fixLines.isEmpty)
        let unfit = GameFixCatalogTests.entry(id: "u", match: #""appIDs":[5]"#)
            .replacingOccurrences(of: "\"fits\"", with: "\"unfit\"")
        let store = try Self.store(catalog: String(decoding: GameFixCatalogTests.catalog(unfit), as: UTF8.self))
        #expect(store.stack(for: 5).recipe == .empty)
    }
}
