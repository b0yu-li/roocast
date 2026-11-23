import AppKit

/// Notch-adjacent floating pill showing an ad-hoc countdown (Dynamic Island–like).
///
/// Pure overlay chrome: nonactivating, never key, mouse events pass through so
/// apps / the menu bar underneath stay usable. Esc cancels (event monitor).
/// One active countdown at a time — `start` replaces any running pill.
@MainActor
final class CountdownIslandPanel: NSPanel {
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private var tick: Timer?
    private var remaining = 0
    private var total = 0
    private var escapeMonitors: EscapeMonitors?

    init() {
        let size = NSSize(width: 120, height: 36)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        // Clicks fall through to whatever is under the pill (menu bar, app, etc.).
        ignoresMouseEvents = true

        let root = NSView(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.88).cgColor
        root.layer?.cornerRadius = size.height / 2
        root.layer?.masksToBounds = true

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        timeLabel.textColor = .white
        timeLabel.alignment = .center
        timeLabel.isBezeled = false
        timeLabel.drawsBackground = false
        timeLabel.isSelectable = false
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(timeLabel)
        NSLayoutConstraint.activate([
            timeLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            timeLabel.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 16),
            timeLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -16),
        ])

        contentView = root
        setContentSize(size)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Begin or replace the countdown.
    func start(seconds: Int) {
        stopTimer()
        total = max(1, seconds)
        remaining = total
        timeLabel.stringValue = Countdown.format(seconds: remaining)
        positionUnderNotch()
        // Visual only — do not makeKey / activate (would steal focus from Ghostty etc.).
        orderFrontRegardless()
        installEscapeMonitor()
        print("[countdown] start \(seconds)s passThrough=1 key=0")

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickOnce()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    func cancel() {
        print("[countdown] cancel")
        teardown()
        orderOut(nil)
    }

    private func tickOnce() {
        remaining -= 1
        if remaining <= 0 {
            timeLabel.stringValue = "0:00"
            stopTimer()
            removeEscapeMonitor()
            NSSound(named: "Glass")?.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
                self?.orderOut(nil)
            }
            return
        }
        timeLabel.stringValue = Countdown.format(seconds: remaining)
    }

    private func teardown() {
        stopTimer()
        removeEscapeMonitor()
    }

    private func stopTimer() {
        tick?.invalidate()
        tick = nil
    }

    private func installEscapeMonitor() {
        removeEscapeMonitor()
        // Global: Esc while another app is frontmost (island never becomes key).
        // Requires Accessibility / Input Monitoring — same trust Roocast already uses.
        let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == KeyCode.escape else { return }
            Task { @MainActor in
                self?.cancel()
            }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == KeyCode.escape else { return event }
            Task { @MainActor in
                self?.cancel()
            }
            return nil
        }
        guard let local else { return }
        escapeMonitors = EscapeMonitors(global: global, local: local)
    }

    private func removeEscapeMonitor() {
        guard let monitors = escapeMonitors else { return }
        escapeMonitors = nil
        if let global = monitors.global {
            NSEvent.removeMonitor(global)
        }
        NSEvent.removeMonitor(monitors.local)
    }

    private func positionUnderNotch() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let frame = self.frame
        let x = visible.midX - frame.width / 2
        let y = visible.maxY - frame.height - 10
        setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private final class EscapeMonitors {
    let global: Any?
    let local: Any

    init(global: Any?, local: Any) {
        self.global = global
        self.local = local
    }
}
