import AppKit
import CoreGraphics
import XCTest
@testable import RosetticaCore

final class VectorExportTests: XCTestCase {
    /// A spread of curves: every form and side, small and large cogs, pen
    /// near the center and near the rim, a fractional start phase.
    private var sampleCurves: [CurveParameters] {
        var curves: [CurveParameters] = []
        for form in FormID.allCases {
            for side in RollSide.allCases {
                let allowed = RosetteCatalog.form(form).allowedCogTeeth(for: side)
                for (cog, pen) in [(allowed.first!, 0.95), (allowed.last!, 0.3), (allowed[allowed.count / 2], 0.7)] {
                    curves.append(CurveParameters(form: form, side: side, cogTeeth: cog, penFraction: pen, phaseTeeth: 3.5))
                }
            }
        }
        return curves
    }

    func testBezierPiecesFollowTheExactCurve() {
        let tolerance = 0.005
        for p in sampleCurves {
            let pen = CurveEngine.PenEvaluator(p)
            let pieces = CurveEngine.bezierPieces(for: p, tolerance: tolerance)
            XCTAssertFalse(pieces.isEmpty)
            XCTAssertEqual(pieces.first!.s0, pen.s0, accuracy: 1e-9)
            XCTAssertEqual(pieces.last!.s1, pen.s0 + pen.sTotal, accuracy: 1e-6)
            // Closed, gap-free chain.
            XCTAssertLessThan(pieces.last!.p3.distance(to: pieces.first!.p0), 1e-6, "\(p) does not close")
            for (a, b) in zip(pieces, pieces.dropFirst()) {
                XCTAssertEqual(a.s1, b.s0, accuracy: 1e-9)
                XCTAssertEqual(a.p3, b.p0)
            }
            // Dense check in between the subdivision probes (t = ¼, ½, ¾).
            var worst = 0.0
            for piece in pieces {
                for k in 1..<10 {
                    let t = Double(k) / 10
                    let exact = pen.position(at: piece.s0 + t * (piece.s1 - piece.s0))
                    worst = max(worst, exact.distance(to: piece.point(at: t)))
                }
            }
            XCTAssertLessThan(worst, 2 * tolerance, "\(p): Bézier deviates by \(worst)")
        }
    }

    /// The Bézier pieces must trace the same curve as the polyline samples
    /// the canvas and PNG draw (an independent check of `PenEvaluator`).
    func testBezierPiecesMatchCanvasSamples() {
        for p in sampleCurves {
            let points = CurveEngine.points(for: p)
            let pieces = CurveEngine.bezierPieces(for: p, tolerance: 0.005)
            let pen = CurveEngine.PenEvaluator(p)
            let n = points.count - 1
            var index = 0
            for k in stride(from: 0, through: n, by: max(1, n / 500)) {
                let s = pen.s0 + pen.sTotal * Double(k) / Double(n)
                while index < pieces.count - 1 && pieces[index].s1 < s { index += 1 }
                let piece = pieces[index]
                let t = (s - piece.s0) / (piece.s1 - piece.s0)
                XCTAssertLessThan(points[k].distance(to: piece.point(at: t)), 0.01, "\(p) at sample \(k)")
            }
        }
    }

    func testFixedPointFormatting() {
        XCTAssertEqual(VectorArtwork.fixed(0), "0")
        XCTAssertEqual(VectorArtwork.fixed(300), "3")
        XCTAssertEqual(VectorArtwork.fixed(1250), "12.5")
        XCTAssertEqual(VectorArtwork.fixed(-7), "-0.07")
        XCTAssertEqual(VectorArtwork.fixed(-120_005), "-1200.05")
        XCTAssertEqual(VectorArtwork.fixed(1600, decimals: 3), "1.6")
        XCTAssertEqual(VectorArtwork.fixed(3005, decimals: 3), "3.005")
    }

