// Makes a game's .icns in Lullaby's look: the macOS icon body (824 in a 1024 square, the shape of
// native icons) with the glass rim of Lullaby's own icon, and a soft shadow.
//
// Usage: iconmaker <input-image|input.exe> <output.icns> [--alt <other input>]... [--png preview.png]
// With --alt, every input is read and the one with the most pixels is used (the first on a tie): a
// game's own icon is often bigger than the 48 px one Steam publishes.
//
// Two kinds of input are told apart by the edge of the picture:
//  - art that fills its square (a capsule, a photo, an icon with a coloured backdrop): scaled to
//    cover the body;
//  - a logo on a transparent background: scaled down to ~70 % and set on a solid fill of the logo's
//    main colour (moved toward light or dark when the logo would not stand out from it).
// The rim is the one measured on the system's own rendering of Lullaby's icon (macOS 27): a bright
// specular edge along the top that fades within ~30 px of 1024, a weaker one along the bottom, and a
// thin dark edge on the sides. One master is drawn at 1024 and scaled down for the other sizes, and
// the .icns is written directly (PNG entries), so a run takes tens of milliseconds.
//
// Bump `styleVersion` when the look changes: compat_run.sh keys its cached icons on it.

import AppKit
import Foundation

let styleVersion = 2   // keep in step with icon_style in compat_run.sh

let arguments = Array(CommandLine.arguments.dropFirst())
var positional: [String] = []
var alternatives: [String] = []
var previewPath: String?
var argIndex = 0
while argIndex < arguments.count {
    switch arguments[argIndex] {
    case "--alt", "--png":
        guard argIndex + 1 < arguments.count else { fputs("iconmaker: \(arguments[argIndex]) needs a path\n", stderr); exit(1) }
        if arguments[argIndex] == "--alt" { alternatives.append(arguments[argIndex + 1]) } else { previewPath = arguments[argIndex + 1] }
        argIndex += 2
    default:
        positional.append(arguments[argIndex])
        argIndex += 1
    }
}
guard positional.count == 2 else {
    fputs("usage: iconmaker <input-image|input.exe> <output.icns> [--alt <other input>]... [--png preview.png]\n", stderr)
    exit(1)
}
let inputPath = positional[0]
let outputPath = positional[1]

// MARK: - Loading

private func loadImage(_ path: String) -> CGImage? {
    var image: NSImage?
    var length = 0
    if let raw = lb_pe_icon_ico(path, &length) {
        let ico = Data(bytesNoCopy: raw, count: length, deallocator: .free)
        if !ico.isEmpty, let found = NSImage(data: ico) {
            FileHandle.standardError.write(Data("iconmaker: using icon from PE resources\n".utf8))
            image = found
        }
    }
    if image == nil { image = NSImage(contentsOfFile: path) }
    guard let image else { return nil }
    // The largest bitmap an .ico or .icns offers.
    let best = image.representations.compactMap { $0 as? NSBitmapImageRep }.max { $0.pixelsWide < $1.pixelsWide }
    if let best, let cg = best.cgImage, cg.width > 0, cg.height > 0 { return cg }
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

var source: CGImage?
for path in [inputPath] + alternatives {
    guard let candidate = loadImage(path) else { continue }
    if let best = source, candidate.width * candidate.height <= best.width * best.height { continue }
    source = candidate
}
guard let source else {
    fputs("iconmaker: cannot read \(inputPath)\n", stderr)
    exit(1)
}

// MARK: - Looking at the picture (a 48 x 48 copy is enough)

private let probe = 48

private func samplePixels(_ image: CGImage) -> [UInt8] {
    var px = [UInt8](repeating: 0, count: probe * probe * 4)
    let space = CGColorSpaceCreateDeviceRGB()
    px.withUnsafeMutableBytes { buffer in
        guard let ctx = CGContext(data: buffer.baseAddress, width: probe, height: probe, bitsPerComponent: 8,
                                  bytesPerRow: probe * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: probe, height: probe))
    }
    return px
}

private struct Color { var r: Double, g: Double, b: Double }

