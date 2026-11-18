import CoreGraphics
import Foundation

// MARK: - Framing shared by the canvas, PNG, SVG and PDF output

extension RosettePattern {
    /// Line widths are specified for a canvas of this size and scale with it.
    public static let lineWidthReferenceSize: Double = 600

    /// World radius (scene units) of the square viewport that shows content
    /// reaching `contentRadius` from the origin, with a small margin.
    public static func viewportRadius(contentRadius: Double) -> Double {
        max(120, contentRadius) * 1.06
    }

    /// Viewport radius of the finished pattern (no guides), as framed by the
    /// PNG, SVG and PDF exports and by printing.
    public var viewportRadius: Double {
        let content = layers.reduce(0.0) { radius, layer in
            max(radius, CurveEngine.boundingRadius(of: CurveEngine.points(for: layer.curveParameters)))
        }
        return Self.viewportRadius(contentRadius: content)
    }
}

// MARK: - Exact Bézier approximation of a rolled curve

/// One cubic Bézier piece of a curve, with the rolled arc-length range
/// `s0...s1` it stands for (the Bézier parameter t maps linearly onto it).
struct BezierPiece {
    var p0: CGPoint
    var c1: CGPoint
    var c2: CGPoint
    var p3: CGPoint
    var s0: Double
    var s1: Double

    func point(at t: Double) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(
            x: a * p0.x + b * c1.x + c * c2.x + d * p3.x,
            y: a * p0.y + b * c1.y + c * c2.y + d * p3.y
        )
    }
}

extension CurveEngine {
    /// Evaluates the pen position — and its derivative with respect to the
    /// rolled arc length s — exactly, from the same rolling model as
    /// `points(for:)`.
    struct PenEvaluator {
        let track: Track
        let r: Double
        let d: Double
        let eps: Double
        let s0: Double
        let sTotal: Double
        let psi0: Double
        let turning0: Double

        init(_ p: CurveParameters) {
            let form = RosetteCatalog.form(p.form)
            track = form.track(for: p.side)
            let formTeeth = form.teeth(for: p.side)
            let lapCount = CurveEngine.laps(formTeeth: formTeeth, cogTeeth: p.cogTeeth)
            sTotal = Double(formTeeth * lapCount) * RosetteCatalog.toothPitch
            r = RosetteCatalog.cogRadius(teeth: p.cogTeeth)
            d = p.penFraction * r
            eps = p.side == .inside ? 1 : -1
            s0 = p.phaseTeeth * RosetteCatalog.toothPitch
            let start = track.sample(at: s0)
            psi0 = atan2(-eps * start.leftNormal.dy, -eps * start.leftNormal.dx)
            turning0 = track.turning(at: s0)
        }

        func position(at s: Double) -> CGPoint {
            let sample = track.sample(at: s)
            let psi = psi0 + (track.turning(at: s) - turning0) - eps * (s - s0) / r
            return CGPoint(
                x: sample.position.x + eps * r * sample.leftNormal.dx + d * cos(psi),
                y: sample.position.y + eps * r * sample.leftNormal.dy + d * sin(psi)
            )
        }

        /// d(pen)/ds on a track element of curvature κ. With the left normal
        /// n' = −κ·t, the cog center c = p + ε·r·n moves with c' = t·(1 − ε·r·κ),
        /// and the cog turns with ψ' = κ − ε/r. Curvature jumps at element
        /// joints, so the caller passes the curvature of the element the
        /// interval lies in (one-sided derivative at its ends).
        func derivative(at s: Double, curvature kappa: Double) -> CGVector {
            let sample = track.sample(at: s)
            let psi = psi0 + (track.turning(at: s) - turning0) - eps * (s - s0) / r
            let centerSpeed = 1 - eps * r * kappa
            let spin = d * (kappa - eps / r)
            return CGVector(
                dx: sample.tangent.dx * centerSpeed - spin * sin(psi),
                dy: sample.tangent.dy * centerSpeed + spin * cos(psi)
            )
        }
    }

