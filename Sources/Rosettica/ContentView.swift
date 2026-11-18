import SwiftUI
import RosetticaCore

/// Retained target object for block-based undo registration
/// (NSUndoManager does not retain block targets).
final class UndoTarget {
    static let shared = UndoTarget()
}

struct ContentView: View {
    @Binding var document: RosetteDocument
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @State private var settings = DrawSettings()
    @AppStorage("drawingSpeed") private var drawingSpeedRaw = DrawingSpeed.fast.rawValue
    @State private var animation: CanvasAnimation?

    // Random Demo mode: the same endless show as the screensaver, drawn on a
    // transient pattern so the document (and its undo history) is untouched.
    @State private var demoPattern: RosettePattern?
    @State private var demoWorldRadius: Double?
    @State private var demoOpacity = 1.0
    @State private var demoComposer = DemoComposer()
    @State private var demoRNG = SystemRandomNumberGenerator()
    @State private var demoPlanned: [RosetteLayer] = []
    @State private var demoNextIndex = 0
    /// Bumped on every start/stop; scheduled demo steps from an older
    /// generation see the mismatch and do nothing.
    @State private var demoGeneration = 0

    private static let demoTeethPerSecond = 320.0
    private static let demoDurationLimits = 6.0...30.0
    private static let demoLayerPause = 1.2
    private static let demoHold = 8.0
    private static let demoFade = 2.5

    private var drawingSpeed: Binding<DrawingSpeed> {
        Binding(
            get: { DrawingSpeed(rawValue: drawingSpeedRaw) ?? .fast },
            set: { drawingSpeedRaw = $0.rawValue }
        )
    }

    private static let ghostLayerID = UUID()

    private var isDemoActive: Bool { demoPattern != nil }

    var body: some View {
        HSplitView {
            ZStack {
                Color.black
                PatternCanvas(
                    pattern: demoPattern ?? document.pattern,
                    ghost: isDemoActive ? nil : settings.makeLayer(id: Self.ghostLayerID),
                    showGuides: !isDemoActive,
                    animation: animation,
                    fixedWorldRadius: demoWorldRadius
                )
                .opacity(demoOpacity)
            }
            .frame(minWidth: 420, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)

            ControlsSidebar(
                settings: $settings,
                drawingSpeed: drawingSpeed,
                isAnimating: animation != nil,
                isDemoActive: isDemoActive,
                pattern: document.pattern,
                backgroundColor: backgroundBinding,
                onStamp: stamp,
                onToggleDemo: toggleDemo,
                onSkipAnimation: { animation = nil },
                onDeleteLayer: deleteLayer,
                onClearAll: clearAll
            )
            .frame(minWidth: 300, maxWidth: 340)
        }
        .frame(minWidth: 780, minHeight: 540)
        .focusedSceneValue(\.activePattern, document.pattern)
        .onChange(of: settings.form) { _ in settings.clampToForm() }
        .onChange(of: settings.side) { _ in settings.clampToForm() }
        .onAppear {
            if DebugHooks.demoRequested, document.pattern.layers.isEmpty {
                document.pattern = DebugHooks.demoPattern
            }
            if DebugHooks.animateDemoRequested {
                drawingSpeedRaw = DrawingSpeed.learn.rawValue
                stamp()
            }
            if DebugHooks.randomDemoRequested {
                toggleDemo()
            }
            if let ids = ProcessInfo.processInfo.environment["ROSETTICA_OPEN_WINDOWS"] {
                for id in ids.split(separator: ",") {
                    openWindow(id: String(id))
                }
            }
            DebugHooks.run(with: document.pattern)
        }
    }

    private var backgroundBinding: Binding<Color> {
        Binding(
            get: { document.pattern.background.swiftUIColor },
            set: { newColor in
                var pattern = document.pattern
                pattern.background = RGBAColor(newColor)
                apply(pattern, actionName: "Change Background")
            }
        )
    }