    /// Parses the relative path data back and checks every point lands within
    /// rounding distance of the CGPath — rounding must not accumulate.
    func testPathDataRoundTripsWithoutDrift() {
        let artwork = VectorArtwork(pattern: Self.demoPattern)
        for stroke in artwork.strokes {
            var expected: [CGPoint] = []
            stroke.path.applyWithBlock { element in
                let pts = element.pointee.points
                switch element.pointee.type {
                case .moveToPoint: expected.append(pts[0])
                case .addCurveToPoint: expected += [pts[0], pts[1], pts[2]]
                default: break
                }
            }
            let parsed = Self.parsePathData(VectorArtwork.pathData(stroke.path))
            XCTAssertEqual(parsed.count, expected.count)
            var worst = 0.0
            for (a, b) in zip(parsed, expected) {
                worst = max(worst, a.distance(to: b))
            }
            XCTAssertLessThan(worst, 0.0071, "path data drifts by \(worst)")
        }
    }

    func testSVGStructure() throws {
        let svg = VectorArtwork(pattern: Self.demoPattern).svg()
        XCTAssertTrue(svg.contains("width=\"1200pt\" height=\"1200pt\" viewBox=\"0 0 1200 1200\""))
        XCTAssertTrue(svg.contains("fill=\"#fcf7eb\""), "background color")
        XCTAssertTrue(svg.contains("stroke-opacity=\"0.5\""), "translucent layer")
        let parser = XMLParser(data: Data(svg.utf8))
        let counter = ElementCounter()
        parser.delegate = counter
        XCTAssertTrue(parser.parse(), "SVG is not well-formed XML")
        XCTAssertEqual(counter.counts["path"], Self.demoPattern.layers.count)
        XCTAssertEqual(counter.counts["rect"], 1)
    }

    func testPDFPageAndMetadata() throws {
        let data = try XCTUnwrap(VectorArtwork(pattern: Self.demoPattern).pdf())
        let document = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        XCTAssertEqual(document.numberOfPages, 1)
        let page = try XCTUnwrap(document.page(at: 1))
        XCTAssertEqual(page.getBoxRect(.mediaBox), CGRect(x: 0, y: 0, width: 1200, height: 1200))
        let info = try XCTUnwrap(document.info)
        var creator: CGPDFStringRef?
        XCTAssertTrue(CGPDFDictionaryGetString(info, "Creator", &creator))
        XCTAssertEqual(creator.flatMap { CGPDFStringCopyTextString($0) } as String?, "Rosettica")
        var author: CGPDFStringRef?
        XCTAssertFalse(CGPDFDictionaryGetString(info, "Author", &author), "PDF must not name an author")
    }

