import AppKit
import SwiftUI
import UniformTypeIdentifiers
import RosetticaCore

enum WindowID {
    static let about = "about"
    static let help = "help"
    static let license = "license"
}

final class RosetticaAppDelegate: NSObject, NSApplicationDelegate {
    // Launch tidying. At launch, SwiftUI's DocumentGroup always creates a
    // blank "Untitled" document — even when the app was launched to open a
    // file, and even when macOS restores the previous session's windows
    // (with "Close windows when quitting an application" turned off), which
    // themselves include blank untitled windows. Left alone, blank windows
    // pile up from launch to launch. Native apps (TextEdit) instead drop the
    // blank launch document once a real one is open.
    //
    // So until the user's first click or keypress in the app, every pass of
    // the event loop tidies up: blank untitled documents are closed when a
    // real document is open, and only one survives when there are only
    // blank ones. User input ends this phase before a menu or ⌘N can
    // create a document, so documents the user makes are never touched.
    //
    // Not an option: a custom NSDocumentController subclass (SwiftUI
    // installs its own and crashes if another exists first), and marking
    // blank windows non-restorable at quit (macOS has already recorded them).
    private var launchObservers: [NSObjectProtocol] = []
    private var launchEventMonitor: Any?

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        writeDebugSnapshot(suffix: "")
        launchObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didUpdateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tidyLaunchDocuments() }
        })
        launchEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            self?.endLaunchPhase()
            return event
        }
        // On recent macOS versions, SwiftUI's DocumentGroup can present the
        // Open panel at launch instead of creating an untitled document.
        // If that happened, dismiss the panel and create one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.ensureUntitledDocument()
            self?.writeDebugSnapshot(suffix: ".after")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.writeDebugSnapshot(suffix: ".settled")
        }
    }

    private func endLaunchPhase() {
        launchObservers.forEach(NotificationCenter.default.removeObserver)
        launchObservers.removeAll()
        if let monitor = launchEventMonitor {
            NSEvent.removeMonitor(monitor)
            launchEventMonitor = nil
        }
    }

    @MainActor
    private func tidyLaunchDocuments() {
        let documents = NSDocumentController.shared.documents
        // A restored document exists a moment before its window does;
        // closing it then would orphan the window that follows. Only blank
        // documents already on screen are candidates (later passes catch up).
        let blank = documents.filter { document in
            Self.isBlankUntitled(document)
                && document.windowControllers.contains { $0.window?.isVisible == true }
        }
        let pending = documents.contains { document in
            Self.isBlankUntitled(document) && !blank.contains { $0 === document }
        }
        let survivor: NSDocument?
        if pending {
            return
        } else if blank.count < documents.count {
            survivor = nil // a real document is open
        } else if blank.count > 1 {
            // Keep the plainest title ("Untitled" rather than "Untitled 4").
            survivor = blank.min { a, b in
                let (x, y) = (a.displayName ?? "", b.displayName ?? "")
                return (x.count, x) < (y.count, y)
            }
        } else {
            return
        }
        for document in blank where document !== survivor {
            document.close()
        }
    }

    /// Never saved and never edited — closing it loses nothing.
    private static func isBlankUntitled(_ document: NSDocument) -> Bool {
        document.fileURL == nil && !document.isDocumentEdited && !document.hasUnautosavedChanges
            && document.autosavedContentsFileURL == nil
    }

    private func ensureUntitledDocument() {
        guard let panel = NSApp.windows.first(where: { $0 is NSOpenPanel && $0.isVisible }) as? NSOpenPanel,
              NSDocumentController.shared.documents.isEmpty
        else { return }
        panel.cancel(nil)
        NSDocumentController.shared.newDocument(nil)
    }

    private func writeDebugSnapshot(suffix: String) {
        guard let debugPath = ProcessInfo.processInfo.environment["ROSETTICA_DEBUG_PATH"] else { return }
        let controller = NSDocumentController.shared
        let type = UTType("io.github.tarzno.rosettica.document")
        let lines = [
            "defaultType: \(controller.defaultType ?? "nil")",
            "documents: \(controller.documents.count)",
            "documentClassNames: \(controller.documentClassNames)",
            "utype: \(type?.identifier ?? "nil") ext: \(type?.preferredFilenameExtension ?? "nil") declared: \(type?.isDeclared ?? false)",
            "windows: \(NSApp.windows.map { "\(Swift.type(of: $0)) visible=\($0.isVisible)" })",
            "windowMenu: \(NSApp.windowsMenu?.items.map(\.title) ?? [])",
            "appMenu: \(NSApp.mainMenu?.items.first?.submenu?.items.map(\.title) ?? [])",
            "helpMenu: \(NSApp.helpMenu?.items.map(\.title) ?? [])",
        ]
        try? lines.joined(separator: "\n").write(toFile: debugPath + suffix, atomically: true, encoding: .utf8)
    }
}

@main
struct RosetticaApp: App {
    @NSApplicationDelegateAdaptor(RosetticaAppDelegate.self) private var appDelegate

    init() {
        // `Rosettica --license` prints the compiled-in license and exits;
        // Scripts/build-app.sh compares it with the LICENSE file.
        if CommandLine.arguments.contains("--license") {
            print(License.text)
            exit(0)
        }
    }

    var body: some Scene {
        DocumentGroup(newDocument: RosetteDocument()) { configuration in
            ContentView(document: configuration.$document)
        }
        .commands {
            RosetticaCommands()
        }

        Window("About Rosettica", id: WindowID.about) {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        // Opened from the app menu; keep SwiftUI from also listing it
        // permanently in the Window menu.
        .commandsRemoved()

        Window("Rosettica License", id: WindowID.license) {
            LicenseView()
        }
        .defaultSize(width: 560, height: 470)
        .defaultPosition(.center)
        // Opened from the app menu; no permanent Window-menu entry.
        .commandsRemoved()

        Window("Rosettica Help", id: WindowID.help) {
            HelpView()
        }
        .defaultPosition(.center)
        // Opened from the Help menu; no permanent Window-menu entry.
        .commandsRemoved()
    }
}

struct RosetticaCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.activePattern) private var activePattern

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Rosettica") {
                openWindow(id: WindowID.about)
            }
            Button("License") {
                openWindow(id: WindowID.license)
            }
        }

        CommandGroup(replacing: .help) {
            Button("Rosettica Help") {
                openWindow(id: WindowID.help)
            }
            .keyboardShortcut("?", modifiers: .command)
        }

        CommandGroup(replacing: .printItem) {
            Button("Print…") {
                if let activePattern {
                    PatternPrinter.printPattern(activePattern)
                }
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(activePattern == nil)
        }

        CommandGroup(after: .saveItem) {
            Divider()
            Menu("Export") {
                Button("PNG…") {
                    if let activePattern { PatternPrinter.exportPNG(activePattern) }
                }
                .keyboardShortcut("e", modifiers: .command)
                Button("SVG…") {
                    if let activePattern { PatternPrinter.exportSVG(activePattern) }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("PDF…") {
                    if let activePattern { PatternPrinter.exportPDF(activePattern) }
                }
                .keyboardShortcut("e", modifiers: [.command, .option])
            }
            .disabled(activePattern == nil)
        }
    }
}