    private func stamp() {
        let layer = settings.makeLayer()
        var pattern = document.pattern
        pattern.layers.append(layer)
        apply(pattern, actionName: "Draw Pattern")

        if let rate = drawingSpeed.wrappedValue.teethPerSecond {
            let totalTeeth = Double(settings.formTeeth * settings.laps)
            let duration = max(totalTeeth / rate, 0.8)
            let anim = CanvasAnimation(layerID: layer.id, start: Date(), duration: duration)
            animation = anim
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.2) {
                if animation?.layerID == layer.id {
                    animation = nil
                }
            }
        }
    }

    // MARK: - Random Demo

    private func toggleDemo() {
        if isDemoActive {
            demoGeneration += 1
            demoPattern = nil
            demoWorldRadius = nil
            demoOpacity = 1
            animation = nil
        } else {
            demoGeneration += 1
            animation = nil
            startDemoComposition(generation: demoGeneration)
        }
    }

    private func startDemoComposition(generation: Int) {
        guard generation == demoGeneration else { return }
        demoPlanned = demoComposer.composeLayers(using: &demoRNG)
        demoNextIndex = 0

        // Pin the viewport to the whole planned composition up front.
        var radius = 120.0
        for layer in demoPlanned {
            radius = max(radius, PathCache.shared.boundingRadius(for: layer.curveParameters))
            radius = max(radius, PathCache.shared.trackRadius(form: layer.form, side: layer.side) + RosetteCatalog.toothPitch)
        }
        demoWorldRadius = radius * 1.06
        demoPattern = RosettePattern(background: .black, layers: [])
        demoOpacity = 1

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            stampNextDemoLayer(generation: generation)
        }
    }

    private func stampNextDemoLayer(generation: Int) {
        guard generation == demoGeneration, demoNextIndex < demoPlanned.count else { return }
        let layer = demoPlanned[demoNextIndex]
        demoNextIndex += 1
        demoPattern?.layers.append(layer)

        let duration = DemoComposer.drawingDuration(
            for: layer.curveParameters,
            teethPerSecond: Self.demoTeethPerSecond,
            limits: Self.demoDurationLimits
        )
        animation = CanvasAnimation(layerID: layer.id, start: Date(), duration: duration)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.2) {
            if generation == demoGeneration, animation?.layerID == layer.id {
                animation = nil
            }
        }

        let isLastLayer = demoNextIndex == demoPlanned.count
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + Self.demoLayerPause) {
            guard generation == demoGeneration else { return }
            if isLastLayer {
                holdThenFadeDemo(generation: generation)
            } else {
                stampNextDemoLayer(generation: generation)
            }
        }
    }

    private func holdThenFadeDemo(generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.demoHold - Self.demoLayerPause) {
            guard generation == demoGeneration else { return }
            withAnimation(.easeInOut(duration: Self.demoFade)) {
                demoOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.demoFade + 0.1) {
                startDemoComposition(generation: generation)
            }
        }
    }

    private func deleteLayer(_ id: UUID) {
        var pattern = document.pattern
        pattern.layers.removeAll { $0.id == id }
        apply(pattern, actionName: "Remove Layer")
    }

    private func clearAll() {
        var pattern = document.pattern
        pattern.layers.removeAll()
        apply(pattern, actionName: "Clear All Layers")
    }

    /// Replaces the document's pattern, registering the inverse for undo.
    /// Re-registration inside an undo automatically provides redo.
    private func apply(_ new: RosettePattern, actionName: String) {
        let old = document.pattern
        guard old != new else { return }
        document.pattern = new
        if let undoManager {
            undoManager.registerUndo(withTarget: UndoTarget.shared) { _ in
                apply(old, actionName: actionName)
            }
            undoManager.setActionName(actionName)
        }
    }
}

struct ActivePatternKey: FocusedValueKey {
    typealias Value = RosettePattern
}

extension FocusedValues {
    var activePattern: RosettePattern? {
        get { self[ActivePatternKey.self] }
        set { self[ActivePatternKey.self] = newValue }
    }
}
