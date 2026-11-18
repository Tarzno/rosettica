// Stress and resource test for dist/Rosettica.saver: loads the bundle like
// the screensaver engine does, then
//   1. runs a long simulated session at full-screen Retina size, measuring
//      per-frame CPU cost, redraw duty cycle, and memory footprint drift,
//   2. verifies that a "screensaver did stop" distributed notification makes
//      the view do (almost) zero work and release its bitmap after ~10 s,
//   3. verifies that stopAnimation releases resources and the view recovers,
//   4. checks degenerate view sizes don't crash or spin.
//
// Usage: swift Scripts/saver-stress.swift <path-to-.saver> [simulated-minutes]

import AppKit
import Darwin
import ObjectiveC
import ScreenSaver

let args = CommandLine.arguments
guard args.count >= 2 else {
    fatalError("usage: saver-stress <path-to-.saver> [simulated-minutes]")
}
let simulatedMinutes = args.count >= 3 ? Double(args[2]) ?? 5 : 5

guard let bundle = Bundle(path: args[1]), bundle.load(),
      let principal = bundle.principalClass else {
    fatalError("failed to load \(args[1])")
}
print("Loaded principal class: \(NSStringFromClass(principal))")

func makeView(width: CGFloat, height: CGFloat) -> ScreenSaverView {
    let allocSel = NSSelectorFromString("alloc")
    let allocIMP = method_getImplementation(class_getClassMethod(principal, allocSel)!)
    typealias AllocFn = @convention(c) (AnyClass, Selector) -> AnyObject
    let instance = unsafeBitCast(allocIMP, to: AllocFn.self)(principal, allocSel)

    let initSel = NSSelectorFromString("initWithFrame:isPreview:")
    let initIMP = class_getMethodImplementation(principal, initSel)!
    typealias InitFn = @convention(c) (AnyObject, Selector, NSRect, Bool) -> AnyObject?
    let rect = NSRect(x: 0, y: 0, width: width, height: height)
    guard let view = unsafeBitCast(initIMP, to: InitFn.self)(instance, initSel, rect, false) as? ScreenSaverView else {
        fatalError("initWithFrame:isPreview: returned nil or a non-ScreenSaverView")
    }
    return view
}

func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) /
        mach_msg_type_number_t(MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return -1 }
    return Double(info.phys_footprint) / 1_048_576
}

let width: CGFloat = 2560
let height: CGFloat = 1440
let scale: CGFloat = 2
let view = makeView(width: width, height: height)

// AppKit ignores -setNeedsDisplayInRect: on views that are not in a window,
// so intercept it at the runtime level to observe the saver's redraw
// requests (the host's window makes this work for real).
var redrawRequested = false
var requestedRect = CGRect.null
let sndSel = NSSelectorFromString("setNeedsDisplayInRect:")
let sndMethod = class_getInstanceMethod(principal, sndSel)!
let sndBlock: @convention(block) (AnyObject, NSRect) -> Void = { _, rect in
    redrawRequested = true
    requestedRect = requestedRect.union(rect)
}
method_setImplementation(sndMethod, imp_implementationWithBlock(sndBlock))

// Offscreen Retina render target so draw(_:) runs its real full-screen path.
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = NSSize(width: width, height: height)
let gctx = NSGraphicsContext(bitmapImageRep: rep)!

// ---- 1. Long simulated session --------------------------------------------
print("\n== 1. Simulated session: \(simulatedMinutes) min at 30 fps, \(Int(width))x\(Int(height))@\(Int(scale))x ==")
view.startAnimation()
let frames = Int(simulatedMinutes * 60 * 30)
var advanceTime = 0.0
var drawTime = 0.0
var maxFrame = 0.0
var drawCount = 0
let startFootprint = footprintMB()

var dirtyArea = 0.0
NSGraphicsContext.current = gctx
for _ in 0..<frames {
    autoreleasepool {
        redrawRequested = false
        requestedRect = .null
        let t0 = CFAbsoluteTimeGetCurrent()
        view.animateOneFrame()
        let t1 = CFAbsoluteTimeGetCurrent()
        var t2 = t1
        if redrawRequested {
            // Draw only the invalidated region, exactly like the host does.
            let rect = requestedRect.intersection(view.bounds)
            view.draw(rect)
            drawCount += 1
            dirtyArea += rect.width * rect.height
            t2 = CFAbsoluteTimeGetCurrent()
            drawTime += t2 - t1
        }
        advanceTime += t1 - t0
        maxFrame = max(maxFrame, t2 - t0)
    }
}
NSGraphicsContext.current = nil
let endFootprint = footprintMB()

