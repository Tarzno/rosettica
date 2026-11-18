// Renders the pictures in Images/ that README.md shows (except the app icon
// and the window screenshots, which come from the app itself — see
// CLAUDE.md "README pictures").
//
// Compiled together with the core so it draws with the app's own geometry:
//
//   swiftc -O -parse-as-library Sources/RosetticaCore/*.swift \
//       Tools/readme-images.swift -o .build/readme-images
//   .build/readme-images gallery Images/gallery.png
//   .build/readme-images zoom Images/zoom-png.png Images/zoom-svg.png
//   .build/readme-images monitors Images/screensaver.png a.png b.png c.png
//   .build/readme-images candidates <dir>     # seeds for the gallery
//   .build/readme-images window <snapshot.png> Images/window.png
//
// Patterns are drawn through `VectorArtwork` (the SVG/PDF export), so the
// pictures show exactly what the app exports.

import AppKit
import CoreGraphics

/// Reproducible random numbers for the gallery's generated compositions.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A Random-Demo / screensaver composition for a fixed seed, on `background`.
func composition(seed: UInt64, background: RGBAColor) -> RosettePattern {
    var rng = SplitMix64(state: seed)
    var composer = DemoComposer(hue: Double(seed % 1000) / 1000)
    return RosettePattern(background: background, layers: composer.composeLayers(using: &rng))
}

let paper = RGBAColor(red: 0.99, green: 0.97, blue: 0.92)

/// Hand-made classics: ballpoint colors on paper, the way the toy is used.
let classics: [RosettePattern] = [
    RosettePattern(background: paper, layers: [
        RosetteLayer(form: .ringLarge, side: .inside, cogTeeth: 84, penFraction: 0.92,
                     lineWidth: 0.9, color: .classicGreen),
        RosetteLayer(form: .ringLarge, side: .inside, cogTeeth: 52, penFraction: 0.8,
                     lineWidth: 1.0, color: .classicBlue),
        RosetteLayer(form: .ringLarge, side: .inside, cogTeeth: 30, penFraction: 0.7,
                     lineWidth: 1.1, color: .classicRed),
    ]),
    RosettePattern(background: RGBAColor(red: 0.97, green: 0.97, blue: 0.99), layers: [
        RosetteLayer(form: .pentagon, side: .outside, cogTeeth: 52, penFraction: 0.75,
                     lineWidth: 0.8, color: RGBAColor(red: 0.0, green: 0.50, blue: 0.56)),
        RosetteLayer(form: .pentagon, side: .inside, cogTeeth: 32, penFraction: 0.9,
                     lineWidth: 0.9, color: RGBAColor(red: 0.45, green: 0.18, blue: 0.62)),
    ]),
    RosettePattern(background: RGBAColor(red: 0.95, green: 0.98, blue: 0.94), layers: [
        RosetteLayer(form: .ringSmall, side: .inside, cogTeeth: 45, penFraction: 0.95,
                     lineWidth: 0.8, color: RGBAColor(red: 0.85, green: 0.42, blue: 0.08)),
        RosetteLayer(form: .square, side: .inside, cogTeeth: 45, penFraction: 0.8,
                     rotationDegrees: 45, lineWidth: 0.9, color: .classicGreen),
        RosetteLayer(form: .ringSmall, side: .inside, cogTeeth: 75, penFraction: 0.5,
                     lineWidth: 0.9, color: .classicRed),
    ]),
]

// MARK: - Drawing helpers

func makeContext(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func writePNG(_ image: CGImage, to path: String) {
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(image.width) x \(image.height))")
}

/// Draws `pattern`'s vector export into `rect` (y-up context coordinates).
func drawPattern(_ pattern: RosettePattern, in ctx: CGContext, rect: CGRect) {
    let artwork = VectorArtwork(pattern: pattern)
    let page = CGPDFDocument(CGDataProvider(data: artwork.pdf()! as CFData)!)!.page(at: 1)!
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.minY)
    ctx.scaleBy(x: rect.width / artwork.size, y: rect.height / artwork.size)
    ctx.drawPDFPage(page)
    ctx.restoreGState()
}

