#!/usr/bin/swift
// Draws the backdrop of the installer disk image.
// Usage: swift Tools/dmgbackground.swift <output.png> [scale]
// Scripts/build-dmg.sh renders it at 1x and 2x and packs both into one TIFF.
//
// All coordinates are Finder's: points, origin top-left. The icon positions
// below must match the ones Scripts/build-dmg.sh hands to Finder.
//
// The backdrop is deliberately mid-toned: Finder draws icon labels black in
// light mode and white in dark mode whatever the picture behind them, and
// only a middle brightness keeps both readable.

import AppKit
import CoreText

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
let scale = CommandLine.arguments.count > 2 ? CGFloat(Double(CommandLine.arguments[2]) ?? 1) : 1

// The window shows 680 x 460; the picture is larger so a slightly bigger
// window never runs out of backdrop.
let width: CGFloat = 760
let height: CGFloat = 520

let appIcon = CGPoint(x: 180, y: 150)
let applicationsIcon = CGPoint(x: 500, y: 150)
let saverIcon = CGPoint(x: 180, y: 330)
let iconSize: CGFloat = 112

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale),
                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else {
    print("dmgbackground: cannot create context")
    exit(1)
}
// Work in Finder coordinates: y grows downward.
ctx.scaleBy(x: scale, y: scale)
ctx.translateBy(x: 0, y: height)
ctx.scaleBy(x: 1, y: -1)

func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}
let white = { (alpha: CGFloat) in srgb(1, 1, 1, alpha) }

// Blue-teal ground (the app icon's deep blue, lifted to a middle
// brightness), a little lighter toward the top left.
if let gradient = CGGradient(colorsSpace: space,
                             colors: [srgb(0.33, 0.58, 0.72), srgb(0.24, 0.44, 0.62)] as CFArray,
                             locations: [0, 1]) {
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }

/// A trochoid rosette as the app draws it: a cog of `cogTeeth` rolling
/// inside (`inside`) or around a ring of `ringTeeth`, pen at `pen` × cog
/// radius, scaled so the ring radius is `radius` points. Closed form of the
/// hypotrochoid / epitrochoid; the curve closes after cog/gcd laps.
func trochoid(at center: CGPoint, radius: CGFloat, ringTeeth: Int, cogTeeth: Int,
              pen: CGFloat, inside: Bool, rotation: CGFloat = 0) -> CGPath {
    let R = CGFloat(ringTeeth), r = CGFloat(cogTeeth), d = pen * r
    let laps = cogTeeth / gcd(ringTeeth, cogTeeth)
    let steps = laps * 360
    let k = radius / R
    let path = CGMutablePath()
    for i in 0...steps {
        let t = 2 * .pi * CGFloat(laps) * CGFloat(i) / CGFloat(steps)
        let x: CGFloat, y: CGFloat
        if inside {
            x = (R - r) * cos(t) + d * cos((R - r) / r * t)
            y = (R - r) * sin(t) - d * sin((R - r) / r * t)
        } else {
            x = (R + r) * cos(t) - d * cos((R + r) / r * t)
            y = (R + r) * sin(t) - d * sin((R + r) / r * t)
        }
        let p = CGPoint(x: x * k, y: y * k)
            .applying(CGAffineTransform(rotationAngle: rotation))
        let q = CGPoint(x: center.x + p.x, y: center.y + p.y)
        if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
    }
    path.closeSubpath()
    return path
}

func stroke(_ path: CGPath, alpha: CGFloat, width lineWidth: CGFloat = 1.1) {
    ctx.addPath(path)
    ctx.setStrokeColor(white(alpha))
    ctx.setLineWidth(lineWidth)
    ctx.strokePath()
}

ctx.setLineCap(.round)
ctx.setLineJoin(.round)

// Large layered rosette at the bottom right, as if stamped three times
// with different cogs, kept clear of the screensaver caption.
let big = CGPoint(x: 650, y: 432)
stroke(trochoid(at: big, radius: 190, ringTeeth: 96, cogTeeth: 84, pen: 0.85, inside: true), alpha: 0.09)
stroke(trochoid(at: big, radius: 150, ringTeeth: 96, cogTeeth: 52, pen: 0.8, inside: true, rotation: 0.12), alpha: 0.17)
stroke(trochoid(at: big, radius: 95, ringTeeth: 96, cogTeeth: 30, pen: 0.75, inside: true), alpha: 0.22)

// Smaller rosette peeking in at the top left corner.
let small = CGPoint(x: 30, y: 25)
stroke(trochoid(at: small, radius: 70, ringTeeth: 96, cogTeeth: 36, pen: 0.9, inside: false), alpha: 0.12)
stroke(trochoid(at: small, radius: 70, ringTeeth: 96, cogTeeth: 63, pen: 0.6, inside: true), alpha: 0.10)

/// Draws one line of text; `x` is its left edge, or its center with `centered`.
func text(_ string: String, x: CGFloat, baseline y: CGFloat, size: CGFloat, bold: Bool = false,
          alpha: CGFloat = 1, centered: Bool = false) {
    let font = bold ? NSFont.systemFont(ofSize: size, weight: .semibold) : NSFont.systemFont(ofSize: size)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [
        .font: font, .foregroundColor: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha),
    ]))
    let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    ctx.saveGState()
    // Core Text draws y-up: undo the flip around the baseline.
    ctx.translateBy(x: centered ? x - lineWidth / 2 : x, y: y)
    ctx.scaleBy(x: 1, y: -1)
    ctx.textPosition = .zero
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

// "Drag the app onto Applications": an arrow between the two icons.
do {
    let from = appIcon.x + iconSize / 2 + 34
    let to = applicationsIcon.x - iconSize / 2 - 34
    let y = appIcon.y - 6
    ctx.setStrokeColor(white(0.92))
    ctx.setLineWidth(5)
    ctx.move(to: CGPoint(x: from, y: y))
    ctx.addLine(to: CGPoint(x: to, y: y))
    ctx.move(to: CGPoint(x: to - 15, y: y - 13))
    ctx.addLine(to: CGPoint(x: to, y: y))
    ctx.addLine(to: CGPoint(x: to - 15, y: y + 13))
    ctx.strokePath()
    text("drag to install", x: (from + to) / 2, baseline: y + 30, size: 12.5, alpha: 0.9, centered: true)
}

// The screensaver sits below the app, with its instructions beside it.
do {
    let x = saverIcon.x + iconSize / 2 + 34
    text("The screensaver", x: x, baseline: saverIcon.y - 12, size: 15, bold: true)
    text("Double-click to install it.", x: x, baseline: saverIcon.y + 9, size: 12.5, alpha: 0.92)
    text("Every display draws its own rosettes.", x: x, baseline: saverIcon.y + 27, size: 12.5, alpha: 0.92)
}

guard let image = ctx.makeImage(),
      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
else {
    print("dmgbackground: cannot render")
    exit(1)
}
do {
    try data.write(to: URL(fileURLWithPath: output))
    print("dmgbackground: wrote \(output) (\(image.width) x \(image.height))")
} catch {
    print("dmgbackground: \(error.localizedDescription)")
    exit(1)
}
