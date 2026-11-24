import AppKit

/// Notch-adjacent floating pill showing an ad-hoc countdown (Dynamic Island–like).
///
/// Nonactivating overlay (never key). Hover reveals a close button; no Esc cancel
/// (so launcher ⌘K → Esc cannot kill the timer). One active countdown at a time.
@MainActor
final class CountdownIslandPanel: NSPanel {
    private let root = HoverRootView(frame: .zero)
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private let closeButton = NSButton(frame: .zero)
    private var tick: Timer?
    private var remaining = 0
    private var total = 0
    private let collapsedSize = NSSize(width: 120, height: 36)
    private let expandedSize = NSSize(width: 148, height: 36)

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: collapsedSize),
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
        // Need hit-testing for hover close; only this small pill intercepts clicks.
        ignoresMouseEvents = false

        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        root.layer?.cornerRadius = collapsedSize.height / 2
        root.layer?.masksToBounds = true
        root.onHoverChanged = { [weak self] hovering in
            self?.setCloseVisible(hovering)
        }

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        timeLabel.textColor = .white
        timeLabel.alignment = .center
        timeLabel.isBezeled = false
        timeLabel.drawsBackground = false
        timeLabel.isSelectable = false
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(timeLabel)

        closeButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "Cancel countdown"
        )
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.9)
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.isHidden = true
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setButtonType(.momentaryChange)
        root.addSubview(closeButton)

        NSLayoutConstraint.activate([
            timeLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            timeLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            timeLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),

            closeButton.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18),
        ])

        contentView = root
        setContentSize(collapsedSize)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Begin or replace the countdown.
    func start(seconds: Int) {
        stopTimer()
        total = max(1, seconds)
        remaining = total
        timeLabel.stringValue = Countdown.format(seconds: remaining)
        setCloseVisible(false)
        positionUnderNotch()
        orderFrontRegardless()
        print("[countdown] start \(seconds)s hoverClose=1 key=0 alpha=0.45")

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
        stopTimer()
        orderOut(nil)
    }

    @objc private func closeClicked() {
        cancel()
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

    private func setCloseVisible(_ visible: Bool) {
        closeButton.isHidden = !visible
        let size = visible ? expandedSize : collapsedSize
        let oldOrigin = frame.origin
        // Keep horizontal center stable when expanding for the ×.
        let midX = oldOrigin.x + frame.width / 2
        setContentSize(size)
        setFrameOrigin(NSPoint(x: midX - size.width / 2, y: oldOrigin.y))
        root.frame = NSRect(origin: .zero, size: size)
        root.layer?.cornerRadius = size.height / 2
        root.updateTrackingAreas()
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

/// Root view that reports mouse enter/exit for the hover close control.
private final class HoverRootView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeAlways,
            .inVisibleRect,
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }
}