let simSeconds = Double(frames) / 30.0
let work = advanceTime + drawTime
let f = { (x: Double) in String(format: "%.2f", x) }
print("frames: \(frames) (\(f(simSeconds)) simulated s), redraws: \(drawCount) (\(f(Double(drawCount) / Double(frames) * 100))% duty cycle)")
print("advance: \(f(advanceTime)) s total, draw: \(f(drawTime)) s total, worst frame: \(f(maxFrame * 1000)) ms")
print("estimated CPU while visible: \(f(work / simSeconds * 100))% of one core per screen")
if drawCount > 0 {
    let avgFrac = dirtyArea / Double(drawCount) / (Double(width) * Double(height))
    print("avg dirty region: \(f(avgFrac * 100))% of the screen, avg draw: \(f(drawTime / Double(drawCount) * 1000)) ms")
}
print("memory footprint: \(f(startFootprint)) MB -> \(f(endFootprint)) MB")

// ---- 2. After "screensaver stopped", the view must idle -------------------
print("\n== 2. Paused after didstop notification ==")

// The saver gates on the real com.apple.screensaver.* distributed
// notifications; post them and pump the runloop so they get delivered.
func post(_ name: String) {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name(name), object: nil, userInfo: nil, deliverImmediately: true)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0))
}

let beforeHidden = footprintMB()
post("com.apple.screensaver.didstop")
let h0 = CFAbsoluteTimeGetCurrent()
redrawRequested = false
for _ in 0..<400 {                       // > releaseAfterSkippedFrames (300)
    view.animateOneFrame()
}
let hiddenTime = CFAbsoluteTimeGetCurrent() - h0
let afterHidden = footprintMB()
print("400 paused frames took \(f(hiddenTime * 1000)) ms total, redraw requested: \(redrawRequested)")
print("memory footprint: \(f(beforeHidden)) MB -> \(f(afterHidden)) MB (bitmap released: \(beforeHidden - afterHidden > 20 ? "YES" : "NO"))")

post("com.apple.screensaver.didstart")
NSGraphicsContext.current = gctx
var resumedRedraws = 0
for _ in 0..<60 {
    redrawRequested = false
    view.animateOneFrame()
    if redrawRequested {
        view.draw(view.bounds)
        resumedRedraws += 1
    }
}
NSGraphicsContext.current = nil
print("after didstart, 60 frames produced \(resumedRedraws) redraws (resumed: \(resumedRedraws > 0 ? "YES" : "NO"))")

// ---- 3. stopAnimation must release resources ------------------------------
print("\n== 3. stopAnimation ==")
let beforeStop = footprintMB()
view.stopAnimation()
let afterStop = footprintMB()
print("memory footprint: \(f(beforeStop)) MB -> \(f(afterStop)) MB (released: \(beforeStop - afterStop > 10 ? "YES" : "NO"))")
view.startAnimation()
NSGraphicsContext.current = gctx
var restartRedraws = 0
for _ in 0..<60 {
    redrawRequested = false
    view.animateOneFrame()
    if redrawRequested {
        view.draw(view.bounds)
        restartRedraws += 1
    }
}
NSGraphicsContext.current = nil
print("after restart, 60 frames produced \(restartRedraws) redraws (recovered: \(restartRedraws > 0 ? "YES" : "NO"))")

// ---- 4. Degenerate sizes --------------------------------------------------
print("\n== 4. Degenerate sizes ==")
view.setFrameSize(.zero)
for _ in 0..<10 { view.animateOneFrame() }
view.setFrameSize(NSSize(width: 5, height: 5))
for _ in 0..<10 { view.animateOneFrame() }
view.setFrameSize(NSSize(width: width, height: height))
for _ in 0..<30 { view.animateOneFrame() }
view.stopAnimation()
print("zero-size, 5x5, and restored full size: no crash, no spin")

print("\ndone")

// Dump the accumulated render target so the incremental (cropped) draw path
// can be inspected visually.
if let data = rep.representation(using: .png, properties: [:]) {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("saver-stress-target.png")
    try? data.write(to: url)
    print("render target written to \(url.path)")
}
