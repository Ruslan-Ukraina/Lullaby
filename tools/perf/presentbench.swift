// presentbench: how the display shows frames that are presented unevenly, the way frame generation does:
// a "real" frame, then a "generated" one, every base interval. Each strategy runs a few seconds; the moments
// the frames reached the screen (addPresentedHandler) give the on-screen intervals.
//   presentbench [base_ms] [seconds] [hdr] [full|borderless]   defaults 22.222 (45 real + 45 generated = 90 shown), 6, off, windowed
//   full: native full-screen; borderless: a window of the screen's size above the menu bar
// Strategies:
//   immediate  displaySync on, the generated frame follows the real one at once (what an unpaced FG does)
//   paced      displaySync on, the generated frame waits for half a base interval (a CPU wait before presenting)
//   afterdur   displaySync on, the generated frame is presented with presentDrawable(_:afterMinimumDuration:) = half base
//   atTime     displaySync on, presentDrawable(_:atTime:) for the generated frame at the half-way moment
//   nosync     displaySync off, paced (tearing allowed): shows what the display does without waiting for a refresh
import AppKit
import Metal
import QuartzCore

let baseMs = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 22.222 : 22.222
let seconds = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2]) ?? 6 : 6
let hdr = CommandLine.arguments.contains("hdr")
let fullscreen = CommandLine.arguments.contains("full")
let borderless = CommandLine.arguments.contains("borderless")

func machNow() -> Double { Double(mach_continuous_time()) * 1e-9 * Double(timebase.numer) / Double(timebase.denom) }
var timebase = mach_timebase_info_data_t(); mach_timebase_info(&timebase)
func wait(until t: Double) {
    let now = machNow(); if t <= now { return }
    let coarse = t - 0.0004
    if coarse > now { mach_wait_until(mach_absolute_time() + UInt64((coarse - now) * 1e9 * Double(timebase.denom) / Double(timebase.numer))) }
    while machNow() < t {}
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 560), styleMask: [.titled], backing: .buffered, defer: false)
window.title = "presentbench"
let layer = CAMetalLayer()
let device = MTLCreateSystemDefaultDevice()!
layer.device = device
layer.pixelFormat = hdr ? .rgba16Float : .bgra8Unorm
if hdr {
    layer.wantsExtendedDynamicRangeContent = true
    layer.colorspace = CGColorSpace(name: CGColorSpace.itur_2100_PQ)
}
layer.drawableSize = CGSize(width: 1800, height: 1120)
layer.maximumDrawableCount = 3
window.contentView!.wantsLayer = true
window.contentView!.layer = layer
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)
if fullscreen { window.collectionBehavior = [.fullScreenPrimary]; window.toggleFullScreen(nil) }
if borderless {
    window.styleMask = [.borderless]
    window.level = .mainMenu + 1
    window.setFrame(NSScreen.main!.frame, display: true)
    layer.drawableSize = CGSize(width: NSScreen.main!.frame.width * 2, height: NSScreen.main!.frame.height * 2)
}
let queue = device.makeCommandQueue()!

struct Result { var name: String; var intervals: [Double] }
var results: [Result] = []

func run(_ name: String, sync: Bool, mode: String) {
    layer.displaySyncEnabled = sync
    var presented: [Double] = []
    let lock = NSLock()
    let base = baseMs / 1000
    var tNext = machNow() + 0.3
    let end = tNext + seconds
    var n = 0
    func frame(color: Double, then present: (MTLCommandBuffer, CAMetalDrawable) -> Void) {
        guard let drawable = layer.nextDrawable(), let cb = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: color, green: 0.2, blue: 1 - color, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        cb.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        drawable.addPresentedHandler { d in
            if d.presentedTime > 0 { lock.lock(); presented.append(d.presentedTime); lock.unlock() }
        }
        present(cb, drawable)
        cb.commit()
    }
    while tNext < end {
        wait(until: tNext)
        let c = Double(n % 2)
        n += 1
        frame(color: c) { cb, d in cb.present(d) }                       // the real frame
        let half = tNext + base / 2
        switch mode {
        case "immediate": frame(color: 1 - c) { cb, d in cb.present(d) }
        case "paced", "nosync": wait(until: half); frame(color: 1 - c) { cb, d in cb.present(d) }
        case "exact", "exactnosync":
            // the generated frame is encoded first and only committed at the exact moment
            guard let d2 = layer.nextDrawable(), let cb2 = queue.makeCommandBuffer() else { break }
            let pass2 = MTLRenderPassDescriptor()
            pass2.colorAttachments[0].texture = d2.texture
            pass2.colorAttachments[0].loadAction = .clear
            pass2.colorAttachments[0].clearColor = MTLClearColor(red: 1 - c, green: 0.2, blue: c, alpha: 1)
            pass2.colorAttachments[0].storeAction = .store
            cb2.makeRenderCommandEncoder(descriptor: pass2)?.endEncoding()
            d2.addPresentedHandler { d in if d.presentedTime > 0 { lock.lock(); presented.append(d.presentedTime); lock.unlock() } }
            cb2.present(d2)
            wait(until: half)
            cb2.commit()
        case "afterdur": frame(color: 1 - c) { cb, d in cb.present(d, afterMinimumDuration: base / 2) }
        case "atTime":
            frame(color: 1 - c) { cb, d in
                cb.present(d, atTime: CACurrentMediaTime() + max(0, half - machNow()))
            }
        case "grid240":
            // The real frame was presented at once above; the pacer (below) only decides the generated one.
            break
        default: break
        }
        tNext += base
    }
    Thread.sleep(forTimeInterval: 0.5)
    lock.lock(); let times = presented.sorted(); lock.unlock()
    let intervals = zip(times.dropFirst(), times).map { ($0 - $1) * 1000 }
    results.append(Result(name: name, intervals: intervals))
}

