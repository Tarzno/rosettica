import CoreGraphics
import Foundation

/// Everything that determines the shape of one traced curve.
public struct CurveParameters: Hashable, Sendable {
    public var form: FormID
    public var side: RollSide
    public var cogTeeth: Int
    /// Pen hole position as a fraction of the cog radius (0 = center).
    public var penFraction: Double
    /// Starting contact position along the track, in teeth.
    public var phaseTeeth: Double

    public init(form: FormID, side: RollSide, cogTeeth: Int, penFraction: Double, phaseTeeth: Double = 0) {
        self.form = form
        self.side = side
        self.cogTeeth = cogTeeth
        self.penFraction = penFraction
        self.phaseTeeth = phaseTeeth
    }
}

/// Simulates a cog rolling without slipping along a track.
///
/// With the cog center on the ε-side of the track (ε = +1 inside/left,
/// −1 outside/right), the cog's absolute rotation obeys
/// dψ/ds = κ(s) − ε/r, so ψ(s) = ψ₀ + turning(s) − ε·s/r.
/// On a circular track this reduces exactly to the classic
/// hypotrochoid/epitrochoid equations.
public enum CurveEngine {
    public static func gcd(_ a: Int, _ b: Int) -> Int {
        var a = a, b = b
        while b != 0 { (a, b) = (b, a % b) }
        return abs(a)
    }

    /// Number of laps around the track before the pattern closes exactly.
    public static func laps(formTeeth: Int, cogTeeth: Int) -> Int {
        cogTeeth / gcd(formTeeth, cogTeeth)
    }

    /// Whether the cog can physically roll on the chosen side of the form.
    public static func fits(_ p: CurveParameters) -> Bool {
        switch p.side {
        case .inside:
            return p.cogTeeth < RosetteCatalog.form(p.form).insideCogTeethLimit
        case .outside:
            return true
        }
    }

    public static func laps(for p: CurveParameters) -> Int {
        laps(formTeeth: RosetteCatalog.form(p.form).teeth(for: p.side), cogTeeth: p.cogTeeth)
    }

    /// The pen positions of the complete (closed) curve.
    /// The last point coincides with the first.
    public static func points(
        for p: CurveParameters,
        samplesPerTooth: Double = 8,
        maxPoints: Int = 60_000
    ) -> [CGPoint] {
        let form = RosetteCatalog.form(p.form)
        let track = form.track(for: p.side)
        let formTeeth = form.teeth(for: p.side)
        let lapCount = laps(formTeeth: formTeeth, cogTeeth: p.cogTeeth)
        let totalTeeth = Double(formTeeth * lapCount)

        var sampleCount = Int(totalTeeth * samplesPerTooth)
        sampleCount = min(max(sampleCount, 64), maxPoints)

        let r = RosetteCatalog.cogRadius(teeth: p.cogTeeth)
        let d = p.penFraction * r
        let eps: Double = p.side == .inside ? 1 : -1
        let s0 = p.phaseTeeth * RosetteCatalog.toothPitch
        let sTotal = totalTeeth * RosetteCatalog.toothPitch

        // The pen starts pointing from the cog center toward the contact point.
        let start = track.sample(at: s0)
        let psi0 = atan2(-eps * start.leftNormal.dy, -eps * start.leftNormal.dx)
        let turning0 = track.turning(at: s0)

        var points: [CGPoint] = []
        points.reserveCapacity(sampleCount + 1)
        for i in 0...sampleCount {
            let s = s0 + sTotal * Double(i) / Double(sampleCount)
            let sample = track.sample(at: s)
            let cx = sample.position.x + eps * r * sample.leftNormal.dx
            let cy = sample.position.y + eps * r * sample.leftNormal.dy
            let psi = psi0 + (track.turning(at: s) - turning0) - eps * (s - s0) / r
            points.append(CGPoint(x: cx + d * cos(psi), y: cy + d * sin(psi)))
        }
        return points
    }

    /// Where the cog and pen are at a given moment of drawing the curve.
    public struct RollingState {
        /// Point where the cog touches the track.
        public let contactPoint: CGPoint
        public let cogCenter: CGPoint
        /// Absolute rotation ψ of the cog in world coordinates.
        public let cogRotation: Double
        public let penPosition: CGPoint
    }

    /// The exact rolling state at `progress` (0...1) through the complete
    /// curve. `rollingState(progress: k/n).penPosition` coincides with
    /// `points(...)[k]` for a curve sampled with n+1 points.
    public static func rollingState(for p: CurveParameters, progress: Double) -> RollingState {
        let form = RosetteCatalog.form(p.form)
        let track = form.track(for: p.side)
        let formTeeth = form.teeth(for: p.side)
        let lapCount = laps(formTeeth: formTeeth, cogTeeth: p.cogTeeth)
        let sTotal = Double(formTeeth * lapCount) * RosetteCatalog.toothPitch
        let s0 = p.phaseTeeth * RosetteCatalog.toothPitch
        let s = s0 + progress * sTotal

        let r = RosetteCatalog.cogRadius(teeth: p.cogTeeth)
        let d = p.penFraction * r
        let eps: Double = p.side == .inside ? 1 : -1

        let start = track.sample(at: s0)
        let psi0 = atan2(-eps * start.leftNormal.dy, -eps * start.leftNormal.dx)
        let turning0 = track.turning(at: s0)

        let sample = track.sample(at: s)
        let center = CGPoint(
            x: sample.position.x + eps * r * sample.leftNormal.dx,
            y: sample.position.y + eps * r * sample.leftNormal.dy
        )
        let psi = psi0 + (track.turning(at: s) - turning0) - eps * (s - s0) / r
        return RollingState(
            contactPoint: sample.position,
            cogCenter: center,
            cogRotation: psi,
            penPosition: CGPoint(x: center.x + d * cos(psi), y: center.y + d * sin(psi))
        )
    }

    /// Largest distance from the origin over the given points.
    public static func boundingRadius(of points: [CGPoint]) -> Double {
        points.reduce(0) { max($0, hypot($1.x, $1.y)) }
    }

    /// Largest distance from the origin the track outline itself reaches.
    public static func trackRadius(form: FormID, side: RollSide) -> Double {
        let track = RosetteCatalog.form(form).track(for: side)
        let steps = 256
        var best = 0.0
        for i in 0..<steps {
            let p = track.sample(at: track.totalLength * Double(i) / Double(steps)).position
            best = max(best, hypot(p.x, p.y))
        }
        return best
    }
}
