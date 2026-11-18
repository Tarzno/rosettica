import ScreenSaver
import os.log

/// The screensaver's principal class. macOS creates one instance per screen,
/// and each instance owns an independently seeded `SaverScene`, so every
/// monitor of a multi-monitor setup draws different patterns.
///
/// Defensive behavior for the lingering-host problem: macOS 14/15 sometimes
/// keep `legacyScreenSaver` alive — and animating — after the screensaver is
/// dismissed. Window-based visibility (occlusion, hidden) is *unreliable*
/// inside the extension host — the window is an out-of-process proxy that
/// reports "not visible" while the saver is actually on screen — so the only
/// trustworthy signal is the distributed `com.apple.screensaver.*`
/// notifications: this view pauses all work after `willstop`/`didstop`,
/// resumes on `willstart`/`didstart`/`startAnimation`, releases its backing
/// bitmap when stopped or paused for a while, and logs its lifecycle to the
/// unified log (subsystem `io.github.tarzno.rosettica.saver`) so a misbehaving
/// host process can be attributed with
/// `log show --last 1h --predicate 'subsystem == "io.github.tarzno.rosettica.saver"'`.
@objc(RosetticaSaverView)
public final class RosetticaSaverView: ScreenSaverView {
    private static let log = Logger(subsystem: "io.github.tarzno.rosettica.saver", category: "lifecycle")

    /// ~10 s of consecutive paused frames before the backing bitmap
    /// (tens of MB per screen) is handed back.
    private static let releaseAfterSkippedFrames = 300

    private var scene: SaverScene?
    private var skippedFrames = 0
    private var observers: [NSObjectProtocol] = []
    private var isPreviewInstance = false
    private var loggedFirstFrame = false
    /// True between a screensaver `willstop`/`didstop` notification and the
    /// next start signal — the window during which a buggy lingering host
    /// would keep driving `animateOneFrame` invisibly.
    private var hostStopped = false

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        configure(isPreview: isPreview)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure(isPreview: false)
    }

    private func configure(isPreview: Bool) {
        animationTimeInterval = 1.0 / 30.0
        isPreviewInstance = isPreview
        scene = SaverScene(isPreview: isPreview)
        Self.log.notice("init preview=\(isPreview) size=\(self.bounds.width, format: .fixed(precision: 0))x\(self.bounds.height, format: .fixed(precision: 0))")

        let center = DistributedNotificationCenter.default()
        for (name, stopped) in [("com.apple.screensaver.willstart", false),
                                ("com.apple.screensaver.didstart", false),
                                ("com.apple.screensaver.willstop", true),
                                ("com.apple.screensaver.didstop", true)] {
            observers.append(center.addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                RosetticaSaverView.log.notice("distributed notification: \(name, privacy: .public)")
                self?.hostStopped = stopped
            })
        }
    }

    deinit {
        let center = DistributedNotificationCenter.default()
        for token in observers {
            center.removeObserver(token)
        }
        Self.log.notice("deinit")
    }

    // Note: startAnimation deliberately does NOT clear `hostStopped`. The
    // host can call it after a didstop that arrived mid-startup (observed
    // when the engine is dismissed while still fading in), which would
    // un-pause an instance that is about to linger invisibly. Fresh
    // instances start unpaused, real activations post willstart/didstart,
    // and previews are exempt — so the notifications alone are sufficient.
    public override func startAnimation() {
        super.startAnimation()
        skippedFrames = 0
        Self.log.notice("startAnimation size=\(self.bounds.width, format: .fixed(precision: 0))x\(self.bounds.height, format: .fixed(precision: 0))")
    }

    public override func stopAnimation() {
        super.stopAnimation()
        scene?.releaseResources()
        Self.log.notice("stopAnimation — resources released")
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            scene?.releaseResources()
            Self.log.notice("removed from window — resources released")
        }
    }

    public override func animateOneFrame() {
        // Pause only on the explicit "screensaver stopped" signal — never on
        // window visibility, which the extension host reports wrongly.
        // Previews (the System Settings thumbnail) are tiny and exempt.
        if hostStopped && !isPreviewInstance {
            skippedFrames += 1
            if skippedFrames == 1 {
                Self.log.notice("screensaver stopped — pausing all animation work")
            }
            if skippedFrames == Self.releaseAfterSkippedFrames {
                scene?.releaseResources()
                Self.log.notice("paused for \(Self.releaseAfterSkippedFrames) frames — resources released")
            }
            return
        }
        if skippedFrames > 0 {
            Self.log.notice("resuming after \(self.skippedFrames) skipped frames")
            skippedFrames = 0
        }
        if !loggedFirstFrame {
            loggedFirstFrame = true
            Self.log.notice("animating first frame size=\(self.bounds.width, format: .fixed(precision: 0))x\(self.bounds.height, format: .fixed(precision: 0))")
        }

        guard let scene else { return }
        let dirty = scene.advance(
            by: animationTimeInterval,
            size: bounds.size,
            scale: window?.backingScaleFactor ?? 2
        )
        if let dirty, !dirty.isEmpty {
            setNeedsDisplay(dirty)
        }
    }

    public override func draw(_ rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        scene?.draw(in: ctx, rect: rect, size: bounds.size)
    }

    public override var hasConfigureSheet: Bool { false }
}
