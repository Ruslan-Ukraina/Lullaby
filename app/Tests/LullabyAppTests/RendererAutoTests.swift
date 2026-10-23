import Foundation
import Testing
@testable import LullabySettings

@Suite("Automatic renderer choice")
struct RendererAutoTests {
    /// A PE file with the given imports (32 or 64 bit) built by hand: one .idata section.
    static func pe(imports: [String], is64: Bool = true) -> Data {
        var d = Data(count: 0x400)
        func put16(_ o: Int, _ v: Int) { d[o] = UInt8(v & 255); d[o + 1] = UInt8(v >> 8 & 255) }
        func put32(_ o: Int, _ v: Int) { for i in 0..<4 { d[o + i] = UInt8(v >> (8 * i) & 255) } }
        put16(0, 0x5A4D); put32(0x3C, 0x80)
        let pe = 0x80, opt = is64 ? 240 : 224
        put32(pe, 0x4550); put16(pe + 6, 1); put16(pe + 20, opt); put16(pe + 24, is64 ? 0x20B : 0x10B)
        let dirs = pe + 24 + (is64 ? 112 : 96)
        put32(dirs + 8, 0x1000)  // import table RVA
        let sec = pe + 24 + opt
        put32(sec + 8, 0x200); put32(sec + 12, 0x1000); put32(sec + 16, 0x200); put32(sec + 20, 0x200)
        var strings = 0x1000 + 20 * (imports.count + 1)
        for (i, name) in imports.enumerated() {
            put32(0x200 + i * 20 + 12, strings)
            let at = 0x200 + (strings - 0x1000)
            for (j, b) in Array(name.utf8).enumerated() { d[at + j] = b }
            strings += name.utf8.count + 1
        }
        return d
    }

    @Test("Imports are read from a 64 and a 32 bit file; garbage is not a PE")
    func reads() throws {
        let r = try #require(PEImports.read(Self.pe(imports: ["KERNEL32.dll", "D3D11.dll", "dxgi.dll"])))
        #expect(r.names == ["kernel32.dll", "d3d11.dll", "dxgi.dll"] && r.is64)
        #expect(PEImports.apis(of: r.names) == .d3d11)
        let r32 = try #require(PEImports.read(Self.pe(imports: ["d3d9.dll"], is64: false)))
        #expect(!r32.is64 && PEImports.apis(of: r32.names) == .d3d9)
        #expect(PEImports.read(Data("not a pe".utf8)) == nil)
        #expect(PEImports.read(Data(Self.pe(imports: ["d3d11.dll"]).prefix(100))) == nil)
    }

    @Test("The choice follows the newest Direct3D, and D3D12 needs the toolkit")
    func choice() {
        #expect(RendererAuto.choose(apis: [.d3d11, .d3d12], has32bit: false, d3dmetalAvailable: true)?.renderer == .d3dmetal)
        #expect(RendererAuto.choose(apis: .d3d12, has32bit: false, d3dmetalAvailable: false)?.renderer == .dxmt)
        #expect(RendererAuto.choose(apis: [.d3d11, .d3d9], has32bit: false, d3dmetalAvailable: true)?.renderer == .dxmt)
        #expect(RendererAuto.choose(apis: .d3d9, has32bit: true, d3dmetalAvailable: true)?.renderer == .wined3d)
        #expect(RendererAuto.choose(apis: [.vulkan, .opengl], has32bit: false, d3dmetalAvailable: true) == nil)
        #expect(RendererAuto.choose(apis: [], has32bit: false, d3dmetalAvailable: true) == nil)
    }

    @Test("A folder is scanned for its executable and DLLs")
    func folder() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "auto-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appending(path: "bin"), withIntermediateDirectories: true)
        try Self.pe(imports: ["d3d12.dll"]).write(to: dir.appending(path: "bin/Game.exe"))
        try Self.pe(imports: ["d3d9.dll"], is64: false).write(to: dir.appending(path: "bin/helper.dll"))
        let r = RendererAuto.scan(gameFolder: dir, executables: ["game.exe"])
        #expect(r.apis == [.d3d12, .d3d9] && r.has32bit && r.files == 2)
    }

    /// Set AUTO_GAME_DIRS to folders separated by ":" to see the result for installed games.
    @Test("Installed games, when asked for")
    func installed() {
        guard let dirs = ProcessInfo.processInfo.environment["AUTO_GAME_DIRS"] else { return }
        for dir in dirs.split(separator: ":") {
            let r = RendererAuto.scan(gameFolder: URL(filePath: String(dir)), executables: [])
            let pick = RendererAuto.choose(apis: r.apis, has32bit: r.has32bit, d3dmetalAvailable: true)
            print("AUTO \((String(dir) as NSString).lastPathComponent): apis=\(r.apis.rawValue) files=\(r.files) 32bit=\(r.has32bit) -> \(pick.map { "\($0.renderer.rawValue) (\($0.reason))" } ?? "unknown")")
        }
    }
}
