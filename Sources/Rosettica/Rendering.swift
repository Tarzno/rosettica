import CoreGraphics
import Foundation
import RosetticaCore

/// Main-thread cache of computed curve paths keyed by their parameters.
@MainActor
final class PathCache {
    static let shared = PathCache()

    private var paths: [CurveParameters: CGPath] = [:]
    private var radii: [CurveParameters: Double] = [:]
    private var pointLists: [CurveParameters: [CGPoint]] = [:]
    private var trackPaths: [String: CGPath] = [:]
    private var teethPaths: [String: CGPath] = [:]
    private var trackRadii: [String: Double] = [:]

    func path(for params: CurveParameters) -> CGPath {
        if let cached = paths[params] { return cached }
        if paths.count > 128 {
            paths.removeAll()
            radii.removeAll()
        }
        let points = CurveEngine.points(for: params)
        let path = CGMutablePath()
        if let first = points.first {
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
        paths[params] = path
        radii[params] = CurveEngine.boundingRadius(of: points)
        return path
    }

    func boundingRadius(for params: CurveParameters) -> Double {
        if radii[params] == nil {
            _ = path(for: params)
        }
        return radii[params] ?? 0
    }

    /// The curve's sample points, uniform in rolled arc length — used for
    /// physically correct partial drawing during animation.
    func points(for params: CurveParameters) -> [CGPoint] {
        if let cached = pointLists[params] { return cached }
        if pointLists.count > 6 {
            pointLists.removeAll()
        }
        let points = CurveEngine.points(for: params)
        pointLists[params] = points
        return points
    }

    /// Short tick marks along the track, one per tooth, pointing toward the
    /// side the cog rolls on.
    func formTeethPath(form: FormID, side: RollSide) -> CGPath {
        let key = "\(form.rawValue)-\(side.rawValue)"
        if let cached = teethPaths[key] { return cached }
        let rosetteForm = RosetteCatalog.form(form)
        let track = rosetteForm.track(for: side)
        let teeth = rosetteForm.teeth(for: side)
        let length = RosetteCatalog.toothPitch * 0.5
        let direction: Double = side == .inside ? 1 : -1
        let path = CGMutablePath()
        for i in 0..<teeth {
            let sample = track.sample(at: Double(i) * RosetteCatalog.toothPitch)
            let tip = CGPoint(
                x: sample.position.x + direction * length * sample.leftNormal.dx,
                y: sample.position.y + direction * length * sample.leftNormal.dy
            )
            path.move(to: sample.position)
            path.addLine(to: tip)
        }
        teethPaths[key] = path
        return path
    }

    func trackPath(form: FormID, side: RollSide) -> CGPath {
        let key = "\(form.rawValue)-\(side.rawValue)"
        if let cached = trackPaths[key] { return cached }
        let track = RosetteCatalog.form(form).track(for: side)
        let steps = 720
        let path = CGMutablePath()
        path.move(to: track.sample(at: 0).position)
        for i in 1...steps {
            path.addLine(to: track.sample(at: track.totalLength * Double(i) / Double(steps)).position)
        }
        path.closeSubpath()
        trackPaths[key] = path
        return path
    }

    func trackRadius(form: FormID, side: RollSide) -> Double {
        let key = "\(form.rawValue)-\(side.rawValue)"
        if let cached = trackRadii[key] { return cached }
        let radius = CurveEngine.trackRadius(form: form, side: side)
        trackRadii[key] = radius
        return radius
    }
}

@MainActor
enum PatternRenderer {
    /// World radius (scene units) needed to show the pattern plus, if given,
    /// the currently configured curve and its form outline.
    static func viewportRadius(pattern: RosettePattern, extra: CurveParameters?) -> Double {
        var radius = 0.0
        for layer in pattern.layers {
            radius = max(radius, PathCache.shared.boundingRadius(for: layer.curveParameters))
        }
        if let extra {
            radius = max(radius, PathCache.shared.boundingRadius(for: extra))
            radius = max(radius, PathCache.shared.trackRadius(form: extra.form, side: extra.side))
        }
        return RosettePattern.viewportRadius(contentRadius: radius)
    }

    /// Maps world coordinates (y up, origin at center) onto a view rect
    /// (y down, origin top-left).
    static func worldTransform(size: CGSize, worldRadius: Double) -> CGAffineTransform {
        let scale = min(size.width, size.height) / (2 * worldRadius)
        return CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
            .scaledBy(x: scale, y: -scale)
    }

    /// Line widths are specified for a 600 pt canvas and scale with the view.
    static func lineWidthScale(size: CGSize) -> Double {
        min(size.width, size.height) / RosettePattern.lineWidthReferenceSize
    }

    /// World transform for one layer: the form rotation (counterclockwise on
    /// screen for positive degrees) followed by the world-to-view mapping.
    static func layerTransform(rotationDegrees: Double, world: CGAffineTransform) -> CGAffineTransform {
        guard rotationDegrees != 0 else { return world }
        return CGAffineTransform(rotationAngle: -rotationDegrees * .pi / 180).concatenating(world)
    }

    /// Renders the finished pattern (no guides) into a y-down CGContext.
    /// Used for printing and PNG export; `VectorArtwork` frames SVG/PDF the same way.
    static func render(pattern: RosettePattern, in ctx: CGContext, rect: CGRect) {
        ctx.saveGState()
        ctx.setFillColor(pattern.background.cgColor)
        ctx.fill(rect)

        let radius = viewportRadius(pattern: pattern, extra: nil)
        let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: min(rect.width, rect.height) / (2 * radius), y: -min(rect.width, rect.height) / (2 * radius))
        let widthScale = lineWidthScale(size: rect.size)

        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for layer in pattern.layers {
            var layerT = layerTransform(rotationDegrees: layer.rotationDegrees, world: transform)
            guard let path = PathCache.shared.path(for: layer.curveParameters).copy(using: &layerT) else { continue }
            ctx.addPath(path)
            ctx.setStrokeColor(layer.color.cgColor)
            ctx.setLineWidth(layer.lineWidth * widthScale)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }
}
