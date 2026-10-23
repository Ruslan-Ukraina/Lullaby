// Automatic renderer choice (docs/ROADMAP.md §14.3): which Direct3D a game links, read from
// the import tables of its executable and the DLLs beside it. Nothing of the game is changed.
// Engines that pick the API at run time (Unity, Godot) show nothing here; the answer for them
// is `unknown` and the default stays.

import Foundation

public struct GraphicsAPIs: OptionSet, Sendable, Equatable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let d3d8 = GraphicsAPIs(rawValue: 1)
    public static let d3d9 = GraphicsAPIs(rawValue: 2)
    public static let d3d10 = GraphicsAPIs(rawValue: 4)
    public static let d3d11 = GraphicsAPIs(rawValue: 8)
    public static let d3d12 = GraphicsAPIs(rawValue: 16)
    public static let vulkan = GraphicsAPIs(rawValue: 32)
    public static let opengl = GraphicsAPIs(rawValue: 64)
    public static let ddraw = GraphicsAPIs(rawValue: 128)
}

public enum PEImports {
    /// The DLL names a PE file imports (normal and delay-load tables), lower case, and
    /// whether it is 64 bit. nil: not a PE file we can read.
    public static func read(_ data: Data) -> (names: Set<String>, is64: Bool)? {
        func u16(_ o: Int) -> Int? { o >= 0 && o + 2 <= data.count ? Int(data[o]) | Int(data[o + 1]) << 8 : nil }
        func u32(_ o: Int) -> Int? {
            guard o >= 0, o + 4 <= data.count else { return nil }
            return Int(data[o]) | Int(data[o + 1]) << 8 | Int(data[o + 2]) << 16 | Int(data[o + 3]) << 24
        }
        guard u16(0) == 0x5A4D, let pe = u32(0x3C), u32(pe) == 0x4550, let sections = u16(pe + 6),
              let optSize = u16(pe + 20), let magic = u16(pe + 24) else { return nil }
        let is64 = magic == 0x20B
        guard is64 || magic == 0x10B else { return nil }
        let dirs = pe + 24 + (is64 ? 112 : 96)
        let table = pe + 24 + optSize
        var spans: [(rva: Int, size: Int, raw: Int)] = []
        for i in 0..<min(sections, 96) {
            let s = table + i * 40
            guard let vsize = u32(s + 8), let rva = u32(s + 12), let rawSize = u32(s + 16), let raw = u32(s + 20) else { return nil }
            spans.append((rva, max(vsize, rawSize), raw))
        }
        func offset(_ rva: Int) -> Int? {
            spans.first { rva >= $0.rva && rva < $0.rva + $0.size }.map { $0.raw + rva - $0.rva }
        }
        func cString(_ o: Int) -> String? {
            guard o >= 0, o < data.count else { return nil }
            var end = o
            while end < data.count, end - o < 260, data[end] != 0 { end += 1 }
            return String(bytes: data[o..<end], encoding: .ascii)?.lowercased()
        }
        var names = Set<String>()
        // Import (entry 1, 20 bytes each, name at +12) and delay import (entry 13, 32 bytes, name at +4).
        for (entry, size, nameAt) in [(1, 20, 12), (13, 32, 4)] {
            guard let rva = u32(dirs + entry * 8), rva != 0, var at = offset(rva) else { continue }
            for _ in 0..<512 {
                guard let nameRVA = u32(at + nameAt), nameRVA != 0, let nameOffset = offset(nameRVA),
                      let name = cString(nameOffset) else { break }
                names.insert(name)
                at += size
            }
        }
        return (names, is64)
    }

    public static func apis(of names: Set<String>) -> GraphicsAPIs {
        var apis = GraphicsAPIs()
        for name in names {
            switch name {
            case "d3d8.dll": apis.insert(.d3d8)
            case "d3d9.dll": apis.insert(.d3d9)
            case "d3d10.dll", "d3d10core.dll", "d3d10_1.dll": apis.insert(.d3d10)
            case "d3d11.dll": apis.insert(.d3d11)
            case "d3d12.dll", "d3d12core.dll": apis.insert(.d3d12)
            case "vulkan-1.dll": apis.insert(.vulkan)
            case "opengl32.dll": apis.insert(.opengl)
            case "ddraw.dll": apis.insert(.ddraw)
            default: break
            }
        }
        return apis
    }
}

public struct AutoRenderer: Equatable, Sendable {
    public let renderer: RendererChoice
    /// Why, for the panel ("Auto: DXMT (Direct3D 11)") and the log.
    public let reason: String
}

public enum RendererAuto {
    /// What a game's folder links: the executables first, then DLLs beside and below them
    /// (a depth of three, at most 400 files); a game's own DLL can carry the API.
    public static func scan(gameFolder: URL, executables: [String]) -> (apis: GraphicsAPIs, has32bit: Bool, files: Int) {
        let fm = FileManager.default
        var apis = GraphicsAPIs(), has32 = false, count = 0
        func take(_ url: URL) {
            guard count < 400, let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                  let (names, is64) = PEImports.read(data) else { return }
            count += 1
            apis.formUnion(PEImports.apis(of: names))
            if !is64 { has32 = true }
        }
        let root = gameFolder.resolvingSymlinksInPath()
        let wanted = Set(executables.map { $0.lowercased() })
        let base = root.path.count
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                         options: [.skipsHiddenFiles]) else { return (apis, has32, count) }
        var others: [URL] = []
        for case let url as URL in walker {
            guard url.path.count > base, url.pathComponents.count - root.pathComponents.count <= 4 else { walker.skipDescendants(); continue }
            let ext = url.pathExtension.lowercased(), name = url.lastPathComponent.lowercased()
            if wanted.contains(name) { take(url) } else if ext == "dll" || ext == "exe" { others.append(url) }
        }
        for url in others.prefix(400) { take(url) }
        return (apis, has32, count)
    }

    /// The renderer for a game nobody chose a renderer for. nil: nothing to go on (the default stays).
    public static func choose(apis: GraphicsAPIs, has32bit: Bool, d3dmetalAvailable: Bool) -> AutoRenderer? {
        if apis.contains(.d3d12) {
            return d3dmetalAvailable
                ? AutoRenderer(renderer: .d3dmetal, reason: "Direct3D 12")
                : AutoRenderer(renderer: .dxmt, reason: "Direct3D 12, but Apple's Game Porting Toolkit is not added")
        }
        if apis.contains(.d3d11) || apis.contains(.d3d10) { return AutoRenderer(renderer: .dxmt, reason: "Direct3D 11") }
        if apis.contains(.d3d9) || apis.contains(.d3d8) || apis.contains(.ddraw) {
            return AutoRenderer(renderer: .wined3d, reason: "Direct3D 9 or older")
        }
        return nil
    }
}