private func luminance(_ c: Color) -> Double { 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }

private func hsv(_ c: Color) -> (h: Double, s: Double, v: Double) {
    let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b), d = mx - mn
    var h = 0.0
    if d > 0 {
        if mx == c.r { h = ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6) }
        else if mx == c.g { h = (c.b - c.r) / d + 2 }
        else { h = (c.r - c.g) / d + 4 }
        h /= 6
        if h < 0 { h += 1 }
    }
    return (h, mx == 0 ? 0 : d / mx, mx)
}

private func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
    Color(r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t)
}

private struct Look {
    var logoOnTransparent: Bool
    var background: Color
}

private func look(at image: CGImage) -> Look {
    let px = samplePixels(image)
    func pixel(_ x: Int, _ y: Int) -> (c: Color, a: Double) {
        let i = (y * probe + x) * 4
        let a = Double(px[i + 3]) / 255
        guard a > 0.001 else { return (Color(r: 0, g: 0, b: 0), 0) }
        return (Color(r: Double(px[i]) / 255 / a, g: Double(px[i + 1]) / 255 / a, b: Double(px[i + 2]) / 255 / a), a)
    }

    // The border: transparent all along means a logo; transparent only in the corners is a picture
    // someone rounded, which is not.
    var borderTotal = 0, borderClear = 0
    var edge = Color(r: 0, g: 0, b: 0), edgeCount = 0.0
    for i in 0..<probe {
        for (x, y) in [(i, 0), (i, probe - 1), (0, i), (probe - 1, i)] {
            borderTotal += 1
            let (c, a) = pixel(x, y)
            if a < 0.25 { borderClear += 1 }
            else if a > 0.9 { edge.r += c.r; edge.g += c.g; edge.b += c.b; edgeCount += 1 }
        }
    }
    let logo = Double(borderClear) / Double(borderTotal) > 0.6

    // The logo's main colour: the fullest bucket of hue, saturation and value, weighted toward colour.
    var weight = [Double](repeating: 0, count: 18 * 3 * 3)
    var sum = [Color](repeating: Color(r: 0, g: 0, b: 0), count: 18 * 3 * 3)
    var mean = Color(r: 0, g: 0, b: 0), meanWeight = 0.0
    for y in 0..<probe {
        for x in 0..<probe {
            let (c, a) = pixel(x, y)
            guard a > 0.6 else { continue }
            let (h, s, v) = hsv(c)
            let bucket = (min(17, Int(h * 18)) * 3 + min(2, Int(s * 3))) * 3 + min(2, Int(v * 3))
            let w = a * (0.25 + s)
            weight[bucket] += w
            sum[bucket].r += c.r * w; sum[bucket].g += c.g * w; sum[bucket].b += c.b * w
            mean.r += c.r * a; mean.g += c.g * a; mean.b += c.b * a
            meanWeight += a
        }
    }
    guard meanWeight > 0 else { return Look(logoOnTransparent: logo, background: Color(r: 0.2, g: 0.2, b: 0.25)) }
    mean = Color(r: mean.r / meanWeight, g: mean.g / meanWeight, b: mean.b / meanWeight)

    if !logo {
        // A picture fills the body; what shows where it was rounded or short is its own edge colour.
        let bg = edgeCount > 0 ? Color(r: edge.r / edgeCount, g: edge.g / edgeCount, b: edge.b / edgeCount) : mean
        return Look(logoOnTransparent: false, background: bg)
    }

    var best = 0
    for i in weight.indices where weight[i] > weight[best] { best = i }
    var bg = weight[best] > 0
        ? Color(r: sum[best].r / weight[best], g: sum[best].g / weight[best], b: sum[best].b / weight[best]) : mean

    // The logo has to stand out from its own colour: move the fill toward the side the logo is not on.
    let logoLuma = luminance(mean)
    var steps = 0
    while abs(luminance(bg) - logoLuma) < 0.28 && steps < 8 {
        bg = logoLuma >= 0.5 ? mix(bg, Color(r: 0, g: 0, b: 0), 0.18) : mix(bg, Color(r: 1, g: 1, b: 1), 0.18)
        steps += 1
    }
    return Look(logoOnTransparent: true, background: bg)
}