func roundedTile(_ pattern: RosettePattern, in ctx: CGContext, rect: CGRect, radius: CGFloat) {
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    drawPattern(pattern, in: ctx, rect: rect)
    ctx.restoreGState()
}

// MARK: - Commands

/// 3 × 2 tiles: three generated compositions on dark grounds (top) and the
/// three classics on paper (bottom).
func gallery(_ out: String) {
    let darkGrounds = [
        RGBAColor(red: 0.04, green: 0.04, blue: 0.06),
        RGBAColor(red: 0.07, green: 0.05, blue: 0.11),
        RGBAColor(red: 0.03, green: 0.06, blue: 0.07),
    ]
    let seeds: [UInt64] = [21, 8, 17]
    let generated = zip(seeds, darkGrounds).map { composition(seed: $0, background: $1) }
    let tiles = generated + classics
    let tile: CGFloat = 460, gap: CGFloat = 26, radius: CGFloat = 22
    let ctx = makeContext(Int(3 * tile + 2 * gap), Int(2 * tile + gap))
    for (i, pattern) in tiles.enumerated() {
        let col = CGFloat(i % 3), row = CGFloat(1 - i / 3) // first row on top
        roundedTile(pattern, in: ctx, rect: CGRect(x: col * (tile + gap), y: row * (tile + gap),
                                                   width: tile, height: tile), radius: radius)
    }
    writePNG(ctx.makeImage()!, to: out)
}

/// Small renders of many seeds, to pick the gallery's compositions.
func candidates(_ dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for seed in UInt64(1)...30 {
        let ctx = makeContext(300, 300)
        drawPattern(composition(seed: seed, background: RGBAColor(red: 0.04, green: 0.04, blue: 0.06)),
                    in: ctx, rect: CGRect(x: 0, y: 0, width: 300, height: 300))
        writePNG(ctx.makeImage()!, to: "\(dir)/seed-\(String(format: "%02d", seed)).png")
    }
}

/// The same detail of the first classic at 10× magnification: the PNG export
/// (2048 px, as the app writes it, from the canvas polyline) enlarged with
/// visible pixels, and the vector export rendered at that magnification.
func zoom(_ outPNG: String, _ outSVG: String, origin: CGPoint = CGPoint(x: 1004, y: 1660)) {
    let pattern = classics[0]
    let exportPixels = 2048
    let magnification: CGFloat = 10
    let view = 400 // output edge in pixels
    let crop = CGFloat(view) / magnification // detail edge in export pixels
    // `origin`: bottom-left of the detail in export pixels (y up), chosen
    // where several curves cross.

    // PNG export, rendered like PatternRenderer: dense polylines, round caps.
    let png = makeContext(exportPixels, exportPixels)
    let size = Double(exportPixels)
    png.setFillColor(CGColor(srgbRed: paper.red, green: paper.green, blue: paper.blue, alpha: 1))
    png.fill(CGRect(x: 0, y: 0, width: size, height: size))
    png.translateBy(x: 0, y: CGFloat(size)); png.scaleBy(x: 1, y: -1)
    let scale = size / (2 * pattern.viewportRadius)
    let world = CGAffineTransform(translationX: size / 2, y: size / 2).scaledBy(x: scale, y: -scale)
    png.setLineCap(.round); png.setLineJoin(.round)
    for layer in pattern.layers {
        let path = CGMutablePath()
        path.addLines(between: CurveEngine.points(for: layer.curveParameters), transform: world)
        png.addPath(path)
        let c = layer.color
        png.setStrokeColor(CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha))
        png.setLineWidth(layer.lineWidth * size / RosettePattern.lineWidthReferenceSize)
        png.strokePath()
    }
    let full = png.makeImage()!
    // CGImage.cropping uses a top-left origin.
    let detail = full.cropping(to: CGRect(x: origin.x, y: CGFloat(exportPixels) - origin.y - crop,
                                          width: crop, height: crop))!
    let pixelated = makeContext(view, view)
    pixelated.interpolationQuality = .none
    pixelated.draw(detail, in: CGRect(x: 0, y: 0, width: view, height: view))
    writePNG(pixelated.makeImage()!, to: outPNG)

    // Vector export of the same detail, at 10× the export resolution.
    let vector = makeContext(view, view)
    vector.translateBy(x: -origin.x * magnification, y: -origin.y * magnification)
    drawPattern(pattern, in: vector, rect: CGRect(x: 0, y: 0, width: size * magnification,
                                                  height: size * magnification))
    writePNG(vector.makeImage()!, to: outSVG)
}