    /// The complete closed curve as cubic Bézier pieces in world coordinates,
    /// each within `tolerance` (world units) of the exact rolled curve.
    ///
    /// Pieces never straddle a joint of the track's segments and arcs (where
    /// the pen velocity jumps); within an element the curve is smooth, and
    /// each piece is the cubic Hermite interpolant of the exact positions and
    /// derivatives at its ends, subdivided until it is accurate enough.
    static func bezierPieces(for p: CurveParameters, tolerance: Double) -> [BezierPiece] {
        let pen = PenEvaluator(p)
        let track = pen.track
        let sStart = pen.s0
        let sEnd = pen.s0 + pen.sTotal

        // Every element joint inside the rolled range, plus its ends.
        var knots = [sStart]
        var lapStart = (sStart / track.totalLength).rounded(.down) * track.totalLength
        scan: while true {
            for start in track.elementStartLengths {
                let knot = lapStart + start
                if knot >= sEnd - 1e-9 { break scan }
                if knot > sStart + 1e-9 { knots.append(knot) }
            }
            lapStart += track.totalLength
        }
        knots.append(sEnd)

        let maxStep = 2 * RosetteCatalog.toothPitch
        var pieces: [BezierPiece] = []
        pieces.reserveCapacity(Int(pen.sTotal / maxStep) * 2)

        func subdivide(_ a: Double, _ pa: CGPoint, _ b: Double, _ pb: CGPoint, kappa: Double, depth: Int) {
            let h = b - a
            let da = pen.derivative(at: a, curvature: kappa)
            let db = pen.derivative(at: b, curvature: kappa)
            let piece = BezierPiece(
                p0: pa,
                c1: CGPoint(x: pa.x + h / 3 * da.dx, y: pa.y + h / 3 * da.dy),
                c2: CGPoint(x: pb.x - h / 3 * db.dx, y: pb.y - h / 3 * db.dy),
                p3: pb,
                s0: a,
                s1: b
            )
            var error = 0.0
            var midPoint = CGPoint.zero
            for t in [0.5, 0.25, 0.75] {
                let exact = pen.position(at: a + t * h)
                if t == 0.5 { midPoint = exact }
                error = max(error, exact.distance(to: piece.point(at: t)))
                if error > tolerance { break }
            }
            if error <= tolerance || depth >= 12 {
                pieces.append(piece)
            } else {
                let m = a + h / 2
                subdivide(a, pa, m, midPoint, kappa: kappa, depth: depth + 1)
                subdivide(m, midPoint, b, pb, kappa: kappa, depth: depth + 1)
            }
        }

        var previous = pen.position(at: sStart)
        for (a, b) in zip(knots, knots.dropFirst()) where b - a > 1e-12 {
            let kappa = track.sample(at: (a + b) / 2).curvature
            let steps = max(1, Int((b - a) / maxStep) + 1)
            for i in 0..<steps {
                let s1 = i == steps - 1 ? b : a + (b - a) * Double(i + 1) / Double(steps)
                let s0 = a + (b - a) * Double(i) / Double(steps)
                let next = pen.position(at: s1)
                subdivide(s0, previous, s1, next, kappa: kappa, depth: 0)
                previous = next
            }
        }
        return pieces
    }
}

// MARK: - Vector artwork and its writers

/// A pattern as resolution-independent vector artwork on a square page:
/// the background plus one closed Bézier path per layer, bottom first, in
/// page coordinates (y down, origin top-left, one unit = one point). It is
/// framed exactly like the PNG export; `svg()` and `pdf()` only translate it,
/// so both formats show the same picture.
public struct VectorArtwork {
    public struct Stroke {
        public let path: CGPath
        public let color: RGBAColor
        public let width: Double
    }

    /// Default page edge in points.
    public static let defaultSize: Double = 1200
    /// Name written as the PDF creator.
    public static let creator = "Rosettica"

    public let size: Double
    public let background: RGBAColor
    public let strokes: [Stroke]

    /// - Parameter tolerance: maximum deviation from the exact curve, in points.
    public init(pattern: RosettePattern, size: Double = defaultSize, tolerance: Double = 0.01) {
        self.size = size
        self.background = pattern.background
        let radius = pattern.viewportRadius
        let scale = size / (2 * radius)
        let world = CGAffineTransform(translationX: size / 2, y: size / 2).scaledBy(x: scale, y: -scale)
        let widthScale = size / RosettePattern.lineWidthReferenceSize
        strokes = pattern.layers.map { layer in
            // Same mapping as the canvas: form rotation, then world → page.
            let t = layer.rotationDegrees == 0
                ? world
                : CGAffineTransform(rotationAngle: -layer.rotationDegrees * .pi / 180).concatenating(world)
            let pieces = CurveEngine.bezierPieces(for: layer.curveParameters, tolerance: tolerance / scale)
            let path = CGMutablePath()
            if let first = pieces.first {
                path.move(to: first.p0.applying(t))
                for (i, piece) in pieces.enumerated() {
                    // The curve closes exactly; snap the last end onto the start.
                    let end = i == pieces.count - 1 ? first.p0 : piece.p3
                    path.addCurve(to: end.applying(t), control1: piece.c1.applying(t), control2: piece.c2.applying(t))
                }
                path.closeSubpath()
            }
            return Stroke(path: path, color: layer.color, width: layer.lineWidth * widthScale)
        }
    }

    // MARK: SVG

