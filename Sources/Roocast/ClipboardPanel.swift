import SwiftUI
import AppKit

final class ClipboardPanel: NSPanel {
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onEnter: (() -> Void)?

    private weak var previouslyActiveApp: NSRunningApplication?
    private var previousFocusSnapshot = FocusRestorer.Snapshot()
    private var isHiding = false
    private var didStealActivation = false

    init(store: ClipboardStore, navigationState: NavigationState, onPaste: @escaping (ClipboardItem) -> Void) {
        var style: NSWindow.StyleMask = [.borderless]
        if PanelFocusPolicy.usesNonactivatingStyle {
            style.insert(.nonactivatingPanel)
        }

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: ClipboardLayout.width, height: ClipboardLayout.height),
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
        hidesOnDeactivate = PanelFocusPolicy.hidesOnDeactivate

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - ClipboardLayout.width / 2
            let y = screenFrame.maxY - ClipboardLayout.height - 80
            setFrameOrigin(NSPoint(x: x, y: y))
        }

        let contentView = ClipboardView(
            store: store,
            navigationState: navigationState,
            onPaste: onPaste,
            onDismiss: { [weak self] in
                self?.hide(restoreFocus: false)
            }
        )
        let hosting = NSHostingController(rootView: contentView)
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        contentViewController = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        if isVisible {
            hide(restoreFocus: false)
        }
    }

    func show() {
        FocusRestorer.logTrustOnce()
        rememberPreviousFocus()
        didStealActivation = false

        setContentSize(NSSize(width: ClipboardLayout.width, height: ClipboardLayout.height))
        NotificationCenter.default.post(name: .clipboardWillShow, object: nil)

        orderFrontRegardless()
        makeKey()
        focusSearchField()

        if PanelFocusPolicy.shouldFallbackActivate(isKeyWindow: isKeyWindow) {
            FocusRestorer.log("clipboard show: fallback NSApp.activate")
            previouslyActiveApp = previouslyActiveApp ?? NSWorkspace.shared.frontmostApplication
            NSApp.activate(ignoringOtherApps: true)
            makeKeyAndOrderFront(nil)
            didStealActivation = true
            focusSearchField()
        } else {
            FocusRestorer.log("clipboard show: nonactivating key window")
        }
    }

    func hide(restoreFocus: Bool) {
        guard !isHiding else { return }
        isHiding = true
        defer { isHiding = false }

        let shouldRestore = PanelFocusPolicy.shouldRestoreFocus(
            restoreRequested: restoreFocus,
            didStealActivation: didStealActivation
        )
        let appToRestore = shouldRestore ? previouslyActiveApp : nil
        let snapshot = shouldRestore ? previousFocusSnapshot : FocusRestorer.Snapshot()
        previouslyActiveApp = nil
        previousFocusSnapshot = FocusRestorer.Snapshot()
        didStealActivation = false

        if isVisible {
            orderOut(nil)
        }

        guard let app = appToRestore, !app.isTerminated else {
            return
        }

        DispatchQueue.main.async {
            FocusRestorer.restore(app: app, snapshot: snapshot)
        }
    }

    /// Hide and restore prior app focus (used before synthesizing ⌘V).
    /// Returns the app that should receive the paste, if any.
    @discardableResult
    func hideForPaste() -> NSRunningApplication? {
        let ourPID = ProcessInfo.processInfo.processIdentifier
        var appToRestore = previouslyActiveApp
        let snapshot = previousFocusSnapshot
        previouslyActiveApp = nil
        previousFocusSnapshot = FocusRestorer.Snapshot()
        didStealActivation = false

        if isVisible {
            orderOut(nil)
        }

        // Fallback: if show() missed the prior app (e.g. Roocast briefly frontmost),
        // pick the current frontmost non-Roocast app after we order out.
        if appToRestore == nil || appToRestore?.isTerminated == true {
            let front = NSWorkspace.shared.frontmostApplication
            if let front, front.processIdentifier != ourPID, !front.isTerminated {
                appToRestore = front
                FocusRestorer.log("clipboard hideForPaste: fallback frontmost=\(front.localizedName ?? "?")")
            }
        }

        guard let app = appToRestore, !app.isTerminated else {
            FocusRestorer.log("clipboard hideForPaste: no app to restore")
            return nil
        }

        // Always activate the target so ⌘V lands there — even without Accessibility trust.
        let activated = app.activate()
        FocusRestorer.log(
            "clipboard hideForPaste: activate \(app.localizedName ?? "?") ok=\(activated)"
        )
        FocusRestorer.restore(app: app, snapshot: snapshot)
        return app
    }

    private func rememberPreviousFocus() {
        let front = NSWorkspace.shared.frontmostApplication
        let ourPID = ProcessInfo.processInfo.processIdentifier
        if let front, front.processIdentifier != ourPID, !front.isTerminated {
            previouslyActiveApp = front
            previousFocusSnapshot = FocusRestorer.capture(pid: front.processIdentifier)
            FocusRestorer.log("clipboard remember: \(front.localizedName ?? "?") pid=\(front.processIdentifier)")
        } else {
            previouslyActiveApp = nil
            previousFocusSnapshot = FocusRestorer.Snapshot()
            FocusRestorer.log("clipboard remember: no prior app (front=\(front?.localizedName ?? "nil"))")
        }
    }

    private func focusSearchField() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let field = Self.findCustomTextField(in: self.contentView) {
                self.makeFirstResponder(field)
            }
        }
    }

    private static func findCustomTextField(in view: NSView?) -> CustomTextField? {
        guard let view else { return nil }
        if let field = view as? CustomTextField { return field }
        for sub in view.subviews {
            if let found = findCustomTextField(in: sub) { return found }
        }
        return nil
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            switch event.keyCode {
            case 126:
                onArrowUp?()
                return
            case 125:
                onArrowDown?()
                return
            case 36:
                onEnter?()
                return
            case 53:
                hide(restoreFocus: true)
                return
            default:
                break
            }
        }
        super.sendEvent(event)
    }
}
