import SwiftUI
import RosetticaCore

struct ControlsSidebar: View {
    @Binding var settings: DrawSettings
    var drawingSpeed: Binding<DrawingSpeed>
    var isAnimating: Bool
    var isDemoActive: Bool
    var pattern: RosettePattern
    var backgroundColor: Binding<Color>
    var onStamp: () -> Void
    var onToggleDemo: () -> Void
    var onSkipAnimation: () -> Void
    var onDeleteLayer: (UUID) -> Void
    var onClearAll: () -> Void

    private static let previewLayerID = UUID()

    private var lineColor: Binding<Color> {
        Binding(
            get: { settings.color.swiftUIColor },
            set: { settings.color = RGBAColor($0) }
        )
    }

    private var previewPattern: RosettePattern {
        RosettePattern(background: pattern.background, layers: [settings.makeLayer(id: Self.previewLayerID)])
    }

    var body: some View {
        Form {
            Section("Form & Cog") {
                Picker("Form", selection: $settings.form) {
                    ForEach(RosetteCatalog.forms, id: \.id) { form in
                        Text(form.name).tag(form.id)
                    }
                }
                Picker("Rolling", selection: $settings.side) {
                    Text("Inside").tag(RollSide.inside)
                    Text("Outside").tag(RollSide.outside)
                }
                .pickerStyle(.segmented)
                Picker("Cog size", selection: $settings.cogTeeth) {
                    ForEach(settings.allowedCogTeeth, id: \.self) { teeth in
                        Text("\(teeth) teeth").tag(teeth)
                    }
                }
                sliderRow(
                    "Pen hole",
                    value: $settings.penFraction,
                    range: 0.15...1.0,
                    display: String(format: "%.0f %%", settings.penFraction * 100)
                )
                sliderRow(
                    "Start position",
                    value: $settings.phaseTeeth,
                    range: 0...Double(settings.formTeeth),
                    display: String(format: "tooth %.0f", settings.phaseTeeth)
                )
                sliderRow(
                    "Form rotation",
                    value: $settings.rotationDegrees,
                    range: 0...360,
                    display: String(format: "%.0f°", settings.rotationDegrees)
                )
            }

            Section("Pen & Paper") {
                sliderRow(
                    "Line width",
                    value: $settings.lineWidth,
                    range: 0.5...8,
                    display: String(format: "%.1f pt", settings.lineWidth)
                )
                ColorPicker("Line color", selection: lineColor, supportsOpacity: true)
                ColorPicker("Background", selection: backgroundColor, supportsOpacity: false)
            }

            Section("Preview") {
                PatternCanvas(pattern: previewPattern, ghost: nil, showGuides: false, animation: nil)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                Text("\(RosetteCatalog.form(settings.form).name), \(settings.cogTeeth)-tooth cog — closes after \(settings.laps) lap\(settings.laps == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Drawing speed")
                    Picker("Drawing speed", selection: drawingSpeed) {
                        ForEach(DrawingSpeed.allCases) { speed in
                            Text(speed.label).tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if drawingSpeed.wrappedValue == .learn {
                        Text("Watch the toothed cog roll and the pen draw, tooth by tooth.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button {
                    onStamp()
                } label: {
                    Label("Draw Pattern", systemImage: "pencil.and.outline")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("d", modifiers: .command)
                .disabled(isDemoActive)
                if isAnimating && !isDemoActive {
                    Button {
                        onSkipAnimation()
                    } label: {
                        Label("Finish Drawing Now", systemImage: "forward.end")
                            .frame(maxWidth: .infinity)
                    }
                }
                Button {
                    onToggleDemo()
                } label: {
                    Label(
                        isDemoActive ? "Stop Demo" : "Random Demo",
                        systemImage: isDemoActive ? "stop.circle" : "sparkles"
                    )
                    .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                if isDemoActive {
                    Text("Endlessly drawing random patterns, like the screensaver. Your document is untouched — click again to stop.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Layers (\(pattern.layers.count))") {
                if pattern.layers.isEmpty {
                    Text("No patterns drawn yet. Adjust the controls and click Draw Pattern.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pattern.layers.reversed()) { layer in
                        layerRow(layer)
                    }
                    Button("Clear All", role: .destructive) {
                        onClearAll()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(display)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func layerRow(_ layer: RosetteLayer) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(layer.color.swiftUIColor)
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(.quaternary))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(RosetteCatalog.form(layer.form).name) · \(layer.cogTeeth) teeth")
                    .font(.callout)
                Text("\(layer.side == .inside ? "inside" : "outside") · hole \(Int(layer.penFraction * 100)) %\(layer.rotationDegrees != 0 ? " · \(Int(layer.rotationDegrees))°" : "") · \(String(format: "%.1f pt", layer.lineWidth))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                onDeleteLayer(layer.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove this layer")
        }
    }
}
