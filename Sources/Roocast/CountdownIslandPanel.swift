import AppKit

/// Notch-adjacent floating pill showing an ad-hoc countdown (Dynamic Island–like).
///
/// Compact centered digits (AC1/AC2). Hover/drag shows an overlay × on the top-left
/// corner without reflowing text (AC3). Grab-offset drag with no drift (AC4).
/// Nonactivating / never key (AC5).
@MainActor
final class CountdownIslandPanel: NSPanel {
    private let root = PillRootView(frame: .zero)
    private let pillView = NSView(frame: .zero)
    private let timeLabel = NSTextField(labelWithString: "0:00")
    private let closeButton = NSButton(frame: .zero)
    private var tick: Timer?
    private var remaining = 0
    private var total = 0
    private var grabOffset: CGPoint?
    /// Keep × visible while dragging even if the cursor briefly leaves the chrome.
    private var isDragging = false

    init() {
        let chrome = CountdownIslandLayout.chromeSize
        super.init(
            contentRect: NSRect(origin: .zero, size: chrome),
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
        ignoresMouseEvents = false

        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        root.onHoverChanged = { [weak self] hovering in
            self?.updateCloseVisibility(hovering: hovering)
        }
        root.onDragBegan = { [weak self] cursorScreen in
            guard let self else { return }
            self.isDragging = true
            self.grabOffset = CountdownIslandDrag.grabOffset(
                pillOrigin: self.frame.origin,
                cursor: cursorScreen
            )
            self.setCloseVisible(true)
        }
        root.onDragMoved = { [weak self] cursorScreen in
            guard let self, let grab = self.grabOffset else { return }
            let origin = CountdownIslandDrag.origin(cursor: cursorScreen, grabOffset: grab)
            self.setFrameOrigin(origin)
        }
        root.onDragEnded = { [weak self] cursorStillInside in
            guard let self else { return }
            self.isDragging = false
            self.grabOffset = nil
            self.updateCloseVisibility(hovering: cursorStillInside)
        }
        root.closeButton = closeButton

        let pill = CountdownIslandLayout.pillFrame()
        pillView.frame = pill
        pillView.wantsLayer = true
        pillView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        pillView.layer?.cornerRadius = CountdownIslandLayout.pillSize.height / 2
        pillView.layer?.masksToBounds = true
        root.addSubview(pillView)

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        timeLabel.textColor = .white
        timeLabel.alignment = .center
        timeLabel.isBezeled = false
        timeLabel.drawsBackground = false
        timeLabel.isSelectable = false
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        pillView.addSubview(timeLabel)
        NSLayoutConstraint.activate([
            timeLabel.centerXAnchor.constraint(equalTo: pillView.centerXAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
        ])

        let badge = CountdownIslandLayout.badgeFrame(pillFrame: pill)
        closeButton.frame = badge
        closeButton.image = NSImage(
            systemSymbolName: "xmark.circle.fill",
            accessibilityDescription: "Cancel countdown"
        )
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.imageScaling = .scaleProportionallyUpOrDown
        closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.95)
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.isHidden = true
        closeButton.alphaValue = 0
        closeButton.setButtonType(.momentaryChange)
        root.addSubview(closeButton)

        contentView = root
        setContentSize(chrome)
        root.frame = NSRect(origin: .zero, size: chrome)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func start(seconds: Int) {
        stopTimer()
        total = max(1, seconds)
        remaining = total
        timeLabel.stringValue = Countdown.format(seconds: remaining)
        isDragging = false
        grabOffset = nil
        setCloseVisible(false)
        positionUnderNotch()
        orderFrontRegardless()
        print("[countdown] start \(seconds)s compact=1 overlayX=1 grabDrag=1")

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

    private func updateCloseVisibility(hovering: Bool) {
        setCloseVisible(hovering || isDragging)
    }

    private func setCloseVisible(_ visible: Bool) {
        closeButton.isHidden = !visible
        closeButton.alphaValue = visible ? 1 : 0
    }

    private func positionUnderNotch() {
        guard let screen = NSScreen.main else { return }
        let origin = CountdownIslandLayout.defaultOrigin(
            visibleFrame: screen.visibleFrame,
            chromeSize: CountdownIslandLayout.chromeSize
        )
        setFrameOrigin(origin)
    }
}

/// Pill chrome: hover tracking + grab-offset drag.
private final class PillRootView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    var onDragBegan: ((CGPoint) -> Void)?
    var onDragMoved: ((CGPoint) -> Void)?
    var onDragEnded: ((Bool) -> Void)?
    weak var closeButton: NSView?
    private var tracking: NSTrackingArea?
    private var dragActive = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        if let closeButton, hit === closeButton || hit.isDescendant(of: closeButton) {
            return hit
        }
        return self
    }

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
        if dragActive { return }
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragActive = true
        let cursor = window.convertPoint(toScreen: event.locationInWindow)
        onDragBegan?(cursor)
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragActive, let window else { return }
        let cursor = window.convertPoint(toScreen: event.locationInWindow)
        onDragMoved?(cursor)
    }

    override func mouseUp(with event: NSEvent) {
        guard dragActive else { return }
        dragActive = false
        let local = convert(event.locationInWindow, from: nil)
        onDragEnded?(bounds.contains(local))
    }
}