// MARK: - The master at 1024

private let canvas = 1024
private let bodySide = 824.0
private let bodyOrigin = 100.0
/// Where the body's outline lies in each of its first 413 rows (row 0 is the top of the 824 px body): the
/// distance from the left edge, in pixels. Read off the 1024 px rendering macOS 27 gives Lullaby's icon,
/// averaged over its four sides; the shape is the system's own, which is not a plain superellipse. Below
/// row 412 the sides are straight.
private let outlineLeft: [Double] = [
    249.3, 222.9, 208.1, 197.5, 189.1, 181.6, 175.5, 169.7, 164.8, 159.9, 155.7, 151.7, 147.7, 144.2, 140.8, 137.4,
    134.5, 132.1, 129.7, 127.3, 124.9, 122.5, 120.1, 118.1, 116.1, 114.2, 112.3, 110.4, 108.5, 106.5, 104.6, 102.9,
    101.4, 99.8, 98.3, 96.7, 95.2, 93.5, 92.0, 90.4, 88.9, 87.6, 86.4, 85.1, 83.7, 82.4, 81.2, 79.8,
    78.5, 77.2, 75.9, 74.7, 73.6, 72.6, 71.5, 70.4, 69.3, 68.3, 67.2, 66.1, 65.0, 63.9, 62.8, 61.9,
    61.0, 60.1, 59.2, 58.3, 57.3, 56.4, 55.5, 54.5, 53.6, 52.7, 51.7, 50.9, 50.2, 49.4, 48.6, 47.8,
    47.2, 46.3, 45.5, 44.7, 44.1, 43.3, 42.5, 41.6, 40.9, 40.3, 39.6, 39.0, 38.4, 37.6, 37.1, 36.5,
    35.7, 35.2, 34.5, 33.8, 33.3, 32.5, 32.0, 31.4, 30.7, 30.3, 29.7, 29.3, 28.6, 28.3, 27.6, 27.2,
    26.5, 26.2, 25.5, 25.1, 24.5, 24.0, 23.5, 23.1, 22.5, 22.3, 21.7, 21.4, 20.9, 20.5, 20.2, 19.6,
    19.3, 18.8, 18.5, 18.1, 17.5, 17.3, 16.7, 16.4, 16.2, 15.7, 15.5, 15.3, 14.9, 14.6, 14.4, 14.1,
    13.7, 13.5, 13.3, 12.9, 12.6, 12.4, 12.2, 11.9, 11.6, 11.4, 11.2, 10.9, 10.6, 10.5, 10.3, 10.0,
    9.7, 9.5, 9.4, 9.2, 8.9, 8.6, 8.5, 8.4, 8.2, 7.9, 7.6, 7.5, 7.4, 7.3, 7.1, 6.8,
    6.6, 6.5, 6.4, 6.3, 6.2, 5.9, 5.7, 5.6, 5.5, 5.4, 5.3, 5.2, 5.0, 4.8, 4.6, 4.5,
    4.5, 4.4, 4.3, 4.2, 4.1, 3.9, 3.8, 3.6, 3.6, 3.5, 3.5, 3.4, 3.3, 3.3, 3.2, 3.0,
    2.8, 2.8, 2.7, 2.6, 2.6, 2.5, 2.5, 2.4, 2.4, 2.4, 2.3, 2.2, 2.2, 2.1, 2.0, 1.9,
    1.8, 1.8, 1.7, 1.6, 1.6, 1.6, 1.5, 1.5, 1.5, 1.5, 1.4, 1.4, 1.4, 1.4, 1.3, 1.3,
    1.3, 1.3, 1.2, 1.2, 1.2, 1.1, 1.1, 1.1, 1.0, 1.0, 0.9, 0.9, 0.8, 0.8, 0.8, 0.7,
    0.7, 0.7, 0.7, 0.7, 0.7, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.6, 0.5, 0.5, 0.5, 0.5,
    0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5,
    0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4,
    0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4,
    0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4,
    0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4,
    0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4,
    0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4,
    0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4,
    0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4, 0.4,
]

