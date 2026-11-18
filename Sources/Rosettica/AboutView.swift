import SwiftUI
import RosetticaCore

struct AboutView: View {
    private static let decoration = RosettePattern(
        background: RGBAColor(red: 0.97, green: 0.96, blue: 0.93),
        layers: [
            RosetteLayer(form: .ringSmall, side: .inside, cogTeeth: 56, penFraction: 0.85,
                       lineWidth: 1.2, color: .classicBlue),
            RosetteLayer(form: .ringSmall, side: .inside, cogTeeth: 63, penFraction: 0.7,
                       lineWidth: 1.2, color: .classicRed),
            RosetteLayer(form: .ringSmall, side: .inside, cogTeeth: 45, penFraction: 0.55,
                       lineWidth: 1.2, color: .classicGreen),
        ]
    )

    var body: some View {
        VStack(spacing: 12) {
            PatternCanvas(pattern: Self.decoration, ghost: nil, showGuides: false, animation: nil)
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(radius: 4)
            Text("Rosettica")
                .font(.title.bold())
            Text("Version 1.0")
                .font(.callout)
                .foregroundStyle(.secondary)
            VStack(spacing: 2) {
                Text("Concept: Hanno Teeling")
                Text("Initial implementation: Anthropic Claude Fable 5")
                Text("Refinement: Anthropic Claude Opus 5.5")
            }
            .font(.body)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            Text("A homage to the drawing toy invented by Denys Fisher,\nfirst presented in 1965.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 36)
        .frame(width: 400)
        // Let the window adopt the content's full height (it is sized by
        // its content), so no line is ever clipped.
        .fixedSize(horizontal: false, vertical: true)
    }
}
