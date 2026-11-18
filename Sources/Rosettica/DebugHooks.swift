import AppKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import RosetticaCore

/// Environment-variable hooks used for automated verification; inert in
/// normal use.
///
/// - `ROSETTICA_DEMO=1`             — load a demo pattern into the fresh document
/// - `ROSETTICA_EXPORT_PATH=<file>` — write the pattern via the print/export
///                                renderer to a PNG
/// - `ROSETTICA_EXPORT_SVG_PATH=<file>`, `ROSETTICA_EXPORT_PDF_PATH=<file>`
///                              — write the pattern as SVG / PDF
/// - `ROSETTICA_SNAPSHOT_PATH=<f>`  — after 2.5 s, snapshot the main window's
///                                content view to a PNG and quit
@MainActor
enum DebugHooks {
    static let demoPattern = RosettePattern(
        background: RGBAColor(red: 0.99, green: 0.97, blue: 0.92),
        layers: [
            RosetteLayer(form: .ringSmall, side: .inside, cogTeeth: 84, penFraction: 0.9,
                       lineWidth: 1.0, color: .classicGreen),
            RosetteLayer(form: .ringSmall, side: .inside, cogTeeth: 52, penFraction: 0.75,
                       lineWidth: 1.2, color: .classicBlue),
            RosetteLayer(form: .ringSmall, side: .inside, cogTeeth: 63, penFraction: 0.55,
                       lineWidth: 1.2, color: .classicRed),
        ]
    )

    static var demoRequested: Bool {
        ProcessInfo.processInfo.environment["ROSETTICA_DEMO"] != nil
    }

    /// Stamp one layer at "Learn" speed right after launch so automation can
    /// capture the rolling-cog animation mid-flight.
    static var animateDemoRequested: Bool {
        ProcessInfo.processInfo.environment["ROSETTICA_ANIMATE_DEMO"] != nil
    }

    /// Start Random Demo mode right after launch so automation can capture it.
    static var randomDemoRequested: Bool {
        ProcessInfo.processInfo.environment["ROSETTICA_RANDOM_DEMO"] != nil
    }

    static func run(with pattern: RosettePattern) {
        let env = ProcessInfo.processInfo.environment

        if let exportPath = env["ROSETTICA_EXPORT_PATH"] {
            PatternPrinter.writePNG(pattern, to: URL(fileURLWithPath: exportPath))
        }
        if let svgPath = env["ROSETTICA_EXPORT_SVG_PATH"] {
            PatternPrinter.writeSVG(pattern, to: URL(fileURLWithPath: svgPath))
        }
        if let pdfPath = env["ROSETTICA_EXPORT_PDF_PATH"] {
            PatternPrinter.writePDF(pattern, to: URL(fileURLWithPath: pdfPath))
        }

        if let viewsDir = env["ROSETTICA_RENDER_VIEWS_DIR"] {
            renderAuxiliaryViews(to: viewsDir)
        }

        if let snapshotPath = env["ROSETTICA_SNAPSHOT_PATH"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                let windows = NSApp.windows
                    .filter { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) }
                    .sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
                snapshotSequentially(windows, index: 0, basePath: snapshotPath)
            }
        }
    }

    /// Renders the About and Help views directly (no window needed) so their
    /// content can be inspected in automation.
    private static func renderAuxiliaryViews(to dir: String) {
        let dirURL = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        renderView(AboutView(), to: dirURL.appendingPathComponent("about.png"))
        renderView(HelpContent().padding(24).frame(width: 560).background(.white), to: dirURL.appendingPathComponent("help.png"))
        renderView(LicenseContent().padding(24).frame(width: 560).background(.white), to: dirURL.appendingPathComponent("license.png"))
    }

    private static func renderView(_ view: some View, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cgImage = renderer.cgImage,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(destination, cgImage, nil)
        CGImageDestinationFinalize(destination)
    }

    /// Brings each window to the front, lets it render, snapshots it, then
    /// moves on; terminates the app when done. Additional windows get an
    /// index and their title appended to the base file name.
    ///
    /// The snapshot renders the window frame's layer tree (title bar
    /// included) into a bitmap. Unlike `cacheDisplay`, this also captures
    /// SwiftUI text, and it needs no screen-recording permission.
    /// `ROSETTICA_SNAPSHOT_SIZE=<w>x<h>` resizes the first window first.
    private static func snapshotSequentially(_ windows: [NSWindow], index: Int, basePath: String) {
        guard index < windows.count else {
            NSApp.terminate(nil)
            return
        }
        let window = windows[index]
        if index == 0, let size = requestedSnapshotSize {
            window.setContentSize(size)
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            if let data = snapshotPNG(of: window) {
                var url = URL(fileURLWithPath: basePath)
                if index > 0 {
                    let title = window.title.replacingOccurrences(of: " ", with: "-").lowercased()
                    let base = url.deletingPathExtension().lastPathComponent
                    url = url.deletingLastPathComponent()
                        .appendingPathComponent("\(base)-\(index)-\(title).png")
                }
                try? data.write(to: url)
            }
            snapshotSequentially(windows, index: index + 1, basePath: basePath)
        }
    }

    private static var requestedSnapshotSize: NSSize? {
        guard let spec = ProcessInfo.processInfo.environment["ROSETTICA_SNAPSHOT_SIZE"] else { return nil }
        let parts = spec.lowercased().split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return NSSize(width: parts[0], height: parts[1])
    }

    /// The whole window (frame view with title bar) as PNG data at the
    /// window's backing scale.
    private static func snapshotPNG(of window: NSWindow) -> Data? {
        guard let frameView = window.contentView?.superview else { return nil }
        frameView.wantsLayer = true
        frameView.layoutSubtreeIfNeeded()
        frameView.display()
        let scale = window.backingScaleFactor
        let size = frameView.bounds.size
        guard let layer = frameView.layer,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        layer.render(in: ctx)
        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
