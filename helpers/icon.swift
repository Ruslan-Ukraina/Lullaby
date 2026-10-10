// Lullaby's app icon: the owner's art (app/Icon/lullaby-1024.png, 10.10.2026) as an Icon
// Composer document that actool compiles (make icon).
//
//     icon <art.png> <output.icon>
//
// The art comes rounded, with a light rim. macOS 26 draws its own shape over a full-bleed
// square, so the rim is cut off and everything outside the art's rounded body takes the
// colour of the nearest pixel toward the centre; the system mask then trims the corners.
// One layer, no glass effects of the system on top: the art has its own.
// (The earlier generated orbit icon is in git history.)

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write("usage: icon <art.png> <output.icon>\n".data(using: .utf8)!)
    exit(2)
}

let inset = 14
let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil)!
let img = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let n = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n*4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
// 1. The art at full size; everything outside its rounded body minus the rim is filled.
ctx.draw(img, in: CGRect(x: 0, y: 0, width: n, height: n))
let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
let radius = 250.0, lo = Double(inset), hi = Double(n - 1 - inset)
func inside(_ x: Int, _ y: Int) -> Bool {
    let fx = Double(x), fy = Double(y)
    guard fx >= lo, fx <= hi, fy >= lo, fy <= hi else { return false }
    let cx = min(max(fx, lo + radius), hi - radius), cy = min(max(fy, lo + radius), hi - radius)
    return (fx - cx) * (fx - cx) + (fy - cy) * (fy - cy) <= radius * radius
}
let c = Double(n - 1) / 2
var copy = [UInt8](UnsafeBufferPointer(start: p, count: n * n * 4))
for y in 0..<n { for x in 0..<n where !inside(x, y) {
    var t = 0.0, xx = x, yy = y
    while t < 1, !inside(xx, yy) {
        t += 0.001
        xx = Int((Double(x) + (c - Double(x)) * t).rounded()); yy = Int((Double(y) + (c - Double(y)) * t).rounded())
    }
    let i = (y * n + x) * 4, j = (yy * n + xx) * 4
    for k in 0..<3 { copy[i + k] = p[j + k] }; copy[i + 3] = 255
}}
// 2. Crop the rim away and scale back to 1024.
let filled = CGContext(data: &copy, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n*4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
let cropped = filled.cropping(to: CGRect(x: inset, y: inset, width: n - 2*inset, height: n - 2*inset))!
ctx.clear(CGRect(x: 0, y: 0, width: n, height: n))
ctx.interpolationQuality = .high
ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: n, height: n))
let out = ctx.makeImage()!

let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let assets = root.appendingPathComponent("Assets", isDirectory: true)
try? FileManager.default.removeItem(at: root)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
let layer = "lullaby.png"
let dest = CGImageDestinationCreateWithURL(
    assets.appendingPathComponent(layer) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, out, nil)
guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }

let document: [String: Any] = [
    "fill": ["solid": "srgb:0.45882,0.59608,0.86275,1.00000"],
    "groups": [[
        "layers": [["image-name": layer, "name": "Lullaby"]],
        "shadow": ["kind": "none", "opacity": 0],
        "translucency": ["enabled": false, "value": 0],
    ]],
    "supported-platforms": ["squares": "shared"],
]
try JSONSerialization
    .data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    .write(to: root.appendingPathComponent("icon.json"))
