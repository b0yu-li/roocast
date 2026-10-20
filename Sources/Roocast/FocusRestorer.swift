import AppKit
import ApplicationServices

/// Captures / restores prior-app focus when the panel had to steal activation.
///
/// On the happy (nonactivating) path this is unused — Ghostty never loses tab focus.
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

        if PanelFocusPolicy.shouldClickOnRestoreAttempt(attempt), let point = snapshot.clickPoint {
            click(at: point)
        }

        if attempt < PanelFocusPolicy.maxRestoreAttempt {
            let delay = PanelFocusPolicy.restoreDelaySeconds(forAttempt: attempt)
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
        let cgPoint = PanelFocusPolicy.cgEventPoint(fromAX: point, primaryScreenHeight: primaryHeight)
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
