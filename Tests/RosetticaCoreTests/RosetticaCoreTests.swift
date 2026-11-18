import XCTest
@testable import RosetticaCore

final class TrackTests: XCTestCase {
    func testCircleTrackGeometry() {
        let form = RosetteCatalog.form(.ringSmall)
        let track = form.track(for: .inside)
        XCTAssertEqual(track.totalLength, 96 * RosetteCatalog.toothPitch, accuracy: 1e-9)
        XCTAssertEqual(track.totalTurning, 2 * .pi, accuracy: 1e-12)
        XCTAssertEqual(track.maxInsideRollingRadius, 96, accuracy: 1e-9)

        // Radius must be 96 scene units everywhere.
        for i in 0..<50 {
            let s = track.totalLength * Double(i) / 50
            let p = track.sample(at: s).position
            XCTAssertEqual(hypot(p.x, p.y), 96, accuracy: 1e-9)
        }
    }

    func testPolygonTrackContinuityAndClosure() {
        for id in FormID.allCases {
            let form = RosetteCatalog.form(id)
            for side in RollSide.allCases {
                let track = form.track(for: side)
                let teeth = form.teeth(for: side)
                XCTAssertEqual(track.totalLength, Double(teeth) * RosetteCatalog.toothPitch, accuracy: 1e-9,
                               "length mismatch for \(id) \(side)")
                XCTAssertEqual(track.totalTurning, 2 * .pi, accuracy: 1e-9,
                               "turning mismatch for \(id) \(side)")

                // No jumps: consecutive samples stay within twice the step.
                let steps = 2000
                let ds = track.totalLength / Double(steps)
                var previous = track.sample(at: 0).position
                for i in 1...steps {
                    let p = track.sample(at: Double(i) * ds).position
                    XCTAssertLessThan(previous.distance(to: p), 2 * ds,
                                      "discontinuity in \(id) \(side) at step \(i)")
                    previous = p
                }

                // Track is centered on the origin.
                var cx = 0.0, cy = 0.0
                for i in 0..<steps {
                    let p = track.sample(at: Double(i) * ds).position
                    cx += p.x
                    cy += p.y
                }
                XCTAssertEqual(cx / Double(steps), 0, accuracy: 1e-6)
                XCTAssertEqual(cy / Double(steps), 0, accuracy: 1e-6)
            }
        }
    }
}

final class CurveEngineTests: XCTestCase {
    func testHypotrochoidMatchesClosedForm() {
        let params = CurveParameters(form: .ringSmall, side: .inside, cogTeeth: 36, penFraction: 0.7)
        let R = 96.0
        let r = RosetteCatalog.cogRadius(teeth: 36)
        let d = params.penFraction * r

        let track = RosetteCatalog.form(.ringSmall).track(for: .inside)
        let start = track.sample(at: 0).position
        let theta0 = atan2(start.y, start.x)

        let lapCount = CurveEngine.laps(for: params)
        let sTotal = Double(96 * lapCount) * RosetteCatalog.toothPitch
        let points = CurveEngine.points(for: params, samplesPerTooth: 4)
        let n = points.count - 1

        for i in 0...n {
            let s = sTotal * Double(i) / Double(n)
            let theta: Double = theta0 + s / R
            let psi: Double = theta - s / r
            let ex: Double = (R - r) * cos(theta) + d * cos(psi)
            let ey: Double = (R - r) * sin(theta) + d * sin(psi)
            XCTAssertEqual(points[i].x, ex, accuracy: 1e-6)
            XCTAssertEqual(points[i].y, ey, accuracy: 1e-6)
        }
    }

