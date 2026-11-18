import CoreGraphics
import Foundation

public enum FormID: String, Codable, CaseIterable, Sendable {
    case ringSmall
    case ringLarge
    case triangle
    case square
    case pentagon
    case hexagon
    case stadium
}

public enum RollSide: String, Codable, CaseIterable, Sendable {
    case inside
    case outside
}

/// Geometry recipe for a rounded regular polygon: `sides` straight edges of
/// `edgeTeeth` teeth each, joined by corner arcs of `cornerTeeth` teeth each.
/// `sides == 1` with no edge yields a plain circle; `sides == 2` a stadium.
struct PolygonSpec: Hashable {
    let sides: Int
    let edgeTeeth: Int
    let cornerTeeth: Int

    var teeth: Int { sides * (edgeTeeth + cornerTeeth) }
}

/// One of the plastic frames of the toy: a ring, polygon, or stadium the cogs
/// roll inside of or around.
public struct RosetteForm: Sendable {
    public let id: FormID
    public let name: String
    let insideSpec: PolygonSpec
    let outsideSpec: PolygonSpec

    public func teeth(for side: RollSide) -> Int {
        spec(for: side).teeth
    }

    /// Cogs must have strictly fewer teeth than this to roll on the inside.
    public var insideCogTeethLimit: Int {
        insideSpec.sides * insideSpec.cornerTeeth
    }

    public func allowedCogTeeth(for side: RollSide) -> [Int] {
        switch side {
        case .inside:
            return RosetteCatalog.cogTeethOptions.filter { $0 < insideCogTeethLimit }
        case .outside:
            return RosetteCatalog.cogTeethOptions
        }
    }

    public func track(for side: RollSide) -> Track {
        RosetteCatalog.track(for: spec(for: side))
    }

    private func spec(for side: RollSide) -> PolygonSpec {
        side == .inside ? insideSpec : outsideSpec
    }
}

public enum RosetteCatalog {
    /// Scene units per gear tooth. With a pitch of 2π, a circular track of
    /// T teeth has radius exactly T in scene units.
    public static let toothPitch: Double = 2.0 * .pi

    /// The classic wheel set (tooth counts of the original toy's cogs).
    public static let cogTeethOptions = [24, 30, 32, 36, 40, 45, 48, 52, 56, 60, 63, 64, 72, 75, 80, 84]

    public static func cogRadius(teeth: Int) -> Double {
        Double(teeth) * toothPitch / (2.0 * .pi)
    }

    public static let forms: [RosetteForm] = [
        RosetteForm(
            id: .ringSmall, name: "Ring 96/105",
            insideSpec: PolygonSpec(sides: 1, edgeTeeth: 0, cornerTeeth: 96),
            outsideSpec: PolygonSpec(sides: 1, edgeTeeth: 0, cornerTeeth: 105)
        ),
        RosetteForm(
            id: .ringLarge, name: "Ring 144/150",
            insideSpec: PolygonSpec(sides: 1, edgeTeeth: 0, cornerTeeth: 144),
            outsideSpec: PolygonSpec(sides: 1, edgeTeeth: 0, cornerTeeth: 150)
        ),
        RosetteForm(
            id: .triangle, name: "Triangle",
            insideSpec: PolygonSpec(sides: 3, edgeTeeth: 32, cornerTeeth: 16),
            outsideSpec: PolygonSpec(sides: 3, edgeTeeth: 32, cornerTeeth: 16)
        ),
        RosetteForm(
            id: .square, name: "Square",
            insideSpec: PolygonSpec(sides: 4, edgeTeeth: 30, cornerTeeth: 12),
            outsideSpec: PolygonSpec(sides: 4, edgeTeeth: 30, cornerTeeth: 12)
        ),
        RosetteForm(
            id: .pentagon, name: "Pentagon",
            insideSpec: PolygonSpec(sides: 5, edgeTeeth: 21, cornerTeeth: 9),
            outsideSpec: PolygonSpec(sides: 5, edgeTeeth: 21, cornerTeeth: 9)
        ),
        RosetteForm(
            id: .hexagon, name: "Hexagon",
            insideSpec: PolygonSpec(sides: 6, edgeTeeth: 16, cornerTeeth: 8),
            outsideSpec: PolygonSpec(sides: 6, edgeTeeth: 16, cornerTeeth: 8)
        ),
        RosetteForm(
            id: .stadium, name: "Oval",
            insideSpec: PolygonSpec(sides: 2, edgeTeeth: 42, cornerTeeth: 42),
            outsideSpec: PolygonSpec(sides: 2, edgeTeeth: 42, cornerTeeth: 42)
        ),
    ]

    public static func form(_ id: FormID) -> RosetteForm {
        forms.first { $0.id == id }!
    }

    // MARK: - Track construction

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var trackCache: [PolygonSpec: Track] = [:]

    static func track(for spec: PolygonSpec) -> Track {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = trackCache[spec] {
            return cached
        }
        let built = buildTrack(spec)
        trackCache[spec] = built
        return built
    }

    /// Turtle-walks the rounded polygon counterclockwise: for each side, a
    /// straight edge followed by a left-turning corner arc. The resulting
    /// track is recentered on the centroid of its arc centers (the exact
    /// center for regular shapes).
    private static func buildTrack(_ spec: PolygonSpec) -> Track {
        let turnPerCorner = 2.0 * .pi / Double(spec.sides)
        let cornerRadius = Double(spec.cornerTeeth) * toothPitch / turnPerCorner
        let edgeLength = Double(spec.edgeTeeth) * toothPitch

        var elements: [TrackElement] = []
        var arcCenters: [CGPoint] = []
        var position = CGPoint.zero
        var heading = 0.0

        for _ in 0..<spec.sides {
            if edgeLength > 0 {
                let end = position.offset(by: unitVector(angle: heading), scaled: edgeLength)
                elements.append(.segment(from: position, to: end))
                position = end
            }
            let center = position.offset(by: unitVector(angle: heading + .pi / 2), scaled: cornerRadius)
            let startAngle = heading - .pi / 2
            elements.append(.arc(center: center, radius: cornerRadius, startAngle: startAngle, sweep: turnPerCorner))
            arcCenters.append(center)
            position = center.offset(by: unitVector(angle: startAngle + turnPerCorner), scaled: cornerRadius)
            heading += turnPerCorner
        }

        let cx = arcCenters.map(\.x).reduce(0, +) / Double(arcCenters.count)
        let cy = arcCenters.map(\.y).reduce(0, +) / Double(arcCenters.count)
        let recentered = elements.map { $0.translated(by: CGVector(dx: -cx, dy: -cy)) }
        return Track(elements: recentered)
    }
}