/// Every present (real and generated alike, arriving back to back) is scheduled with presentDrawable(_:atTime:) on a
/// 240 Hz grid so that the average interval is base/2 and the intervals alternate between neighbouring grid steps.
func runGrid(_ name: String, sync: Bool) {
    layer.displaySyncEnabled = sync
    var presented: [Double] = []
    let lock = NSLock()
    let unit = 1.0 / 240, step = baseMs / 2000
    let off = CACurrentMediaTime() - machNow()
    var ideal = machNow() + 0.4
    var last = ideal - step
    let end = ideal + seconds
    var k = 0
    while ideal < end {
        // arrive "back to back" per pair: wait for the pair's real arrival time, present both with their scheduled times
        wait(until: ideal - 0.004)
        for _ in 0..<2 {
            let wanted = ideal
            let n = max(2, Int(((wanted - last) / unit).rounded()))
            let target = last + Double(n) * unit
            last = target
            guard let d = layer.nextDrawable(), let cb = queue.makeCommandBuffer() else { continue }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = d.texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(k % 2), green: 0.2, blue: 1 - Double(k % 2), alpha: 1)
            pass.colorAttachments[0].storeAction = .store
            cb.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
            d.addPresentedHandler { d in if d.presentedTime > 0 { lock.lock(); presented.append(d.presentedTime); lock.unlock() } }
            cb.present(d, atTime: target + off)
            cb.commit()
            ideal += step
            k += 1
        }
    }
    Thread.sleep(forTimeInterval: 0.5)
    lock.lock(); let times = presented.sorted(); lock.unlock()
    results.append(Result(name: name, intervals: zip(times.dropFirst(), times).map { ($0 - $1) * 1000 }))
}

DispatchQueue.global().async {
    Thread.sleep(forTimeInterval: (fullscreen || borderless) ? 3.0 : 1.0)
    for (name, sync, mode) in [("immediate", true, "immediate"), ("paced", true, "paced"), ("afterdur", true, "afterdur"),
                               ("atTime", true, "atTime"), ("nosync", false, "nosync"),
                               ("exact", true, "exact"), ("exactnosync", false, "exactnosync")] {
        run(name, sync: sync, mode: mode)
    }
    runGrid("grid240", sync: true)
    runGrid("grid240-nosync", sync: false)
    print("presentbench base \(baseMs) ms (\(String(format: "%.1f", 2000 / baseMs)) shown per second wanted), hdr \(hdr)")
    print("strategy    shown  mean    p50     p95     p99     max     std   | intervals under 40 percent of the base over")
    for r in results {
        let v = r.intervals.sorted(); guard v.count > 10 else { print(r.name, "no data"); continue }
        let mean = v.reduce(0, +) / Double(v.count)
        let std = (v.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(v.count)).squareRoot()
        func q(_ p: Double) -> Double { v[min(v.count - 1, Int(Double(v.count) * p))] }
        print(String(format: "%-11@ %5d %6.2f %6.2f %6.2f %6.2f %6.2f %6.2f", r.name as NSString, v.count, mean, q(0.5), q(0.95), q(0.99), v.last!, std))
    }
    exit(0)
}
app.run()