/// Screensaver frames side by side in simple display bezels.
func monitors(_ out: String, _ frames: [String]) {
    let images = frames.map { NSImage(contentsOfFile: $0)!.cgImage(forProposedRect: nil, context: nil, hints: nil)! }
    let screenW: CGFloat = 800
    let screenH = screenW * CGFloat(images[0].height) / CGFloat(images[0].width)
    let bezel: CGFloat = 14, gap: CGFloat = 22, radius: CGFloat = 26
    let width = CGFloat(images.count) * (screenW + 2 * bezel) + CGFloat(images.count - 1) * gap
    let height = screenH + 2 * bezel
    let ctx = makeContext(Int(width), Int(height))
    ctx.interpolationQuality = .high
    for (i, image) in images.enumerated() {
        let x = CGFloat(i) * (screenW + 2 * bezel + gap)
        let outer = CGRect(x: x, y: 0, width: screenW + 2 * bezel, height: height)
        ctx.setFillColor(CGColor(srgbRed: 0.29, green: 0.29, blue: 0.30, alpha: 1))
        ctx.addPath(CGPath(roundedRect: outer, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
        let inner = outer.insetBy(dx: bezel, dy: bezel)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: inner, cornerWidth: radius - bezel, cornerHeight: radius - bezel,
                           transform: nil))
        ctx.clip()
        ctx.draw(image, in: inner)
        ctx.restoreGState()
    }
    writePNG(ctx.makeImage()!, to: out)
}

/// A window snapshot (ROSETTICA_SNAPSHOT_PATH) dressed like a screenshot:
/// rounded corners and a soft shadow, scaled to `width` pixels.
func window(_ input: String, _ out: String, width: CGFloat = 1720) {
    let image = NSImage(contentsOfFile: input)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let scale = width / CGFloat(image.width)
    let w = width, h = CGFloat(image.height) * scale
    let margin: CGFloat = 60, radius: CGFloat = 26
    let ctx = makeContext(Int(w + 2 * margin), Int(h + 2 * margin))
    ctx.interpolationQuality = .high
    let rect = CGRect(x: margin, y: margin, width: w, height: h)
    let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 44,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.draw(image, in: rect)
    ctx.restoreGState()
    // Hairline border, as macOS draws around windows.
    ctx.addPath(shape)
    ctx.setStrokeColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 0.5))
    ctx.setLineWidth(1.5)
    ctx.strokePath()
    writePNG(ctx.makeImage()!, to: out)
}

@main
struct ReadmeImages {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        switch args.first {
        case "gallery" where args.count == 2: gallery(args[1])
        case "candidates" where args.count == 2: candidates(args[1])
        case "window" where args.count == 3: window(args[1], args[2])
        case "zoom" where args.count == 3: zoom(args[1], args[2])
        case "zoom" where args.count == 5:
            zoom(args[1], args[2], origin: CGPoint(x: Double(args[3])!, y: Double(args[4])!))
        case "monitors" where args.count >= 3: monitors(args[1], Array(args.dropFirst(2)))
        default:
            print("usage: readme-images gallery <out> | candidates <dir> | zoom <png> <svg> [x y] | monitors <out> <frames…> | window <snapshot> <out>")
            exit(1)
        }
    }
}