    func testEpitrochoidMatchesClosedForm() {
        let params = CurveParameters(form: .ringSmall, side: .outside, cogTeeth: 40, penFraction: 0.8)
        let R = 105.0
        let r = RosetteCatalog.cogRadius(teeth: 40)
        let d = params.penFraction * r

        let track = RosetteCatalog.form(.ringSmall).track(for: .outside)
        let start = track.sample(at: 0).position
        let theta0 = atan2(start.y, start.x)

        let lapCount = CurveEngine.laps(for: params)
        let sTotal = Double(105 * lapCount) * RosetteCatalog.toothPitch
        let points = CurveEngine.points(for: params, samplesPerTooth: 4)
        let n = points.count - 1

        for i in 0...n {
            let s = sTotal * Double(i) / Double(n)
            let theta: Double = theta0 + s / R
            let psi: Double = theta + .pi + s / r
            let ex: Double = (R + r) * cos(theta) + d * cos(psi)
            let ey: Double = (R + r) * sin(theta) + d * sin(psi)
            XCTAssertEqual(points[i].x, ex, accuracy: 1e-6)
            XCTAssertEqual(points[i].y, ey, accuracy: 1e-6)
        }
    }

    /// Cardan circles: a pen on the rim of a cog of half the ring's diameter
    /// traces a straight diameter line.
    func testCardanCirclesTraceStraightLine() {
        let params = CurveParameters(form: .ringSmall, side: .inside, cogTeeth: 48, penFraction: 1.0)
        let points = CurveEngine.points(for: params, samplesPerTooth: 4)

        let far = points.max { hypot($0.x, $0.y) < hypot($1.x, $1.y) }!
        let norm = hypot(far.x, far.y)
        XCTAssertEqual(norm, 96, accuracy: 1e-6)
        let ux = far.x / norm
        let uy = far.y / norm
        for p in points {
            XCTAssertEqual(p.x * uy - p.y * ux, 0, accuracy: 1e-4)
        }
    }

    func testClosureAndLapCountAcrossForms() {
        let combos: [(FormID, RollSide, Int)] = [
            (.ringSmall, .inside, 52),
            (.ringSmall, .outside, 63),
            (.ringLarge, .inside, 84),
            (.triangle, .inside, 45),
            (.triangle, .outside, 84),
            (.square, .inside, 40),
            (.pentagon, .outside, 52),
            (.hexagon, .inside, 32),
            (.stadium, .inside, 80),
            (.stadium, .outside, 63),
        ]
        for (form, side, cog) in combos {
            let params = CurveParameters(form: form, side: side, cogTeeth: cog, penFraction: 0.75, phaseTeeth: 3)
            XCTAssertTrue(CurveEngine.fits(params), "\(form) \(side) cog \(cog) should fit")

            let formTeeth = RosetteCatalog.form(form).teeth(for: side)
            let expectedLaps = cog / CurveEngine.gcd(formTeeth, cog)
            XCTAssertEqual(CurveEngine.laps(for: params), expectedLaps)

            let points = CurveEngine.points(for: params, samplesPerTooth: 4)
            let first = points.first!
            let last = points.last!
            XCTAssertEqual(first.x, last.x, accuracy: 1e-6, "\(form) \(side) cog \(cog) does not close")
            XCTAssertEqual(first.y, last.y, accuracy: 1e-6, "\(form) \(side) cog \(cog) does not close")

            // Everything stays inside the guaranteed world bound.
            XCTAssertLessThan(CurveEngine.boundingRadius(of: points), RosettePattern.maxWorldRadius,
                              "\(form) \(side) leaves the world bound")
        }
    }

