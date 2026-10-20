import SwiftUI
import AppKit

final class LauncherPanel: NSPanel {
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onEnter: (() -> Void)?
    let navigationState: NavigationState

    /// Only used if we somehow became frontmost (fallback path).
    private weak var previouslyActiveApp: NSRunningApplication?
    private var previousFocusSnapshot = FocusRestorer.Snapshot()
    private var isHiding = false
    /// True when this show cycle called `NSApp.activate` (should be rare).
    private var didStealActivation = false

    init(navigationState: NavigationState) {
        self.navigationState = navigationState

        var style: NSWindow.StyleMask = [.borderless]
        if PanelFocusPolicy.usesNonactivatingStyle {
            style.insert(.nonactivatingPanel)
        }

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: LauncherLayout.width, height: LauncherLayout.height),
            // nonactivatingPanel: take typing without deactivating Ghostty / its tab.
            // Must pair with hidesOnDeactivate=false — otherwise an inactive accessory
            // app never composites the panel (invisible but still key).
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
        // CRITICAL: false with nonactivatingPanel or the panel never paints while inactive.
        hidesOnDeactivate = PanelFocusPolicy.hidesOnDeactivate

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - LauncherLayout.width / 2
            let y = screenFrame.maxY - LauncherLayout.height - 80
            setFrameOrigin(NSPoint(x: x, y: y))
        }

        let contentView = ContentView(
            navigationState: navigationState,
            onDismiss: { [weak self] in
                // Launch path: target app activates itself.
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
        // Click-away: other app already has (or will get) focus.
        if isVisible {
            hide(restoreFocus: false)
        }
    }

    func show() {
        FocusRestorer.logTrustOnce()
        rememberPreviousFocus()
        didStealActivation = false

        setContentSize(NSSize(width: LauncherLayout.width, height: LauncherLayout.height))
        NotificationCenter.default.post(name: .launcherWillShow, object: nil)

        // Order front without activating Roocast — Ghostty keeps its tab first-responder.
        orderFrontRegardless()
        makeKey()

        // If we somehow aren't key/visible, last-resort activate (breaks tab focus).
        if PanelFocusPolicy.shouldFallbackActivate(isKeyWindow: isKeyWindow) {
            FocusRestorer.log("show: not key after makeKey — falling back to NSApp.activate")
            previouslyActiveApp = previouslyActiveApp ?? NSWorkspace.shared.frontmostApplication
            NSApp.activate(ignoringOtherApps: true)
            makeKeyAndOrderFront(nil)
            didStealActivation = true
        } else {
            FocusRestorer.log("show: nonactivating key window (Ghostty should keep tab focus)")
        }
    }

    /// Hide the panel. `restoreFocus` only matters if we stole activation this show.
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
            FocusRestorer.log("hide: no activation steal — Ghostty tab focus untouched")
            return
        }

        DispatchQueue.main.async {
            FocusRestorer.restore(app: app, snapshot: snapshot)
        }
    }

    private func rememberPreviousFocus() {
        let front = NSWorkspace.shared.frontmostApplication
        let ourPID = ProcessInfo.processInfo.processIdentifier
        if let front, front.processIdentifier != ourPID, !front.isTerminated {
            previouslyActiveApp = front
            previousFocusSnapshot = FocusRestorer.capture(pid: front.processIdentifier)
        } else {
            previouslyActiveApp = nil
            previousFocusSnapshot = FocusRestorer.Snapshot()
        }
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
