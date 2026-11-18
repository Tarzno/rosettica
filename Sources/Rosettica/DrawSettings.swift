import Foundation
import RosetticaCore

/// How fast a stamped pattern is drawn. Rates are in teeth rolled per second,
/// so the cog moves at constant rolling speed, like the real toy.
/// "Learn" is slow enough for children to follow the cog and pen.
enum DrawingSpeed: String, CaseIterable, Identifiable {
    case instant
    case fast
    case slow
    case learn

    var id: String { rawValue }

    var label: String {
        switch self {
        case .instant: return "Instant"
        case .fast: return "Fast"
        case .slow: return "Slow"
        case .learn: return "Learn"
        }
    }

    var teethPerSecond: Double? {
        switch self {
        case .instant: return nil
        case .fast: return 1500
        case .slow: return 300
        case .learn: return 60
        }
    }
}

/// The controls' current state: what the next stamped layer will look like.
struct DrawSettings: Equatable {
    var form: FormID = .ringSmall
    var side: RollSide = .inside
    var cogTeeth: Int = 52
    var penFraction: Double = 0.7
    var phaseTeeth: Double = 0
    var rotationDegrees: Double = 0
    var lineWidth: Double = 1.6
    var color: RGBAColor = .classicBlue

    var curveParameters: CurveParameters {
        CurveParameters(form: form, side: side, cogTeeth: cogTeeth, penFraction: penFraction, phaseTeeth: phaseTeeth)
    }

    var allowedCogTeeth: [Int] {
        RosetteCatalog.form(form).allowedCogTeeth(for: side)
    }

    var formTeeth: Int {
        RosetteCatalog.form(form).teeth(for: side)
    }

    var laps: Int {
        CurveEngine.laps(for: curveParameters)
    }

    func makeLayer(id: UUID = UUID()) -> RosetteLayer {
        RosetteLayer(
            id: id,
            form: form,
            side: side,
            cogTeeth: cogTeeth,
            penFraction: penFraction,
            phaseTeeth: phaseTeeth,
            rotationDegrees: rotationDegrees,
            lineWidth: lineWidth,
            color: color
        )
    }

    /// Keeps the cog and phase valid after a form or side change.
    mutating func clampToForm() {
        let allowed = allowedCogTeeth
        if !allowed.contains(cogTeeth) {
            cogTeeth = allowed.last ?? RosetteCatalog.cogTeethOptions.first!
        }
        phaseTeeth = min(phaseTeeth, Double(formTeeth))
    }
}
