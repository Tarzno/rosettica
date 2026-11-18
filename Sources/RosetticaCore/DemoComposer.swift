import Foundation

extension RGBAColor {
    /// Builds an sRGB color from hue/saturation/brightness (all 0...1).
    public init(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1) {
        let h = (hue - floor(hue)) * 6
        let f = h - floor(h)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * f)
        let t = brightness * (1 - saturation * (1 - f))
        switch Int(h) % 6 {
        case 0: self.init(red: brightness, green: t, blue: p, alpha: alpha)
        case 1: self.init(red: q, green: brightness, blue: p, alpha: alpha)
        case 2: self.init(red: p, green: brightness, blue: t, alpha: alpha)
        case 3: self.init(red: p, green: q, blue: brightness, alpha: alpha)
        case 4: self.init(red: t, green: p, blue: brightness, alpha: alpha)
        default: self.init(red: brightness, green: p, blue: q, alpha: alpha)
        }
    }
}

/// Plans random Rosettica compositions — vibrant colors meant for a black
/// background. Shared by the screensaver and the app's Random Demo mode so
/// both put on exactly the same show: one form per composition, 3–6 layers
/// with random cogs, pen holes, phases, and rotations, occasionally switching
/// between inside and outside rolling, with hues spaced along the golden
/// ratio so every composition gets a balanced palette.
public struct DemoComposer {
    private var hue: Double

    public init(hue: Double = Double.random(in: 0..<1)) {
        self.hue = hue
    }

    /// Plans the next composition. All returned layers use the same form and
    /// are meant to be drawn in order on a black background.
    public mutating func composeLayers<R: RandomNumberGenerator>(using rng: inout R) -> [RosetteLayer] {
        let form = RosetteCatalog.forms.randomElement(using: &rng)!
        var side: RollSide = Double.random(in: 0..<1, using: &rng) < 0.7 ? .inside : .outside
        var layers: [RosetteLayer] = []
        for _ in 0..<Int.random(in: 3...6, using: &rng) {
            layers.append(composeLayer(form: form, side: side, using: &rng))
            // Occasionally switch sides mid-composition — an inside rosette
            // with an outside lattice woven around it is a classic look.
            if Double.random(in: 0..<1, using: &rng) < 0.25 {
                side = side == .inside ? .outside : .inside
            }
        }
        return layers
    }

    private mutating func composeLayer<R: RandomNumberGenerator>(
        form: RosetteForm, side: RollSide, using rng: inout R
    ) -> RosetteLayer {
        hue = (hue + 0.381966).truncatingRemainder(dividingBy: 1)
        return RosetteLayer(
            form: form.id,
            side: side,
            cogTeeth: form.allowedCogTeeth(for: side).randomElement(using: &rng)!,
            penFraction: Double.random(in: 0.35...1.0, using: &rng),
            phaseTeeth: Double.random(in: 0..<Double(form.teeth(for: side)), using: &rng),
            rotationDegrees: Double.random(in: 0..<1, using: &rng) < 0.5
                ? 0
                : Double.random(in: 0..<360, using: &rng),
            lineWidth: Double.random(in: 0.9...2.0, using: &rng),
            color: RGBAColor(
                hue: hue,
                saturation: Double.random(in: 0.85...1.0, using: &rng),
                brightness: Double.random(in: 0.95...1.0, using: &rng)
            )
        )
    }

    /// Seconds the cog needs to roll the complete curve at the given tooth
    /// rate, clamped so short curves stay watchable and long ones finish.
    public static func drawingDuration(
        for params: CurveParameters, teethPerSecond: Double, limits: ClosedRange<Double>
    ) -> Double {
        let formTeeth = RosetteCatalog.form(params.form).teeth(for: params.side)
        let totalTeeth = Double(formTeeth * CurveEngine.laps(for: params))
        return min(max(totalTeeth / teethPerSecond, limits.lowerBound), limits.upperBound)
    }
}
