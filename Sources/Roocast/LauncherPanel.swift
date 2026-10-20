import SwiftUI
import AppKit
import ApplicationServices

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

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: LauncherLayout.width, height: LauncherLayout.height),
            // nonactivatingPanel: take typing without deactivating Ghostty / its tab.
            // Must pair with hidesOnDeactivate=false — otherwise an inactive accessory
            // app never composites the panel (invisible but still key).
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
        // CRITICAL: false. With nonactivatingPanel the app stays inactive; true would
        // hide/un-composite the panel while Ghostty remains frontmost.
        hidesOnDeactivate = false

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
        if !isKeyWindow {
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

        let shouldRestore = restoreFocus && didStealActivation
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

// MARK: - Focus restore (fallback when activation was stolen)

enum FocusRestorer {
    private static var didLogTrust = false

    struct Snapshot {
        var window: AXUIElement?
        var element: AXUIElement?
        var clickPoint: CGPoint?
    }

    static func log(_ message: String) {
        let line = "Roocast focus: \(message)"
        NSLog("%@", line)
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Roocast", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("focus.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\(stamp) \(line)\n"
        if let data = entry.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: file.path),
               let handle = try? FileHandle(forWritingTo: file) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: file)
            }
        }
    }

    static func logTrustOnce() {
        let trusted = isTrusted()
        if !didLogTrust {
            didLogTrust = true
            log("Accessibility trusted=\(trusted ? 1 : 0)")
        }
    }

    static func isTrusted() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func capture(pid: pid_t) -> Snapshot {
        guard isTrusted() else { return Snapshot() }

        let appElement = AXUIElementCreateApplication(pid)
        var window: AXUIElement?
        var element: AXUIElement?

        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowRef
        ) == .success, let windowRef {
            window = (windowRef as! AXUIElement)
        }

        var elementRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &elementRef
        ) == .success, let elementRef {
            element = (elementRef as! AXUIElement)
        }

        if element == nil {
            let systemWide = AXUIElementCreateSystemWide()
            var focused: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                systemWide,
                kAXFocusedUIElementAttribute as CFString,
                &focused
            ) == .success, let focused {
                element = (focused as! AXUIElement)
            }
        }

        let clickPoint = centerPoint(of: element) ?? centerPoint(of: window)
        return Snapshot(window: window, element: element, clickPoint: clickPoint)
    }

    static func restore(app: NSRunningApplication, snapshot: Snapshot, attempt: Int = 0) {
        guard !app.isTerminated else { return }

        if attempt == 0 {
            app.activate()
            log("fallback restore activate \(app.localizedName ?? "?")")
        }

        guard isTrusted() else { return }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(
            appElement,
            kAXFrontmostAttribute as CFString,
            kCFBooleanTrue!
        )

        if let window = snapshot.window {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(
                appElement,
                kAXFocusedWindowAttribute as CFString,
                window
            )
            AXUIElementSetAttributeValue(
                appElement,
                kAXMainWindowAttribute as CFString,
                window
            )
        }

        if let element = snapshot.element {
            AXUIElementSetAttributeValue(
                appElement,
                kAXFocusedUIElementAttribute as CFString,
                element
            )
            AXUIElementSetAttributeValue(
                element,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue!
            )
        }

        if attempt == 1 || attempt == 3, let point = snapshot.clickPoint {
            click(at: point)
        }

        if attempt < 4 {
            let delay = 0.05 * Double(attempt + 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                restore(app: app, snapshot: snapshot, attempt: attempt + 1)
            }
        }
    }

    private static func centerPoint(of element: AXUIElement?) -> CGPoint? {
        guard let element else { return nil }
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef
        else {
            return nil
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size),
              size.width > 1, size.height > 1
        else {
            return nil
        }
        return CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    }

    private static func click(at point: CGPoint) {
        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0
        let cgPoint = CGPoint(x: point.x, y: primaryHeight - point.y)
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDown,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
              ),
              let up = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseUp,
                mouseCursorPosition: cgPoint,
                mouseButton: .left
              )
        else {
            return
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
