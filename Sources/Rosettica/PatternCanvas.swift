import SwiftUI
import RosetticaCore

struct CanvasAnimation: Equatable {
    var layerID: UUID
    var start: Date
    var duration: Double
}

/// Draws a pattern's layers plus, optionally, the current settings as a
/// translucent "ghost" with the toothed form outline and cog as guides.
/// While a layer is being animated, the cog rolls along the form with its
/// pen exactly at the end of the partially drawn line.
struct PatternCanvas: View {
    var pattern: RosettePattern
    var ghost: RosetteLayer?
    var showGuides: Bool
    var animation: CanvasAnimation?
    /// When set, the viewport is pinned to this world radius instead of being
    /// fitted to the content — used by the demo so the view doesn't rescale
    /// as the composition's layers appear one by one.
    var fixedWorldRadius: Double? = nil

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: animation == nil)) { timeline in
            Canvas { ctx, size in
                draw(&ctx, size: size, date: timeline.date)
            }
        }
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, date: Date) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(pattern.background.swiftUIColor))
        guard size.width > 10, size.height > 10 else { return }

        let radius = fixedWorldRadius
            ?? PatternRenderer.viewportRadius(pattern: pattern, extra: ghost?.curveParameters)
        let transform = PatternRenderer.worldTransform(size: size, worldRadius: radius)
        let widthScale = PatternRenderer.lineWidthScale(size: size)

        var animatingLayer: RosetteLayer?
        var animationProgress = 1.0

        for layer in pattern.layers {
            var layerT = PatternRenderer.layerTransform(rotationDegrees: layer.rotationDegrees, world: transform)
            let style = StrokeStyle(lineWidth: layer.lineWidth * widthScale, lineCap: .round, lineJoin: .round)

            if let animation, animation.layerID == layer.id {
                let progress = min(max(date.timeIntervalSince(animation.start) / animation.duration, 0), 1)
                if progress < 1 {
                    animatingLayer = layer
                    animationProgress = progress
                    // Partial reveal by point index: points are uniform in
                    // rolled arc length, so the cog rolls at constant speed
                    // and the line ends exactly at the pen.
                    let points = PathCache.shared.points(for: layer.curveParameters)
                    let k = max(1, Int(progress * Double(points.count - 1)))
                    let partial = CGMutablePath()
                    partial.move(to: points[0])
                    for i in 1...k {
                        partial.addLine(to: points[i])
                    }
                    if let cg = partial.copy(using: &layerT) {
                        ctx.stroke(Path(cg), with: .color(layer.color.swiftUIColor), style: style)
                    }
                    continue
                }
            }

            if let cg = PathCache.shared.path(for: layer.curveParameters).copy(using: &layerT) {
                ctx.stroke(Path(cg), with: .color(layer.color.swiftUIColor), style: style)
            }
        }

        if let animatingLayer {
            // The rolling cog steals the show; static guides would clutter it.
            drawFormOutline(&ctx, layer: animatingLayer, world: transform)
            drawCog(&ctx, layer: animatingLayer, progress: animationProgress, world: transform, animated: true)
        } else if let ghost, showGuides {
            drawFormOutline(&ctx, layer: ghost, world: transform)
            drawCog(&ctx, layer: ghost, progress: 0, world: transform, animated: false)
            drawGhostCurve(&ctx, ghost: ghost, world: transform, widthScale: widthScale)
        }
    }

    private var guideColor: Color {
        pattern.background.luminance > 0.5
            ? Color.black.opacity(0.32)
            : Color.white.opacity(0.4)
    }

    private func drawFormOutline(_ ctx: inout GraphicsContext, layer: RosetteLayer, world: CGAffineTransform) {
        var t = PatternRenderer.layerTransform(rotationDegrees: layer.rotationDegrees, world: world)
        if let outline = PathCache.shared.trackPath(form: layer.form, side: layer.side).copy(using: &t) {
            ctx.stroke(Path(outline), with: .color(guideColor), style: StrokeStyle(lineWidth: 1))
        }
        if let teeth = PathCache.shared.formTeethPath(form: layer.form, side: layer.side).copy(using: &t) {
            ctx.stroke(Path(teeth), with: .color(guideColor), style: StrokeStyle(lineWidth: 1))
        }
    }

    /// Draws the cog — toothed rim, center, pen arm, and pen hole — at the
    /// given progress through the curve.
    private func drawCog(_ ctx: inout GraphicsContext, layer: RosetteLayer, progress: Double, world: CGAffineTransform, animated: Bool) {
        let t = PatternRenderer.layerTransform(rotationDegrees: layer.rotationDegrees, world: world)
        let state = CurveEngine.rollingState(for: layer.curveParameters, progress: progress)
        let r = RosetteCatalog.cogRadius(teeth: layer.cogTeeth)
        let scale = world.a

        let viewCenter = state.cogCenter.applying(t)
        let viewPen = state.penPosition.applying(t)
        let viewRadius = r * scale
        let color = animated ? guideColor.opacity(1) : guideColor

        // Rim.
        ctx.stroke(
            Path(ellipseIn: CGRect(
                x: viewCenter.x - viewRadius, y: viewCenter.y - viewRadius,
                width: 2 * viewRadius, height: 2 * viewRadius
            )),
            with: .color(color),
            style: StrokeStyle(lineWidth: animated ? 1.5 : 1, dash: animated ? [] : [3, 3])
        )

        // Teeth: material tick marks crossing the rim; they visibly rotate
        // with the cog and mesh with the form's teeth.
        let toothHalf = RosetteCatalog.toothPitch * 0.25
        let teethPath = CGMutablePath()
        for i in 0..<layer.cogTeeth {
            let angle = state.cogRotation + Double(i) * 2 * .pi / Double(layer.cogTeeth)
            let ux = cos(angle)
            let uy = sin(angle)
            teethPath.move(to: CGPoint(x: state.cogCenter.x + (r - toothHalf) * ux,
                                       y: state.cogCenter.y + (r - toothHalf) * uy))
            teethPath.addLine(to: CGPoint(x: state.cogCenter.x + (r + toothHalf) * ux,
                                          y: state.cogCenter.y + (r + toothHalf) * uy))
        }
        var mutableT = t
        if let teeth = teethPath.copy(using: &mutableT) {
            ctx.stroke(Path(teeth), with: .color(color), style: StrokeStyle(lineWidth: 1))
        }

        // Pen arm from the cog center to the pen hole.
        var arm = Path()
        arm.move(to: viewCenter)
        arm.addLine(to: viewPen)
        ctx.stroke(arm, with: .color(color), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        ctx.fill(
            Path(ellipseIn: CGRect(x: viewCenter.x - 2, y: viewCenter.y - 2, width: 4, height: 4)),
            with: .color(color)
        )

        // Pen hole with the pen (layer color) in it.
        ctx.stroke(
            Path(ellipseIn: CGRect(x: viewPen.x - 5, y: viewPen.y - 5, width: 10, height: 10)),
            with: .color(color),
            style: StrokeStyle(lineWidth: 1)
        )
        ctx.fill(
            Path(ellipseIn: CGRect(x: viewPen.x - 3, y: viewPen.y - 3, width: 6, height: 6)),
            with: .color(layer.color.swiftUIColor)
        )
    }

    private func drawGhostCurve(_ ctx: inout GraphicsContext, ghost: RosetteLayer, world: CGAffineTransform, widthScale: Double) {
        var t = PatternRenderer.layerTransform(rotationDegrees: ghost.rotationDegrees, world: world)
        if let cg = PathCache.shared.path(for: ghost.curveParameters).copy(using: &t) {
            ctx.stroke(
                Path(cg),
                with: .color(ghost.color.swiftUIColor.opacity(0.35)),
                style: StrokeStyle(lineWidth: ghost.lineWidth * widthScale, lineCap: .round, lineJoin: .round)
            )
        }
    }
}
