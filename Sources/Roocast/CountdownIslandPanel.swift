import AppKit

/// Notch-adjacent floating pill showing an ad-hoc countdown (Dynamic Island–like).
///
/// One active countdown at a time — `start` replaces any running pill.
@MainActor
final class CountdownIslandPanel: NSPanel {
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private var tick: Timer?
    private var remaining = 0
    private var total = 0

    init() {
        let size = NSSize(width: 120, height: 36)
        var style: NSWindow.StyleMask = [.borderless]
        if PanelFocusPolicy.usesNonactivatingStyle {
            style.insert(.nonactivatingPanel)
        }
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style,
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

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Begin or replace the countdown.
    func start(seconds: Int) {
        stopTimer()
        total = max(1, seconds)
        remaining = total
        timeLabel.stringValue = Countdown.format(seconds: remaining)
        positionUnderNotch()
        orderFrontRegardless()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickOnce()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    func cancel() {
        stopTimer()
        orderOut(nil)
    }

    private func tickOnce() {
        remaining -= 1
        if remaining <= 0 {
            timeLabel.stringValue = "0:00"
            stopTimer()
            NSSound(named: "Glass")?.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { [weak self] in
                self?.orderOut(nil)
            }
            return
        }
        timeLabel.stringValue = Countdown.format(seconds: remaining)
    }

    private func stopTimer() {
        tick?.invalidate()
        tick = nil
    }

    private func positionUnderNotch() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let frame = self.frame
        let x = visible.midX - frame.width / 2
        // Sit just under the menu bar / notch band.
        let y = visible.maxY - frame.height - 10
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    override func mouseDown(with event: NSEvent) {
        cancel()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == KeyCode.escape {
            cancel()
            return
        }
        super.sendEvent(event)
    }

    /// Become key so Esc reaches `sendEvent` while the pill is up.
    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        makeKey()
    }
}
