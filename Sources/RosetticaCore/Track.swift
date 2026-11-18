import CoreGraphics
import Foundation

/// Position and differential data of a track at a given arc length.
public struct TrackSample {
    public let position: CGPoint
    /// Unit tangent in the direction of travel.
    public let tangent: CGVector
    /// Unit normal, 90° counterclockwise from the tangent.
    public let leftNormal: CGVector
    /// Signed curvature; positive when the track turns left.
    public let curvature: Double
}

/// One primitive of a track: a straight segment or a circular arc.
public enum TrackElement {
    case segment(from: CGPoint, to: CGPoint)
    /// `sweep` > 0 is counterclockwise.
    case arc(center: CGPoint, radius: Double, startAngle: Double, sweep: Double)

    public var length: Double {
        switch self {
        case let .segment(from, to):
            return from.distance(to: to)
        case let .arc(_, radius, _, sweep):
            return abs(sweep) * radius
        }
    }

    /// Total turning of the tangent over the element.
    public var turning: Double {
        switch self {
        case .segment:
            return 0
        case let .arc(_, _, _, sweep):
            return sweep
        }
    }

    func sample(at s: Double) -> TrackSample {
        switch self {
        case let .segment(from, to):
            let len = length
            let t = len > 0 ? s / len : 0
            let tangent = CGVector(dx: (to.x - from.x) / len, dy: (to.y - from.y) / len)
            return TrackSample(
                position: CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t),
                tangent: tangent,
                leftNormal: CGVector(dx: -tangent.dy, dy: tangent.dx),
                curvature: 0
            )
        case let .arc(center, radius, startAngle, sweep):
            let direction: Double = sweep >= 0 ? 1 : -1
            let angle = startAngle + direction * s / radius
            let radial = unitVector(angle: angle)
            let tangent = CGVector(dx: -direction * radial.dy, dy: direction * radial.dx)
            return TrackSample(
                position: center.offset(by: radial, scaled: radius),
                tangent: tangent,
                leftNormal: CGVector(dx: -tangent.dy, dy: tangent.dx),
                curvature: direction / radius
            )
        }
    }

    func turning(at s: Double) -> Double {
        switch self {
        case .segment:
            return 0
        case let .arc(_, radius, _, sweep):
            return (sweep >= 0 ? 1 : -1) * s / radius
        }
    }

    func translated(by v: CGVector) -> TrackElement {
        switch self {
        case let .segment(from, to):
            return .segment(from: from.offset(by: v), to: to.offset(by: v))
        case let .arc(center, radius, startAngle, sweep):
            return .arc(center: center.offset(by: v), radius: radius, startAngle: startAngle, sweep: sweep)
        }
    }
}

/// A closed track built from segments and arcs, parametrized by arc length.
/// Tracks are traversed counterclockwise with the interior on the left.
public struct Track {
    public let elements: [TrackElement]
    public let totalLength: Double
    /// Total turning of the tangent over one full lap (2π for a simple closed CCW track).
    public let totalTurning: Double

    private let startLengths: [Double]
    private let startTurnings: [Double]

    public init(elements: [TrackElement]) {
        self.elements = elements
        var lengths: [Double] = []
        var turnings: [Double] = []
        var s = 0.0
        var turn = 0.0
        for element in elements {
            lengths.append(s)
            turnings.append(turn)
            s += element.length
            turn += element.turning
        }
        self.startLengths = lengths
        self.startTurnings = turnings
        self.totalLength = s
        self.totalTurning = turn
    }

    /// Arc length at which each element begins (the first is 0). The track's
    /// curvature is constant within an element and may jump at these joints.
    public var elementStartLengths: [Double] { startLengths }

    private func wrapped(_ s: Double) -> Double {
        let r = s.truncatingRemainder(dividingBy: totalLength)
        return r < 0 ? r + totalLength : r
    }

    private func elementIndex(for s: Double) -> Int {
        // Few elements per track; a linear scan is fine.
        var index = elements.count - 1
        for i in 1..<elements.count where startLengths[i] > s {
            index = i - 1
            break
        }
        return elements.isEmpty ? 0 : index
    }

    /// Sample the track at arc length `s` (wrapped onto [0, totalLength)).
    public func sample(at s: Double) -> TrackSample {
        let sw = wrapped(s)
        let i = elementIndex(for: sw)
        return elements[i].sample(at: sw - startLengths[i])
    }

    /// Accumulated turning of the tangent from arc length 0 to `s`.
    /// `s` may exceed the track length; full laps each add `totalTurning`.
    public func turning(at s: Double) -> Double {
        let laps = (s / totalLength).rounded(.down)
        let sw = s - laps * totalLength
        let i = elementIndex(for: sw)
        return laps * totalTurning + startTurnings[i] + elements[i].turning(at: sw - startLengths[i])
    }

    /// The largest cog radius that can roll on the concave (inside) face of
    /// this track while keeping contact: it must be smaller than the radius
    /// of the tightest left-turning arc.
    public var maxInsideRollingRadius: Double {
        var best = Double.infinity
        for element in elements {
            if case let .arc(_, radius, _, sweep) = element, sweep > 0 {
                best = min(best, radius)
            }
        }
        return best
    }
}