    /// The rolling-state API (used to animate the cog) must agree with the
    /// sampled curve: the pen position at progress k/n is the k-th point.
    func testRollingStateMatchesSampledPoints() {
        let combos: [(FormID, RollSide, Int)] = [
            (.ringSmall, .inside, 52),
            (.triangle, .outside, 63),
            (.stadium, .inside, 45),
        ]
        for (form, side, cog) in combos {
            let params = CurveParameters(form: form, side: side, cogTeeth: cog, penFraction: 0.8, phaseTeeth: 5)
            let points = CurveEngine.points(for: params, samplesPerTooth: 4)
            let n = points.count - 1
            for k in [0, 1, n / 3, n / 2, n - 1, n] {
                let state = CurveEngine.rollingState(for: params, progress: Double(k) / Double(n))
                XCTAssertEqual(state.penPosition.x, points[k].x, accuracy: 1e-9,
                               "\(form) \(side) cog \(cog) at k=\(k)")
                XCTAssertEqual(state.penPosition.y, points[k].y, accuracy: 1e-9,
                               "\(form) \(side) cog \(cog) at k=\(k)")
                // The pen sits within the cog and the cog touches the track.
                let r = RosetteCatalog.cogRadius(teeth: cog)
                let contactDistance = state.cogCenter.distance(to: state.contactPoint)
                XCTAssertEqual(contactDistance, r, accuracy: 1e-9)
            }
        }
    }

    /// The most far-reaching catalog combination must stay inside the world bound.
    func testWorstCaseStaysInsideWorldBound() {
        let params = CurveParameters(form: .stadium, side: .outside, cogTeeth: 84, penFraction: 1.0)
        let radius = CurveEngine.boundingRadius(of: CurveEngine.points(for: params, samplesPerTooth: 4))
        XCTAssertLessThan(radius, RosettePattern.maxWorldRadius)
    }

    func testInsideFitLimits() {
        XCTAssertTrue(CurveEngine.fits(CurveParameters(form: .triangle, side: .inside, cogTeeth: 45, penFraction: 0.5)))
        XCTAssertFalse(CurveEngine.fits(CurveParameters(form: .triangle, side: .inside, cogTeeth: 48, penFraction: 0.5)))
        XCTAssertFalse(CurveEngine.fits(CurveParameters(form: .pentagon, side: .inside, cogTeeth: 45, penFraction: 0.5)))
        XCTAssertTrue(CurveEngine.fits(CurveParameters(form: .ringSmall, side: .inside, cogTeeth: 84, penFraction: 0.5)))
        XCTAssertTrue(CurveEngine.fits(CurveParameters(form: .triangle, side: .outside, cogTeeth: 84, penFraction: 0.5)))
        // Every form offers at least a few inside cogs.
        for form in RosetteCatalog.forms {
            XCTAssertGreaterThanOrEqual(form.allowedCogTeeth(for: .inside).count, 4, "\(form.id) has too few inside cogs")
        }
    }
}

final class PatternModelTests: XCTestCase {
    func testJSONRoundTrip() throws {
        let pattern = RosettePattern(
            background: RGBAColor(red: 0.98, green: 0.97, blue: 0.9),
            layers: [
                RosetteLayer(form: .ringSmall, side: .inside, cogTeeth: 52, penFraction: 0.7,
                           phaseTeeth: 2.5, lineWidth: 2.0, color: .classicBlue),
                RosetteLayer(form: .triangle, side: .outside, cogTeeth: 63, penFraction: 0.85,
                           phaseTeeth: 0, rotationDegrees: 180, lineWidth: 1.2, color: .classicRed),
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(pattern)
        let decoded = try JSONDecoder().decode(RosettePattern.self, from: data)
        XCTAssertEqual(pattern, decoded)
        XCTAssertEqual(decoded.layers[1].rotationDegrees, 180)
    }

    /// Documents saved before the form-rotation feature lack the key and must
    /// still load, defaulting the rotation to zero.
    func testLegacyLayerWithoutRotationDecodes() throws {
        let legacy = """
        {"id": "8E2B4B49-2C6F-4E6E-9A5B-000000000001", "form": "triangle", "side": "inside",
         "cogTeeth": 40, "penFraction": 0.85, "phaseTeeth": 0, "lineWidth": 1.4,
         "color": {"red": 0.82, "green": 0.12, "blue": 0.16, "alpha": 1}}
        """.data(using: .utf8)!
        let layer = try JSONDecoder().decode(RosetteLayer.self, from: legacy)
        XCTAssertEqual(layer.rotationDegrees, 0)
        XCTAssertEqual(layer.cogTeeth, 40)
    }
}
