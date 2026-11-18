import CoreGraphics
import Foundation
#if canImport(RosetticaCore)
import RosetticaCore
#endif

/// Drives one screen's endless show: random Rosettica compositions in
/// vibrant colors on black, drawn stroke by stroke while the toothed cog
/// visibly rolls along the form, then held and faded out before the next
/// composition begins.
///
/// Each scene owns its own random generator, so every screen of a
/// multi-monitor setup shows different patterns. Time advances by a fixed
/// step per frame; finished strokes accumulate in a backing bitmap so a
/// frame only draws the new segments plus the transient guides.
final class SaverScene {
    private struct PlannedLayer {
        let params: CurveParameters
        /// Rigid rotation of the whole layer about the origin, in radians.
        let rotation: Double
        let color: CGColor
        /// Stroke width in view points.
        let lineWidth: Double
        /// Seconds the cog needs to roll the complete curve.
        let duration: Double
        let points: [CGPoint]
    }

    private struct Composition {
        let form: RosetteForm
        let layers: [PlannedLayer]
        /// Bitmap pixels per world unit, chosen so every planned layer fits.
        let pixelsPerUnit: Double
        let guides: [RollSide: (outline: CGPath, teeth: CGPath)]
    }

    private enum Phase {
        case drawing(elapsed: Double)
        case pause(remaining: Double)
        case hold(remaining: Double)
        case fade(remaining: Double)
    }

    private var rng = SystemRandomNumberGenerator()
    private var composer = DemoComposer()

    private var bitmap: CGContext?
    /// Wraps the live bitmap buffer so `draw` can blit without `makeImage()`,
    /// whose copy-on-write clones all ~50 MB whenever a stroke preceded it.
    private var bitmapProvider: CGDataProvider?
    private var pixelWidth = 0
    private var pixelHeight = 0
    private var backingScale: CGFloat = 2

    private var composition: Composition?
    private var layerIndex = 0
    private var drawnIndex = 0
    private var phase = Phase.drawing(elapsed: 0)
    /// Where the cog overlay was drawn last frame (view coordinates), so the
    /// next frame's dirty region can erase it.
    private var lastOverlayRect: CGRect?

    private let pauseDuration = 1.2
    private let holdDuration: Double
    private let fadeDuration = 2.5
    private let teethPerSecond: Double
    private let durationRange: ClosedRange<Double>

    init(isPreview: Bool) {
        holdDuration = isPreview ? 3 : 8
        teethPerSecond = isPreview ? 1000 : 320
        durationRange = isPreview ? 2...7 : 6...30
    }

    // MARK: - Time stepping

    /// Advances the show by `dt` seconds and returns the view-coordinate
    /// region that changed, or nil when the screen is static (which it is for
    /// seconds at a time during the pause and hold phases). While a layer is
    /// drawing, the region covers only the new curve segments plus the cog
    /// overlay's old and new positions, so the caller can invalidate — and
    /// `draw` can rasterize — a small fraction of the screen per frame.
    @discardableResult
    func advance(by dt: Double, size: CGSize, scale: CGFloat) -> CGRect? {
        guard size.width > 8, size.height > 8 else { return nil }
        let full = CGRect(origin: .zero, size: size)
        ensureBitmap(size: size, scale: scale)
        if composition == nil {
            lastOverlayRect = nil
            startComposition()
            return composition == nil ? nil : full
        }
        guard let comp = composition else { return nil }

        switch phase {
        case .drawing(let elapsed):
            let layer = comp.layers[layerIndex]
            let t = elapsed + dt
            let progress = min(t / layer.duration, 1)
            let target = max(1, Int(progress * Double(layer.points.count - 1)))
            var dirty = CGRect.null
            if target > drawnIndex {
                dirty = strokeRect(layer: layer, from: drawnIndex, to: target, in: comp, size: size)
                stroke(layer: layer, from: drawnIndex, to: target, in: comp)
                drawnIndex = target
            }
            if let old = lastOverlayRect {
                dirty = dirty.union(old)
            }
            let overlay = overlayRect(layer: layer, comp: comp, progress: progress, size: size)
            dirty = dirty.union(overlay)
            lastOverlayRect = overlay
            phase = progress >= 1 ? .pause(remaining: pauseDuration) : .drawing(elapsed: t)
            return dirty.insetBy(dx: -4, dy: -4).intersection(full)
        case .pause(let remaining):
            let t = remaining - dt
            if t > 0 {
                phase = .pause(remaining: t)
                return nil
            } else if layerIndex + 1 < comp.layers.count {
                layerIndex += 1
                drawnIndex = 0
                phase = .drawing(elapsed: 0)
                lastOverlayRect = nil
                return full
            } else {
                phase = .hold(remaining: holdDuration)
                lastOverlayRect = nil
                return full
            }
        case .hold(let remaining):
            let t = remaining - dt
            phase = t > 0 ? .hold(remaining: t) : .fade(remaining: fadeDuration)
            return t > 0 ? nil : full
        case .fade(let remaining):
            let t = remaining - dt
            if t > 0 {
                phase = .fade(remaining: t)
            } else {
                bitmap?.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
                composition = nil
                startComposition()
            }
            return full
        }
    }

