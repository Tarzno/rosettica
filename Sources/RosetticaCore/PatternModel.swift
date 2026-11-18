import CoreGraphics
import Foundation

/// One stamped curve in a document.
public struct RosetteLayer: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var form: FormID
    public var side: RollSide
    public var cogTeeth: Int
    public var penFraction: Double
    public var phaseTeeth: Double
    /// Rotation of the whole form (and therefore the pattern) in degrees.
    public var rotationDegrees: Double
    public var lineWidth: Double
    public var color: RGBAColor

    public init(
        id: UUID = UUID(),
        form: FormID,
        side: RollSide,
        cogTeeth: Int,
        penFraction: Double,
        phaseTeeth: Double = 0,
        rotationDegrees: Double = 0,
        lineWidth: Double = 1.6,
        color: RGBAColor = .classicBlue
    ) {
        self.id = id
        self.form = form
        self.side = side
        self.cogTeeth = cogTeeth
        self.penFraction = penFraction
        self.phaseTeeth = phaseTeeth
        self.rotationDegrees = rotationDegrees
        self.lineWidth = lineWidth
        self.color = color
    }

    // Documents written before the rotation feature lack the key; default it
    // to 0 so older .rosettica files keep loading.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        form = try container.decode(FormID.self, forKey: .form)
        side = try container.decode(RollSide.self, forKey: .side)
        cogTeeth = try container.decode(Int.self, forKey: .cogTeeth)
        penFraction = try container.decode(Double.self, forKey: .penFraction)
        phaseTeeth = try container.decode(Double.self, forKey: .phaseTeeth)
        rotationDegrees = try container.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
        lineWidth = try container.decode(Double.self, forKey: .lineWidth)
        color = try container.decode(RGBAColor.self, forKey: .color)
    }

    public var curveParameters: CurveParameters {
        CurveParameters(
            form: form,
            side: side,
            cogTeeth: cogTeeth,
            penFraction: penFraction,
            phaseTeeth: phaseTeeth
        )
    }
}

/// The document content: a background color and stamped layers, bottom first.
public struct RosettePattern: Codable, Hashable, Sendable {
    public var background: RGBAColor
    public var layers: [RosetteLayer]

    public init(background: RGBAColor = .white, layers: [RosetteLayer] = []) {
        self.background = background
        self.layers = layers
    }

    /// Upper bound (in scene units) on the distance any catalog curve can
    /// reach from the origin; the drawing viewport is fitted dynamically to
    /// the actual content and never needs more than this.
    public static let maxWorldRadius: Double = 400
}