private func cg(_ c: Color, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: a)
}

/// The body's outline as a polygon, in the canvas's coordinates (y up), from the table by symmetry.
private func bodyPath() -> CGPath {
    let side = bodySide, o = bodyOrigin
    func pt(_ x: Double, _ yDown: Double) -> CGPoint { CGPoint(x: o + x, y: o + side - yDown) }
    let path = CGMutablePath()
    path.move(to: pt(side / 2, 0))
    for r in 0...412 { path.addLine(to: pt(outlineLeft[r], Double(r))) }                    // top-left corner, down the left
    for r in stride(from: 412, through: 0, by: -1) { path.addLine(to: pt(outlineLeft[r], side - Double(r))) }   // bottom-left
    path.addLine(to: pt(side / 2, side))
    for r in 0...412 { path.addLine(to: pt(side - outlineLeft[r], side - Double(r))) }      // bottom-right
    for r in stride(from: 412, through: 0, by: -1) { path.addLine(to: pt(side - outlineLeft[r], Double(r))) }  // top-right
    path.closeSubpath()
    return path
}

private func renderMaster(_ image: CGImage, _ look: Look) -> CGImage? {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: canvas * 4,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    let path = bodyPath()

    // Shadow with the fill: soft, a little lower than the body, as native icons carry it.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.32))
    ctx.addPath(path)
    ctx.setFillColor(cg(look.background))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let w = Double(image.width), h = Double(image.height)
    let fit: Double
    if look.logoOnTransparent {
        let box = bodySide * 0.70
        fit = min(box / w, box / h)
    } else {
        fit = max(bodySide / w, bodySide / h)
    }
    let dw = w * fit, dh = h * fit
    ctx.draw(image, in: CGRect(x: bodyOrigin + (bodySide - dw) / 2, y: bodyOrigin + (bodySide - dh) / 2, width: dw, height: dh))
    ctx.restoreGState()

    glassRim(ctx, path)
    return ctx.makeImage()
}