    /// Drops the backing bitmap and the current composition. Called when the
    /// host stops the animation or the view goes invisible, so a lingering
    /// `legacyScreenSaver` process holds no megabytes on our behalf. The next
    /// `advance` rebuilds everything and begins a fresh composition.
    func releaseResources() {
        bitmap = nil
        bitmapProvider = nil
        composition = nil
        pixelWidth = 0
        pixelHeight = 0
        layerIndex = 0
        drawnIndex = 0
        phase = .drawing(elapsed: 0)
        lastOverlayRect = nil
    }

    // MARK: - Dirty regions

    /// Bounding box, in view coordinates, of the curve points about to be
    /// stroked, padded by the stroke width.
    private func strokeRect(layer: PlannedLayer, from: Int, to: Int, in comp: Composition, size: CGSize) -> CGRect {
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for i in from...to {
            let p = layer.points[i]
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return viewRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY,
                        rotation: layer.rotation, comp: comp, size: size)
            .insetBy(dx: -layer.lineWidth - 2, dy: -layer.lineWidth - 2)
    }

    /// Bounding box, in view coordinates, of the transient cog overlay (cog
    /// with teeth, pen arm, and pen) at the given progress.
    private func overlayRect(layer: PlannedLayer, comp: Composition, progress: Double, size: CGSize) -> CGRect {
        let state = CurveEngine.rollingState(for: layer.params, progress: progress)
        let reach = RosetteCatalog.cogRadius(teeth: layer.params.cogTeeth) + RosetteCatalog.toothPitch
        let minX = min(state.cogCenter.x, state.penPosition.x) - reach
        let maxX = max(state.cogCenter.x, state.penPosition.x) + reach
        let minY = min(state.cogCenter.y, state.penPosition.y) - reach
        let maxY = max(state.cogCenter.y, state.penPosition.y) + reach
        return viewRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY,
                        rotation: layer.rotation, comp: comp, size: size)
            .insetBy(dx: -8, dy: -8)
    }

    /// Maps a world-space bounding box through the layer rotation and the
    /// world-to-view transform into a conservative view-space box.
    private func viewRect(minX: Double, minY: Double, maxX: Double, maxY: Double,
                          rotation: Double, comp: Composition, size: CGSize) -> CGRect {
        let u = comp.pixelsPerUnit / Double(backingScale)
        let c = cos(rotation)
        let s = sin(rotation)
        var vMinX = Double.infinity, vMinY = Double.infinity
        var vMaxX = -Double.infinity, vMaxY = -Double.infinity
        for (x, y) in [(minX, minY), (minX, maxY), (maxX, minY), (maxX, maxY)] {
            let rx = x * c - y * s
            let ry = x * s + y * c
            vMinX = min(vMinX, rx); vMaxX = max(vMaxX, rx)
            vMinY = min(vMinY, ry); vMaxY = max(vMaxY, ry)
        }
        return CGRect(x: vMinX * u + Double(size.width) / 2,
                      y: vMinY * u + Double(size.height) / 2,
                      width: (vMaxX - vMinX) * u,
                      height: (vMaxY - vMinY) * u)
    }

    private func ensureBitmap(size: CGSize, scale: CGFloat) {
        let w = max(Int((size.width * scale).rounded()), 8)
        let h = max(Int((size.height * scale).rounded()), 8)
        if bitmap != nil, w == pixelWidth, h == pixelHeight, scale == backingScale { return }
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        bitmap = ctx
        bitmapProvider = ctx.data.flatMap {
            CGDataProvider(dataInfo: nil, data: $0, size: ctx.bytesPerRow * h) { _, _, _ in }
        }
        pixelWidth = w
        pixelHeight = h
        backingScale = scale
        composition = nil
    }

    // MARK: - Composition planning

    private func startComposition() {
        guard bitmap != nil else { return }
        let planned = composer.composeLayers(using: &rng)
        let form = RosetteCatalog.form(planned[0].form)
        let widthScale = max(Double(min(pixelWidth, pixelHeight)) / Double(backingScale) / 800, 0.6)
        let layers = planned.map { layer in
            PlannedLayer(
                params: layer.curveParameters,
                rotation: layer.rotationDegrees * .pi / 180,
                color: CGColor(
                    srgbRed: layer.color.red, green: layer.color.green,
                    blue: layer.color.blue, alpha: layer.color.alpha
                ),
                lineWidth: layer.lineWidth * widthScale,
                duration: DemoComposer.drawingDuration(
                    for: layer.curveParameters,
                    teethPerSecond: teethPerSecond,
                    limits: durationRange
                ),
                points: CurveEngine.points(for: layer.curveParameters)
            )
        }

        var worldRadius = RosetteCatalog.toothPitch
        var guides: [RollSide: (outline: CGPath, teeth: CGPath)] = [:]
        for layer in layers {
            let s = layer.params.side
            worldRadius = max(worldRadius, CurveEngine.boundingRadius(of: layer.points))
            worldRadius = max(worldRadius, CurveEngine.trackRadius(form: form.id, side: s) + RosetteCatalog.toothPitch)
            if guides[s] == nil {
                guides[s] = Self.buildGuides(form: form, side: s)
            }
        }

        composition = Composition(
            form: form,
            layers: layers,
            pixelsPerUnit: Double(min(pixelWidth, pixelHeight)) * 0.47 / worldRadius,
            guides: guides
        )
        layerIndex = 0
        drawnIndex = 0
        phase = .drawing(elapsed: 0)
    }

    private static func buildGuides(form: RosetteForm, side: RollSide) -> (outline: CGPath, teeth: CGPath) {
        let track = form.track(for: side)
        let outline = CGMutablePath()
        let steps = 720
        for i in 0...steps {
            let p = track.sample(at: track.totalLength * Double(i) / Double(steps)).position
            if i == 0 { outline.move(to: p) } else { outline.addLine(to: p) }
        }

        let teeth = CGMutablePath()
        let toward: Double = side == .inside ? 1 : -1
        for i in 0..<form.teeth(for: side) {
            let sample = track.sample(at: Double(i) * RosetteCatalog.toothPitch)
            teeth.move(to: sample.position)
            teeth.addLine(to: CGPoint(
                x: sample.position.x + toward * sample.leftNormal.dx * RosetteCatalog.toothPitch * 0.5,
                y: sample.position.y + toward * sample.leftNormal.dy * RosetteCatalog.toothPitch * 0.5
            ))
        }
        return (outline, teeth)
    }

    // MARK: - Rendering

    /// Appends the newly rolled curve segments to the backing bitmap.
    private func stroke(layer: PlannedLayer, from: Int, to: Int, in comp: Composition) {
        guard let bmp = bitmap, from < to else { return }
        bmp.saveGState()
        bmp.translateBy(x: CGFloat(pixelWidth) / 2, y: CGFloat(pixelHeight) / 2)
        bmp.scaleBy(x: comp.pixelsPerUnit, y: comp.pixelsPerUnit)
        bmp.rotate(by: layer.rotation)
        bmp.setLineCap(.round)
        bmp.setLineJoin(.round)
        bmp.setStrokeColor(layer.color)
        bmp.setLineWidth(layer.lineWidth * Double(backingScale) / comp.pixelsPerUnit)
        bmp.beginPath()
        bmp.move(to: layer.points[from])
        for i in (from + 1)...to {
            bmp.addLine(to: layer.points[i])
        }
        bmp.strokePath()
        bmp.restoreGState()
    }

    /// Renders the current state into `rect` (typically the region
    /// invalidated by `advance`); rasterization is clipped to it, so small
    /// dirty regions cost only a small fraction of a full-screen redraw.
    func draw(in ctx: CGContext, rect: CGRect, size: CGSize) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.clip(to: rect)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(rect)
        guard let comp = composition, let bmp = bitmap else { return }

        // Blit only the pixels under `rect`: crop the (zero-copy) image so
        // Core Graphics never touches — or color-matches — the rest.
        let s = Double(backingScale)
        let pixelRect = CGRect(
            x: (rect.minX * s).rounded(.down),
            y: (Double(pixelHeight) - rect.maxY * s).rounded(.down),
            width: (rect.width * s).rounded(.up) + 1,
            height: (rect.height * s).rounded(.up) + 1
        ).intersection(CGRect(x: 0, y: 0, width: Double(pixelWidth), height: Double(pixelHeight)))
        if !pixelRect.isEmpty, let image = liveImage(of: bmp)?.cropping(to: pixelRect) {
            ctx.saveGState()
            ctx.setAlpha(fadeAlpha)
            let target = CGRect(
                x: pixelRect.minX / s,
                y: (Double(pixelHeight) - pixelRect.maxY) / s,
                width: pixelRect.width / s,
                height: pixelRect.height / s
            )
            ctx.draw(image, in: target)
            ctx.restoreGState()
        }

        if let progress = overlayProgress {
            drawOverlay(ctx, layer: comp.layers[layerIndex], comp: comp, progress: progress, size: size)
        }
    }

    /// A CGImage sharing the bitmap's buffer (created per draw, so CG never
    /// caches stale pixels); falls back to a `makeImage()` copy if the
    /// zero-copy provider is unavailable.
    private func liveImage(of bmp: CGContext) -> CGImage? {
        guard let provider = bitmapProvider else { return bmp.makeImage() }
        return CGImage(
            width: pixelWidth, height: pixelHeight,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bmp.bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        ) ?? bmp.makeImage()
    }

    private var fadeAlpha: CGFloat {
        if case let .fade(remaining) = phase {
            return CGFloat(max(remaining / fadeDuration, 0))
        }
        return 1
    }

    private var overlayProgress: Double? {
        switch phase {
        case .drawing(let elapsed):
            guard let comp = composition else { return nil }
            return min(elapsed / comp.layers[layerIndex].duration, 1)
        case .pause:
            return 1
        case .hold, .fade:
            return nil
        }
    }

    /// Draws the transient guides in view coordinates: the toothed form
    /// outline plus the rolling cog with its teeth, pen arm, and pen.
    private func drawOverlay(_ ctx: CGContext, layer: PlannedLayer, comp: Composition, progress: Double, size: CGSize) {
        let unitsToPoints = comp.pixelsPerUnit / Double(backingScale)
        let pt = 1.0 / unitsToPoints
        let guideColor = CGColor(gray: 1, alpha: 0.3)
        let cogColor = CGColor(gray: 1, alpha: 0.55)

        ctx.saveGState()
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        ctx.scaleBy(x: unitsToPoints, y: unitsToPoints)
        ctx.rotate(by: layer.rotation)

        if let paths = comp.guides[layer.params.side] {
            ctx.setStrokeColor(guideColor)
            ctx.setLineWidth(pt)
            ctx.addPath(paths.outline)
            ctx.strokePath()
            ctx.addPath(paths.teeth)
            ctx.strokePath()
        }

        let state = CurveEngine.rollingState(for: layer.params, progress: progress)
        let r = RosetteCatalog.cogRadius(teeth: layer.params.cogTeeth)

        ctx.setStrokeColor(cogColor)
        ctx.setLineWidth(1.4 * pt)
        ctx.strokeEllipse(in: rect(around: state.cogCenter, radius: r))

        ctx.setLineWidth(pt)
        let toothHalf = RosetteCatalog.toothPitch * 0.25
        ctx.beginPath()
        for i in 0..<layer.params.cogTeeth {
            let angle = state.cogRotation + Double(i) * 2 * .pi / Double(layer.params.cogTeeth)
            let ux = cos(angle)
            let uy = sin(angle)
            ctx.move(to: CGPoint(x: state.cogCenter.x + (r - toothHalf) * ux,
                                 y: state.cogCenter.y + (r - toothHalf) * uy))
            ctx.addLine(to: CGPoint(x: state.cogCenter.x + (r + toothHalf) * ux,
                                    y: state.cogCenter.y + (r + toothHalf) * uy))
        }
        ctx.strokePath()

        ctx.setLineDash(phase: 0, lengths: [2 * pt, 2 * pt])
        ctx.beginPath()
        ctx.move(to: state.cogCenter)
        ctx.addLine(to: state.penPosition)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])

        ctx.setFillColor(cogColor)
        ctx.fillEllipse(in: rect(around: state.cogCenter, radius: 2 * pt))
        ctx.strokeEllipse(in: rect(around: state.penPosition, radius: 5 * pt))
        ctx.setFillColor(layer.color)
        ctx.fillEllipse(in: rect(around: state.penPosition, radius: 3 * pt))

        ctx.restoreGState()
    }

    private func rect(around center: CGPoint, radius: Double) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
    }
}