    /// Rasterized SVG and PDF must agree with a dense polyline rendering of
    /// the same pattern — same framing, rotation, widths and colors.
    func testVectorExportsMatchRasterRendering() throws {
        let pattern = Self.demoPattern
        let artwork = VectorArtwork(pattern: pattern)
        let pixels = 600
        let reference = try XCTUnwrap(Self.renderReference(pattern, pixels: pixels))

        let pdfData = try XCTUnwrap(artwork.pdf())
        let page = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: pdfData as CFData)!)?.page(at: 1))
        let pdfImage = try XCTUnwrap(Self.rasterize(pixels: pixels) { ctx in
            ctx.scaleBy(x: CGFloat(pixels) / 1200, y: CGFloat(pixels) / 1200)
            ctx.drawPDFPage(page)
        })
        let pdfDiff = Self.meanDifference(reference, pdfImage)
        XCTAssertLessThan(pdfDiff, 0.004, "PDF differs from raster by \(pdfDiff)")

        let svgImage = try XCTUnwrap(NSImage(data: Data(artwork.svg().utf8)))
        let svgBitmap = try XCTUnwrap(Self.rasterize(pixels: pixels) { ctx in
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            svgImage.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
            NSGraphicsContext.restoreGraphicsState()
        })
        let svgDiff = Self.meanDifference(reference, svgBitmap)
        XCTAssertLessThan(svgDiff, 0.004, "SVG differs from raster by \(svgDiff)")

        // A blank page would also be "close" on a light background; make
        // sure the comparison is sensitive by checking an empty pattern.
        var empty = pattern
        empty.layers = []
        let blank = try XCTUnwrap(Self.renderReference(empty, pixels: pixels))
        XCTAssertGreaterThan(Self.meanDifference(reference, blank), 10 * pdfDiff)
    }

    // MARK: - Helpers

    static let demoPattern = RosettePattern(
        background: RGBAColor(red: 0.99, green: 0.97, blue: 0.92),
        layers: [
            RosetteLayer(form: .ringLarge, side: .inside, cogTeeth: 84, penFraction: 0.9,
                       lineWidth: 1.0, color: .classicGreen),
            RosetteLayer(form: .triangle, side: .outside, cogTeeth: 30, penFraction: 0.75,
                       rotationDegrees: 20, lineWidth: 1.4, color: .classicBlue),
            RosetteLayer(form: .stadium, side: .inside, cogTeeth: 40, penFraction: 0.55, phaseTeeth: 7,
                       lineWidth: 2.5, color: RGBAColor(red: 0.82, green: 0.12, blue: 0.16, alpha: 0.5)),
        ]
    )

    /// The PNG renderer's algorithm (dense polyline, y-down page) in core terms.
    static func renderReference(_ pattern: RosettePattern, pixels: Int) -> [UInt8]? {
        rasterize(pixels: pixels) { ctx in
            let size = Double(pixels)
            ctx.translateBy(x: 0, y: CGFloat(size))
            ctx.scaleBy(x: 1, y: -1)
            ctx.setFillColor(CGColor(srgbRed: pattern.background.red, green: pattern.background.green,
                                     blue: pattern.background.blue, alpha: pattern.background.alpha))
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            let scale = size / (2 * pattern.viewportRadius)
            let world = CGAffineTransform(translationX: size / 2, y: size / 2).scaledBy(x: scale, y: -scale)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for layer in pattern.layers {
                let t = CGAffineTransform(rotationAngle: -layer.rotationDegrees * .pi / 180).concatenating(world)
                let path = CGMutablePath()
                path.addLines(between: CurveEngine.points(for: layer.curveParameters), transform: t)
                ctx.addPath(path)
                let c = layer.color
                ctx.setStrokeColor(CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha))
                ctx.setLineWidth(layer.lineWidth * size / RosettePattern.lineWidthReferenceSize)
                ctx.strokePath()
            }
        }
    }

    static func rasterize(pixels: Int, draw: (CGContext) -> Void) -> [UInt8]? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                  bytesPerRow: pixels * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        draw(ctx)
        guard let data = ctx.data else { return nil }
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: pixels * pixels * 4))
    }

    /// Mean absolute channel difference, 0...1.
    static func meanDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var total = 0
        for i in 0..<min(a.count, b.count) {
            total += abs(Int(a[i]) - Int(b[i]))
        }
        return Double(total) / Double(a.count) / 255
    }

    /// Absolute points of an "M x y c …Z" path with relative curves.
    static func parsePathData(_ d: String) -> [CGPoint] {
        var points: [CGPoint] = []
        var numbers: [Double] = []
        var command: Character = " "
        var current = CGPoint.zero
        var token = ""
        func flushToken() {
            if !token.isEmpty, let v = Double(token) { numbers.append(v) }
            token = ""
        }
        func consume() {
            if command == "M", numbers.count >= 2 {
                current = CGPoint(x: numbers[0], y: numbers[1])
                points.append(current)
                numbers.removeFirst(2)
                command = "l"
            }
            while command == "c", numbers.count >= 6 {
                let n = numbers
                points.append(CGPoint(x: current.x + n[0], y: current.y + n[1]))
                points.append(CGPoint(x: current.x + n[2], y: current.y + n[3]))
                current = CGPoint(x: current.x + n[4], y: current.y + n[5])
                points.append(current)
                numbers.removeFirst(6)
            }
        }
        for ch in d {
            if ch.isLetter {
                flushToken(); consume()
                command = ch
            } else if ch == " " {
                flushToken(); consume()
            } else if ch == "-" {
                flushToken(); consume()
                token = "-"
            } else {
                token.append(ch)
            }
        }
        flushToken(); consume()
        return points
    }
}

private final class ElementCounter: NSObject, XMLParserDelegate {
    var counts: [String: Int] = [:]
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        counts[elementName, default: 0] += 1
    }
}
