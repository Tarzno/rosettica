import XCTest
@testable import RosetticaCore

/// Deterministic RNG (SplitMix64) so composer tests are reproducible.
private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

final class DemoComposerTests: XCTestCase {
    func testComposedLayersAreValid() {
        var composer = DemoComposer(hue: 0.25)
        var rng = SeededRNG(state: 1)

        for _ in 0..<50 {
            let layers = composer.composeLayers(using: &rng)
            XCTAssertTrue((3...6).contains(layers.count))

            let form = layers[0].form
            for layer in layers {
                XCTAssertEqual(layer.form, form, "one form per composition")
                XCTAssertTrue(CurveEngine.fits(layer.curveParameters), "cog must fit the form")
                XCTAssertTrue((0.35...1.0).contains(layer.penFraction))
                XCTAssertTrue((0.9...2.0).contains(layer.lineWidth))
                XCTAssertTrue(layer.rotationDegrees >= 0 && layer.rotationDegrees < 360)
                let formTeeth = Double(RosetteCatalog.form(layer.form).teeth(for: layer.side))
                XCTAssertTrue(layer.phaseTeeth >= 0 && layer.phaseTeeth < formTeeth)

                // Vibrant on black: high brightness and saturation.
                let maxC = max(layer.color.red, layer.color.green, layer.color.blue)
                let minC = min(layer.color.red, layer.color.green, layer.color.blue)
                XCTAssertGreaterThanOrEqual(maxC, 0.95, "brightness")
                XCTAssertGreaterThanOrEqual((maxC - minC) / maxC, 0.85 - 1e-9, "saturation")
                XCTAssertEqual(layer.color.alpha, 1)
            }
        }
    }

    func testCompositionsVary() {
        var composer = DemoComposer(hue: 0)
        var rng = SeededRNG(state: 42)
        let first = composer.composeLayers(using: &rng)
        let second = composer.composeLayers(using: &rng)
        XCTAssertNotEqual(
            first.map(\.curveParameters), second.map(\.curveParameters),
            "consecutive compositions should differ"
        )
    }

    func testDrawingDurationClampsAndScales() {
        // Ring 96 with a 48-tooth cog closes after 2 laps: 192 teeth at
        // 320 teeth/s would be 0.6 s, clamped up to the 6 s minimum.
        let short = CurveParameters(form: .ringSmall, side: .inside, cogTeeth: 48, penFraction: 0.8)
        XCTAssertEqual(DemoComposer.drawingDuration(for: short, teethPerSecond: 320, limits: 6...30), 6)

        // Ring 105 outside with a 52-tooth cog: 52 laps × 105 teeth = 5460
        // teeth → 17.0625 s, within the limits.
        let long = CurveParameters(form: .ringSmall, side: .outside, cogTeeth: 52, penFraction: 0.8)
        XCTAssertEqual(
            DemoComposer.drawingDuration(for: long, teethPerSecond: 320, limits: 6...30),
            5460.0 / 320.0,
            accuracy: 1e-12
        )
    }
}
