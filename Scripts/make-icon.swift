// Renders the app icon — a layered rosette on a deep blue disc —
// into an .iconset directory. Run: swift Scripts/make-icon.swift <output-dir>
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func hypotrochoid(R: Double, r: Double, d: Double, samples: Int) -> [CGPoint] {
    let gcd: (Int, Int) -> Int = { a, b in
        var a = a, b = b
        while b != 0 { (a, b) = (b, a % b) }
        return abs(a)
    }
    let laps = Int(r) / gcd(Int(R), Int(r))
    var points: [CGPoint] = []
    for i in 0...samples {
        let t = 2 * Double.pi * Double(laps) * Double(i) / Double(samples)
        let x = (R - r) * cos(t) + d * cos((R - r) / r * t)
        let y = (R - r) * sin(t) - d * sin((R - r) / r * t)
        points.append(CGPoint(x: x, y: y))
    }
    return points
}

func drawIcon(into ctx: CGContext, pixels: Int) {
    let size = Double(pixels)
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

    // Rounded-square background with a subtle vertical gradient.
    let inset = size * 0.05
    let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let rounded = CGPath(roundedRect: rect, cornerWidth: size * 0.21, cornerHeight: size * 0.21, transform: nil)
    ctx.addPath(rounded)
    ctx.clip()
    let colors = [
        CGColor(srgbRed: 0.10, green: 0.13, blue: 0.32, alpha: 1),
        CGColor(srgbRed: 0.04, green: 0.05, blue: 0.15, alpha: 1),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

    // Three layered rosettes.
    let scale = size * 0.40 / 96.0
    ctx.translateBy(x: size / 2, y: size / 2)
    ctx.scaleBy(x: scale, y: scale)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    let layers: [(r: Double, d: Double, color: CGColor, width: Double)] = [
        (56, 50, CGColor(srgbRed: 0.36, green: 0.62, blue: 1.00, alpha: 0.95), 2.2),
        (63, 44, CGColor(srgbRed: 1.00, green: 0.42, blue: 0.48, alpha: 0.90), 1.8),
        (45, 25, CGColor(srgbRed: 0.55, green: 0.95, blue: 0.72, alpha: 0.90), 1.5),
    ]
    for layer in layers {
        let points = hypotrochoid(R: 96, r: layer.r, d: layer.d, samples: 6000)
        ctx.beginPath()
        ctx.move(to: points[0])
        for p in points.dropFirst() { ctx.addLine(to: p) }
        ctx.setStrokeColor(layer.color)
        ctx.setLineWidth(layer.width / scale * (size / 1024) * 3.2)
        ctx.strokePath()
    }
}

func writePNG(pixels: Int, to url: URL) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    drawIcon(into: ctx, pixels: pixels)
    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("usage: swift make-icon.swift <output-dir>\n".data(using: .utf8)!)
    exit(1)
}
let outputDir = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = outputDir.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for entry in entries {
    writePNG(pixels: entry.pixels, to: iconset.appendingPathComponent("\(entry.name).png"))
}
print("Wrote \(iconset.path)")
