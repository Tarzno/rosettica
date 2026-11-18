// Verification harness for dist/Rosettica.saver: loads the bundle the same
// way the screensaver engine does (NSBundle + principal class +
// initWithFrame:isPreview:), steps two independent instances frame by frame
// like a two-monitor setup, and snapshots them to PNGs — all without needing
// a window or screen-recording permissions.
//
// Usage: swift Scripts/saver-harness.swift <path-to-.saver> <output-dir>

import AppKit
import ObjectiveC
import ScreenSaver

let args = CommandLine.arguments
guard args.count == 3 else {
    fatalError("usage: saver-harness <path-to-.saver> <output-dir>")
}

guard let bundle = Bundle(path: args[1]), bundle.load(),
      let principal = bundle.principalClass else {
    fatalError("failed to load \(args[1])")
}
print("Loaded principal class: \(NSStringFromClass(principal))")

// The principal class is only known at runtime, and Swift refuses to call a
// non-required initializer on a metatype — go through the ObjC runtime, which
// is exactly what legacyScreenSaver does.
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

let outDir = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func step(_ view: ScreenSaverView, frames: Int) {
    for _ in 0..<frames {
        view.animateOneFrame()
    }
}

func snapshot(_ view: ScreenSaverView, name: String) {
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        fatalError("no bitmap rep for \(name)")
    }
    view.cacheDisplay(in: view.bounds, to: rep)
    let url = outDir.appendingPathComponent(name)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.path)")
}

// Two instances at 30 fps = one simulated two-monitor setup.
let screen1 = makeView(width: 1280, height: 800)
let screen2 = makeView(width: 1280, height: 800)

step(screen1, frames: 100)          // ~3.3 s: first layer mid-draw, cog rolling
snapshot(screen1, name: "screen1-early.png")
step(screen2, frames: 100)
snapshot(screen2, name: "screen2-early.png")

step(screen1, frames: 1400)         // ~50 s: several layers stamped
snapshot(screen1, name: "screen1-late.png")
step(screen1, frames: 1500)         // ~100 s: likely into the next composition
snapshot(screen1, name: "screen1-later.png")
print("done")
