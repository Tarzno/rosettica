import CoreGraphics
import Foundation

/// A device-independent sRGB color that can be serialized in documents.
public struct RGBAColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let black = RGBAColor(red: 0, green: 0, blue: 0)
    /// The classic ballpoint-pen blue of the original toy.
    public static let classicBlue = RGBAColor(red: 0.10, green: 0.22, blue: 0.75)
    public static let classicRed = RGBAColor(red: 0.82, green: 0.12, blue: 0.16)
    public static let classicGreen = RGBAColor(red: 0.05, green: 0.55, blue: 0.28)
}

@inlinable
func unitVector(angle: Double) -> CGVector {
    CGVector(dx: cos(angle), dy: sin(angle))
}

extension CGPoint {
    @inlinable
    func offset(by v: CGVector, scaled k: Double = 1) -> CGPoint {
        CGPoint(x: x + v.dx * k, y: y + v.dy * k)
    }

    @inlinable
    func distance(to other: CGPoint) -> Double {
        hypot(other.x - x, other.y - y)
    }
}