    public func svg() -> String {
        let edge = Self.fixed(Int((size * 100).rounded()))
        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(edge)pt\" height=\"\(edge)pt\""
            + " viewBox=\"0 0 \(edge) \(edge)\">\n"
        out += "<rect width=\"\(edge)\" height=\"\(edge)\"\(Self.paint("fill", background))/>\n"
        for stroke in strokes {
            out += "<path fill=\"none\"\(Self.paint("stroke", stroke.color))"
                + " stroke-width=\"\(Self.fixed(Int((stroke.width * 1000).rounded()), decimals: 3))\""
                + " stroke-linecap=\"round\" stroke-linejoin=\"round\""
                + " d=\"\(Self.pathData(stroke.path))\"/>\n"
        }
        out += "</svg>\n"
        return out
    }

    /// ` stroke="#rrggbb"` (plus ` stroke-opacity` when translucent).
    private static func paint(_ attribute: String, _ color: RGBAColor) -> String {
        func byte(_ v: Double) -> Int { Int(max(0, min(255, (v * 255).rounded()))) }
        var text = String(format: " %@=\"#%02x%02x%02x\"", attribute,
                          byte(color.red), byte(color.green), byte(color.blue))
        if color.alpha < 1 {
            text += " \(attribute)-opacity=\"\(fixed(Int((max(0, color.alpha) * 1000).rounded()), decimals: 3))\""
        }
        return text
    }

    /// Path data with coordinates rounded to 0.01 pt. Curves use relative
    /// coordinates, computed from the *rounded* absolute positions so that
    /// rounding never accumulates along the path.
    static func pathData(_ path: CGPath) -> String {
        var d = ""
        var current = (x: 0, y: 0)
        var lastCommand: Character = " "
        func q(_ p: CGPoint) -> (x: Int, y: Int) {
            (Int((p.x * 100).rounded()), Int((p.y * 100).rounded()))
        }
        func emit(_ value: Int) {
            // A minus sign separates numbers on its own.
            if value >= 0, let last = d.last, last != lastCommand { d += " " }
            d += fixed(value)
        }
        // Repeated commands are implicit; `emit` adds the separator.
        func command(_ c: Character) {
            if c != lastCommand || c == "M" {
                d.append(c)
                lastCommand = c
            }
        }
        path.applyWithBlock { element in
            let pts = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint:
                let p = q(pts[0])
                command("M")
                emit(p.x); emit(p.y)
                current = p
            case .addLineToPoint:
                let p = q(pts[0])
                command("l")
                emit(p.x - current.x); emit(p.y - current.y)
                current = p
            case .addCurveToPoint:
                let c1 = q(pts[0]), c2 = q(pts[1]), p = q(pts[2])
                command("c")
                emit(c1.x - current.x); emit(c1.y - current.y)
                emit(c2.x - current.x); emit(c2.y - current.y)
                emit(p.x - current.x); emit(p.y - current.y)
                current = p
            case .addQuadCurveToPoint:
                let c = q(pts[0]), p = q(pts[1])
                command("q")
                emit(c.x - current.x); emit(c.y - current.y)
                emit(p.x - current.x); emit(p.y - current.y)
                current = p
            case .closeSubpath:
                d.append("Z")
                lastCommand = "Z"
            @unknown default:
                break
            }
        }
        return d
    }

    /// Fixed-point decimal of `value / 10^decimals` without trailing zeros
    /// ("12.5", "-0.07", "3"). Hand-rolled: String(format:) is far too slow
    /// for hundreds of thousands of coordinates.
    static func fixed(_ value: Int, decimals: Int = 2) -> String {
        var divisor = 1
        for _ in 0..<decimals { divisor *= 10 }
        let magnitude = value.magnitude
        let whole = magnitude / UInt(divisor)
        var fraction = magnitude % UInt(divisor)
        var text = value < 0 ? "-" : ""
        text += String(whole)
        if fraction != 0 {
            var digits = decimals
            while fraction % 10 == 0 {
                fraction /= 10
                digits -= 1
            }
            let raw = String(fraction)
            text += "." + String(repeating: "0", count: digits - raw.count) + raw
        }
        return text
    }

    // MARK: PDF

    /// A single square page, `size` points wide, colors in sRGB. The
    /// document info names only the creator — never an author.
    public func pdf() -> Data? {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: size, height: size)
        let info = [kCGPDFContextCreator as String: Self.creator] as CFDictionary
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        func color(_ c: RGBAColor) -> CGColor {
            CGColor(colorSpace: space, components: [c.red, c.green, c.blue, c.alpha])
                ?? CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
        }
        context.beginPDFPage(nil)
        // The artwork is laid out y-down like the canvas; PDF space is y-up.
        context.translateBy(x: 0, y: size)
        context.scaleBy(x: 1, y: -1)
        context.setFillColor(color(background))
        context.fill(mediaBox)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes {
            context.setStrokeColor(color(stroke.color))
            context.setLineWidth(stroke.width)
            context.addPath(stroke.path)
            context.strokePath()
        }
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