/// How far inside the outline each pixel of the body is, in pixels: a 3-4 chamfer distance, then smoothed
/// so the direction taken from it has no steps.
private func insideDistance(_ path: CGPath) -> [Float] {
    let n = canvas
    var mask = [UInt8](repeating: 0, count: n * n)
    mask.withUnsafeMutableBytes { buffer in
        guard let ctx = CGContext(data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
        ctx.addPath(path)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fillPath()
    }
    let big: Int32 = 1 << 20
    var d = [Int32](repeating: 0, count: n * n)
    for i in 0..<(n * n) { d[i] = mask[i] >= 128 ? big : 0 }
    for y in 0..<n {
        for x in 0..<n {
            let i = y * n + x
            if d[i] == 0 { continue }
            var v = d[i]
            if x > 0 { v = min(v, d[i - 1] + 3) }
            if y > 0 {
                v = min(v, d[i - n] + 3)
                if x > 0 { v = min(v, d[i - n - 1] + 4) }
                if x < n - 1 { v = min(v, d[i - n + 1] + 4) }
            }
            d[i] = v
        }
    }
    for y in stride(from: n - 1, through: 0, by: -1) {
        for x in stride(from: n - 1, through: 0, by: -1) {
            let i = y * n + x
            if d[i] == 0 { continue }
            var v = d[i]
            if x < n - 1 { v = min(v, d[i + 1] + 3) }
            if y < n - 1 {
                v = min(v, d[i + n] + 3)
                if x < n - 1 { v = min(v, d[i + n + 1] + 4) }
                if x > 0 { v = min(v, d[i + n - 1] + 4) }
            }
            d[i] = v
        }
    }
    // A box blur, 9 wide, in each direction, over the body's band only.
    var f = d.map { Float($0) / 3 }
    var tmp = f
    let r = 4
    for y in 0..<n {
        for x in r..<(n - r) {
            var sum: Float = 0
            for k in -r...r { sum += f[y * n + x + k] }
            tmp[y * n + x] = sum / Float(2 * r + 1)
        }
    }
    for y in r..<(n - r) {
        for x in 0..<n {
            var sum: Float = 0
            for k in -r...r { sum += tmp[(y + k) * n + x] }
            f[y * n + x] = sum / Float(2 * r + 1)
        }
    }
    return f
}

/// The rim, measured on Lullaby's icon as macOS 27 draws it. Per pixel in a band along the edge, from the
/// distance to the outline and the direction the edge faces (the distance field's gradient):
///  - facing up: white that starts near full strength and fades with e-fold ~6 px;
///  - facing down: the same at 40 %;
///  - facing sideways: a thin dark edge (about 13 %), fading over ~9 px.
private func glassRim(_ ctx: CGContext, _ path: CGPath) {
    guard let data = ctx.data else { return }
    let pixels = data.bindMemory(to: UInt8.self, capacity: canvas * canvas * 4)
    let stride = ctx.bytesPerRow
    let n = canvas
    let dist = insideDistance(path)
    let band: Float = 42
    let lo = Int(bodyOrigin) - 1, hi = Int(bodyOrigin + bodySide) + 1

    for y in lo..<hi {
        for x in lo..<hi {
            let depth = dist[y * n + x] - 0.5
            guard depth > 0, depth < band else { continue }
            // Rows grow downward and the distance grows inward; the edge faces against that gradient.
            let gx = Double(dist[y * n + x + 1] - dist[y * n + x - 1])
            let gy = Double(dist[(y + 1) * n + x] - dist[(y - 1) * n + x])
            let len = (gx * gx + gy * gy).squareRoot()
            guard len > 0.0001 else { continue }
            let nx = -gx / len               // + toward the right
            let ny = gy / len                // + toward the top of the icon

            let t = Double(max(depth - 1.0, 0))
            let lightStrength = ny > 0 ? 0.95 * ny : 0.40 * -ny
            let light = lightStrength * exp(-t / 6.0)
            let dark = 0.13 * abs(nx) * exp(-t / 9.0)

            let i = y * stride + x * 4
            let a = Double(pixels[i + 3]) / 255
            guard a > 0 else { continue }
            for c in 0..<3 {
                var v = Double(pixels[i + c])               // premultiplied: scale the white by alpha too
                v = v * (1 - light) + 255 * a * light
                v *= 1 - dark
                pixels[i + c] = UInt8(max(0, min(255, v.rounded())))
            }
        }
    }
}

// MARK: - Sizes and the .icns

private func png(_ image: CGImage) -> Data? {
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}

private func scaled(_ master: CGImage, to side: Int) -> Data? {
    guard side != canvas else { return png(master) }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(master, in: CGRect(x: 0, y: 0, width: side, height: side))
    guard let image = ctx.makeImage() else { return nil }
    return png(image)
}

private func be32(_ n: Int) -> Data {
    var v = UInt32(n).bigEndian
    return Data(bytes: &v, count: 4)
}

guard let master = renderMaster(source, look(at: source)) else {
    fputs("iconmaker: cannot draw the icon\n", stderr)
    exit(1)
}

if let previewPath, let data = png(master) {
    try? data.write(to: URL(fileURLWithPath: previewPath))
}

// Each pixel size once; the icns entry types that share a size share the PNG.
var encoded: [Int: Data] = [:]
for side in [16, 32, 64, 128, 256, 512, 1024] {
    guard let data = scaled(master, to: side) else {
        fputs("iconmaker: cannot encode \(side) px\n", stderr)
        exit(1)
    }
    encoded[side] = data
}
let entries: [(type: String, side: Int)] = [
    ("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024),
    ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512),
]
var body = Data()
for entry in entries {
    guard let data = encoded[entry.side] else { continue }
    body.append(Data(entry.type.utf8))
    body.append(be32(8 + data.count))
    body.append(data)
}
var file = Data("icns".utf8)
file.append(be32(8 + body.count))
file.append(body)
do {
    try file.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
} catch {
    fputs("iconmaker: cannot write \(outputPath): \(error)\n", stderr)
    exit(1)
}
