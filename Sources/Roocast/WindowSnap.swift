import AppKit
import ApplicationServices

/// Built-in window snap: left / right half, maximize, or reasonable size.
///
/// Maximize fills `NSScreen.visibleFrame` (menu bar / Dock stay) — never toggles
/// macOS `AXFullScreen` (which would create a new Space).
/// Reasonable Size mirrors Tinycast: ~60% of the visible frame, capped, centered.
///
/// Mirrors Tinycast's AX path (`AXGeometry` + `AXWindowAccess.write`):
/// work in Accessibility top-left coordinates, resolve the target window on the
/// remembered app, then apply size → position → size.
enum WindowSnap {
    enum Command: Hashable {
        case left
        case right
        /// Fill the display's visible frame (current Space). Not macOS fullscreen.
        case maximize
        /// ~60% of visible frame, capped at 1025×900, centered (Tinycast).
        case reasonableSize
    }

    /// Tinycast `reasonableSizeFraction` — fraction of the visible canvas.
    nonisolated static let reasonableSizeFraction: CGFloat = 0.6
    /// Tinycast hard ceiling so 60% of a 5K display stays a usable window size.
    nonisolated static let reasonableSizeMax = CGSize(width: 1025, height: 900)

    /// Split a visible frame into a left or right half (same math in AppKit or AX space).
    /// Odd pixel goes to the right half so the two halves cover the frame exactly.
    /// Prefer `targetFrame` for maximize / reasonable size.
    nonisolated static func halfFrame(of visibleFrame: CGRect, side: Command) -> CGRect {
        let leftWidth = floor(visibleFrame.width / 2)
        switch side {
        case .left:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: leftWidth,
                height: visibleFrame.height
            )
        case .right:
            return CGRect(
                x: visibleFrame.minX + leftWidth,
                y: visibleFrame.minY,
                width: visibleFrame.width - leftWidth,
                height: visibleFrame.height
            )
        case .maximize:
            return visibleFrame
        case .reasonableSize:
            return reasonableSizeFrame(of: visibleFrame)
        }
    }

    /// Tinycast reasonable size: `min(canvas * 0.6, 1025×900)`, centered, edges rounded.
    nonisolated static func reasonableSizeFrame(of visibleFrame: CGRect) -> CGRect {
        let size = CGSize(
            width: min(visibleFrame.width * reasonableSizeFraction, reasonableSizeMax.width),
            height: min(visibleFrame.height * reasonableSizeFraction, reasonableSizeMax.height)
        )
        let centered = CGRect(
            x: visibleFrame.minX + (visibleFrame.width - size.width) / 2,
            y: visibleFrame.minY + (visibleFrame.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
        return rounded(centered)
    }

    /// Round the four edges so shared boundaries stay pixel-aligned (Tinycast).
    nonisolated static func rounded(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded()
        let minY = rect.minY.rounded()
        let maxX = rect.maxX.rounded()
        let maxY = rect.maxY.rounded()
        return CGRect(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }

    /// Target frame in the same coordinate space as `visibleFrame`.
    nonisolated static func targetFrame(of visibleFrame: CGRect, command: Command) -> CGRect {
        switch command {
        case .left, .right:
            return halfFrame(of: visibleFrame, side: command)
        case .maximize:
            return visibleFrame
        case .reasonableSize:
            return reasonableSizeFrame(of: visibleFrame)
        }
    }

    /// AppKit bottom-left ↔ AX top-left (Y flipped around primary screen height).
    /// Involutive: `flip(flip(r)) == r`.
    nonisolated static func flip(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryScreenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Resize/move the focused window of `app` per `command`.
    /// Requires Accessibility trust (prompts + opens System Settings when denied).
    @MainActor
    static func apply(command: Command, activating app: NSRunningApplication?) {
        guard FocusRestorer.ensureTrusted(prompt: true) else {
            FocusRestorer.log("windowSnap: Accessibility not trusted — abort \(command)")
            FocusRestorer.openAccessibilitySettings()
            return
        }

        guard let app, !app.isTerminated else {
            FocusRestorer.log("windowSnap: no prior app")
            return
        }
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            FocusRestorer.log("windowSnap: refusing to snap our own process")
            return
        }

        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 1)
        guard let window = targetWindow(in: application) else {
            FocusRestorer.log("windowSnap: no eligible window for \(app.localizedName ?? "?")")
            return
        }
        AXUIElementSetMessagingTimeout(window, 1)

        // Native fullscreen owns a Space — exit it before geometry writes (Tinycast leaves
        // fullscreen alone; we exit so Maximize can fill the desktop Space instead).
        if isNativeFullScreen(window) {
            FocusRestorer.log("windowSnap: exiting native fullscreen before \(command)")
            _ = setNativeFullScreen(window, false)
        }

        let primaryHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0

        guard let currentAX = axFrame(of: window) else {
            FocusRestorer.log("windowSnap: cannot read window frame")
            return
        }

        let screen = screen(containingAppKitCenterOf: currentAX, primaryScreenHeight: primaryHeight)
            ?? NSScreen.main
        guard let screen else {
            FocusRestorer.log("windowSnap: no screen")
            return
        }

        // Tinycast: convert visibleFrame into AX space, then place there.
        let axVisible = flip(screen.visibleFrame, primaryScreenHeight: primaryHeight)
        let target = targetFrame(of: axVisible, command: command)

        var settable = DarwinBoolean(false)
        let canResize =
            AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable)
            == .success && settable.boolValue

        let restoreEnhancedUI = suppressEnhancedUserInterface(on: application)
        defer { restoreEnhancedUI() }

        guard write(target, to: window, canResize: canResize) else {
            FocusRestorer.log(
                "windowSnap: write failed \(command) app=\(app.localizedName ?? "?") target=\(target)"
            )
            return
        }

        FocusRestorer.log(
            "windowSnap: \(command) app=\(app.localizedName ?? "?") target=\(target) canResize=\(canResize)"
        )

        // Tinycast `AXWindowAccess.focus`: raise + frontmost + activate.
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(
            application,
            kAXFrontmostAttribute as CFString,
            kCFBooleanTrue
        )
        app.activate()
    }

    // MARK: - AX write (Tinycast size → position → size)

    @MainActor
    private static func write(_ target: CGRect, to window: AXUIElement, canResize: Bool) -> Bool {
        if canResize {
            _ = setSize(target.size, on: window)
            guard setPosition(target.origin, on: window) else { return false }
            _ = setSize(target.size, on: window)
        } else {
            // Keep size; pin to the leading/trailing edge of the half.
            guard setPosition(target.origin, on: window) else { return false }
        }
        return true
    }

    @MainActor
    private static func setPosition(_ origin: CGPoint, on window: AXUIElement) -> Bool {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return false }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            == .success
    }

    @MainActor
    private static func setSize(_ size: CGSize, on window: AXUIElement) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) == .success
    }

    /// Electron / Chromium: clear enhanced UI around geometry writes (Tinycast).
    @MainActor
    private static func suppressEnhancedUserInterface(on application: AXUIElement) -> () -> Void {
        let attribute = "AXEnhancedUserInterface" as CFString
        guard !NSWorkspace.shared.isVoiceOverEnabled else { return {} }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, attribute, &value) == .success,
              (value as? Bool) == true
        else { return {} }
        AXUIElementSetAttributeValue(application, attribute, kCFBooleanFalse)
        return { AXUIElementSetAttributeValue(application, attribute, kCFBooleanTrue) }
    }

    // MARK: - Window resolution (Tinycast: focused → main → first eligible)

    @MainActor
    private static func targetWindow(in application: AXUIElement) -> AXUIElement? {
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let window = copyElement(application, attribute as String), isEligible(window) {
                return window
            }
        }
        return windows(in: application).first(where: isEligible)
    }

    @MainActor
    private static func windows(in application: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
                == .success,
              let windows = value as? [AXUIElement]
        else { return [] }
        return windows
    }

    @MainActor
    private static func isEligible(_ window: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleRef)
                == .success,
              (roleRef as? String) == (kAXWindowRole as String)
        else { return false }

        var minimizedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef)
            == .success,
           (minimizedRef as? Bool) == true
        {
            return false
        }
        return axFrame(of: window) != nil
    }

    @MainActor
    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    @MainActor
    private static func axFrame(of window: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
                == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
                == .success,
              let posRef, let sizeRef
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posRef as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size),
              size.width > 1, size.height > 1
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Screen whose AppKit frame contains the window center (AX frame flipped back).
    @MainActor
    private static func screen(
        containingAppKitCenterOf axFrame: CGRect,
        primaryScreenHeight: CGFloat
    ) -> NSScreen? {
        let appKit = flip(axFrame, primaryScreenHeight: primaryScreenHeight)
        let center = CGPoint(x: appKit.midX, y: appKit.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
    }

    // MARK: - Native fullscreen (Space-taking) — never used as Maximize

    private static let fullScreenAttribute = "AXFullScreen" as CFString

    @MainActor
    private static func isNativeFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, fullScreenAttribute, &value) == .success
        else { return false }
        return (value as? Bool) == true
    }

    @MainActor
    @discardableResult
    private static func setNativeFullScreen(_ window: AXUIElement, _ enabled: Bool) -> Bool {
        let target: CFBoolean = enabled ? kCFBooleanTrue : kCFBooleanFalse
        return AXUIElementSetAttributeValue(window, fullScreenAttribute, target) == .success
    }
}
