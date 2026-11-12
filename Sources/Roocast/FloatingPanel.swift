import SwiftUI
import AppKit

/// Shared nonactivating floating panel: show/hide, prior-app focus, arrow/Enter/Esc.
///
/// `LauncherPanel` and `ClipboardPanel` specialize content only; focus policy lives here.
class FloatingPanel: NSPanel {
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onEnter: (() -> Void)?
    /// ⌘K toggles the row actions menu (Raycast-style) before the search field sees it.
    var onCommandK: (() -> Void)?
    /// While the actions menu is up, navigation keys route to the menu; return true
    /// if consumed, false to let the key fall through to the search field.
    var onMenuKey: ((UInt16) -> Bool)?

    /// Prior app captured at show — must be **strong**.
    /// A weak `NSRunningApplication` from `frontmostApplication` often deallocates
    /// after the event-loop turn, so paste would always hit the frontmost fallback.
    private(set) var previouslyActiveApp: NSRunningApplication?
    private var previousAppPID: pid_t?
    private(set) var previousFocusSnapshot = FocusRestorer.Snapshot()
    private(set) var didStealActivation = false

    private var isHiding = false
    private let panelSize: NSSize
    private let willShowNotification: Notification.Name
    private let logPrefix: String

    init(
        size: NSSize,
        willShowNotification: Notification.Name,
        logPrefix: String
    ) {
        self.panelSize = size
        self.willShowNotification = willShowNotification
        self.logPrefix = logPrefix

        var style: NSWindow.StyleMask = [.borderless]
        if PanelFocusPolicy.usesNonactivatingStyle {
            style.insert(.nonactivatingPanel)
        }

        super.init(
            contentRect: NSRect(origin: .zero, size: size),
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

        positionNearTopOfMainScreen()
    }

    /// Install a SwiftUI hosting controller with a clear layer-backed root.
    func installHostingController<Content: View>(_ rootView: Content) {
        let hosting = NSHostingController(rootView: rootView)
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

    /// Show the panel. `afterBecomeKey` runs after makeKey (e.g. focus search field).
    func show(afterBecomeKey: (() -> Void)? = nil) {
        FocusRestorer.logTrustOnce()
        rememberPreviousFocus()
        didStealActivation = false

        setContentSize(panelSize)
        NotificationCenter.default.post(name: willShowNotification, object: nil)

        // Order front without activating Roocast — Ghostty keeps its tab first-responder.
        orderFrontRegardless()
        makeKey()
        afterBecomeKey?()

        if PanelFocusPolicy.shouldFallbackActivate(isKeyWindow: isKeyWindow) {
            FocusRestorer.log("\(logPrefix)show: fallback NSApp.activate")
            previouslyActiveApp = previouslyActiveApp ?? NSWorkspace.shared.frontmostApplication
            NSApp.activate(ignoringOtherApps: true)
            makeKeyAndOrderFront(nil)
            didStealActivation = true
            afterBecomeKey?()
        } else {
            FocusRestorer.log("\(logPrefix)show: nonactivating key window")
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
        clearPreviousFocus()
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

    /// Hide and activate the prior app (clipboard paste path). Returns the target if any.
    ///
    /// Caret-safe: the click fallback that FocusRestorer uses for Metal terminals
    /// must NEVER run on this path — a click inside a text view moves the caret,
    /// so ⌘V would paste at the click point instead of the user's cursor. When the
    /// nonactivating panel never stole activation, the prior app still holds focus
    /// and no restore is needed at all: the caret is exactly where the user left it.
    @discardableResult
    func hideForPaste() -> NSRunningApplication? {
        let ourPID = ProcessInfo.processInfo.processIdentifier
        let rememberedPID = previousAppPID
        let stoleActivation = didStealActivation
        var appToRestore = previouslyActiveApp
        let snapshot = previousFocusSnapshot
        clearPreviousFocus()
        didStealActivation = false

        if isVisible {
            orderOut(nil)
        }

        // Re-resolve by PID if the remembered object was cleared somehow.
        if (appToRestore == nil || appToRestore?.isTerminated == true),
           let rememberedPID,
           let byPID = NSRunningApplication(processIdentifier: rememberedPID),
           !byPID.isTerminated
        {
            appToRestore = byPID
            FocusRestorer.log("\(logPrefix)hideForPaste: resolved pid=\(rememberedPID)")
        }

        if appToRestore == nil || appToRestore?.isTerminated == true {
            let front = NSWorkspace.shared.frontmostApplication
            if let front, front.processIdentifier != ourPID, !front.isTerminated {
                appToRestore = front
                FocusRestorer.log("\(logPrefix)hideForPaste: fallback frontmost=\(front.localizedName ?? "?")")
            }
        }

        guard let app = appToRestore, !app.isTerminated else {
            FocusRestorer.log("\(logPrefix)hideForPaste: no app to restore")
            return nil
        }

        if stoleActivation {
            let activated = app.activate()
            FocusRestorer.log(
                "\(logPrefix)hideForPaste: activate \(app.localizedName ?? "?") pid=\(app.processIdentifier) ok=\(activated)"
            )
            // Clicks are forbidden here — they reposition the caret (see doc comment).
            FocusRestorer.restore(app: app, snapshot: snapshot, allowClick: false)
        } else {
            // Happy path: the nonactivating panel never took activation, so the
            // prior app is still active with its caret untouched. Just hand back
            // the app so the ⌘V poster waits for it.
            FocusRestorer.log(
                "\(logPrefix)hideForPaste: activation intact — skip restore, paste target \(app.localizedName ?? "?")"
            )
        }
        return app
    }

    func rememberPreviousFocus() {
        let front = NSWorkspace.shared.frontmostApplication
        let ourPID = ProcessInfo.processInfo.processIdentifier
        if let front, front.processIdentifier != ourPID, !front.isTerminated {
            previouslyActiveApp = front
            previousAppPID = front.processIdentifier
            previousFocusSnapshot = FocusRestorer.capture(pid: front.processIdentifier)
            FocusRestorer.log(
                "\(logPrefix)remember: \(front.localizedName ?? "?") pid=\(front.processIdentifier)"
            )
        } else {
            clearPreviousFocus()
            FocusRestorer.log("\(logPrefix)remember: no prior app (front=\(front?.localizedName ?? "nil"))")
        }
    }

    private func clearPreviousFocus() {
        previouslyActiveApp = nil
        previousAppPID = nil
        previousFocusSnapshot = FocusRestorer.Snapshot()
    }

    private func positionNearTopOfMainScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - panelSize.width / 2
        let y = screenFrame.maxY - panelSize.height - 80
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            // ⌘K toggles the row actions menu (Raycast-style) before the search
            // field sees it — the menu is the delete path, so no direct chords.
            if event.keyCode == KeyCode.k, Self.isBareCommand(event.modifierFlags) {
                onCommandK?()
                return
            }
            // Only intercept bare navigation keys. Leave ⌘C / ⌘X / ⌘V / etc. alone
            // so the search field's performKeyEquivalent can handle edit shortcuts.
            if Self.isBareNavigationModifiers(event.modifierFlags) {
                // The actions menu consumes navigation keys when open; letters
                // still fall through to the search field (and close the menu).
                if let onMenuKey, onMenuKey(event.keyCode) {
                    return
                }
                switch event.keyCode {
                case KeyCode.upArrow:
                    onArrowUp?()
                    return
                case KeyCode.downArrow:
                    onArrowDown?()
                    return
                case KeyCode.returnKey, KeyCode.keypadEnter:
                    onEnter?()
                    return
                case KeyCode.escape:
                    hide(restoreFocus: true)
                    return
                default:
                    break
                }
            }
        }
        super.sendEvent(event)
    }

    /// Ignore device-dependent flag noise; only treat ⌘/⌥/⌃ as blocking navigation.
    private static func isBareNavigationModifiers(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .option, .control])
            .isEmpty
    }

    /// Bare ⌘ — no shift, option, or control riding along (⌘K only, not ⌘⇧K).
    private static func isBareCommand(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .shift, .option, .control])
            == NSEvent.ModifierFlags.command
    }
}

/// Carbon / AppKit virtual key codes used by floating panels.
enum KeyCode {
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let escape: UInt16 = 53
    static let upArrow: UInt16 = 126
    static let downArrow: UInt16 = 125
    /// Bare ⌘K — the row actions menu toggle on the clipboard panel.
    static let k: UInt16 = 40
    /// fn+backspace — tinycast parity: delete entry chords removed, deletes are
    /// menu-only (⌘K → select → enter), so this key no longer deletes.
    static let forwardDelete: UInt16 = 117
}
