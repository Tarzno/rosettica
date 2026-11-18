import AppKit
import UniformTypeIdentifiers
import RosetticaCore

/// Renders a pattern for printing. Flipped so the shared CG renderer's
/// y-down coordinates match the on-screen canvas.
final class PatternPrintView: NSView {
    private let pattern: RosettePattern

    init(pattern: RosettePattern, frame: NSRect) {
        self.pattern = pattern
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        PatternRenderer.render(pattern: pattern, in: ctx, rect: bounds)
    }
}

@MainActor
enum PatternPrinter {
    static func printPattern(_ pattern: RosettePattern) {
        let info = NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true

        let page = info.imageablePageBounds
        let view = PatternPrintView(pattern: pattern, frame: NSRect(origin: .zero, size: page.size))
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.run()
    }

    static func exportPNG(_ pattern: RosettePattern) {
        guard let url = askForDestination(type: .png, fileExtension: "png") else { return }
        if !writePNG(pattern, to: url) {
            reportFailure(format: "PNG", url: url)
        }
    }

    static func exportSVG(_ pattern: RosettePattern) {
        guard let url = askForDestination(type: .svg, fileExtension: "svg") else { return }
        if !writeSVG(pattern, to: url) {
            reportFailure(format: "SVG", url: url)
        }
    }

    static func exportPDF(_ pattern: RosettePattern) {
        guard let url = askForDestination(type: .pdf, fileExtension: "pdf") else { return }
        if !writePDF(pattern, to: url) {
            reportFailure(format: "PDF", url: url)
        }
    }

    /// Save panel suggesting the document's name (or "Rosettica" while
    /// untitled) with the export's extension.
    private static func askForDestination(type: UTType, fileExtension: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        let base = NSDocumentController.shared.currentDocument?.fileURL?
            .deletingPathExtension().lastPathComponent ?? "Rosettica"
        panel.nameFieldStringValue = base + "." + fileExtension
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    private static func reportFailure(format: String, url: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The \(format) file could not be written."
        alert.informativeText = url.path
        alert.runModal()
    }

    /// Resolution-independent export: exact Bézier curves on a
    /// 1200 × 1200 pt page, framed like the PNG.
    @discardableResult
    static func writeSVG(_ pattern: RosettePattern, to url: URL) -> Bool {
        let svg = VectorArtwork(pattern: pattern).svg()
        return (try? Data(svg.utf8).write(to: url, options: .atomic)) != nil
    }

    @discardableResult
    static func writePDF(_ pattern: RosettePattern, to url: URL) -> Bool {
        guard let data = VectorArtwork(pattern: pattern).pdf() else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    @discardableResult
    static func writePNG(_ pattern: RosettePattern, to url: URL, pixels: Int = 2048) -> Bool {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: nil, width: pixels, height: pixels,
                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return false }

        // Flip to the same y-down space the canvas uses.
        ctx.translateBy(x: 0, y: CGFloat(pixels))
        ctx.scaleBy(x: 1, y: -1)
        PatternRenderer.render(
            pattern: pattern,
            in: ctx,
            rect: CGRect(x: 0, y: 0, width: pixels, height: pixels)
        )

        guard let image = ctx.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}
