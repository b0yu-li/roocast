import CoreGraphics
import Foundation

/// Pure rules for the nonactivating launcher panel and fallback AX restore.
///
/// Happy path: `.nonactivatingPanel` + `hidesOnDeactivate = false` so Ghostty
/// keeps tab first-responder. AX restore runs only if we had to steal activation.
enum PanelFocusPolicy {
    /// Must stay false with `.nonactivatingPanel` or the panel never composites
    /// while another app remains frontmost (invisible but still key).
    static let hidesOnDeactivate = false

    /// Prefer a nonactivating style mask so show() need not call `NSApp.activate`.
    static let usesNonactivatingStyle = true

    /// Escape / hotkey restore only if this show cycle stole activation.
    nonisolated static func shouldRestoreFocus(
        restoreRequested: Bool,
        didStealActivation: Bool
    ) -> Bool {
        restoreRequested && didStealActivation
    }

    /// Happy path is `orderFrontRegardless` + `makeKey`. Activate only when that failed.
    nonisolated static func shouldFallbackActivate(isKeyWindow: Bool) -> Bool {
        !isKeyWindow
    }

    /// AX positions use top-left origin; CGEvent uses bottom-left on the primary display.
    nonisolated static func cgEventPoint(
        fromAX point: CGPoint,
        primaryScreenHeight: CGFloat
    ) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// Metal terminals often ignore AX `focused=true`; click on attempts 1 and 3.
    nonisolated static func shouldClickOnRestoreAttempt(_ attempt: Int) -> Bool {
        attempt == 1 || attempt == 3
    }

    nonisolated static func restoreDelaySeconds(forAttempt attempt: Int) -> TimeInterval {
        0.05 * Double(attempt + 1)
    }

    /// Inclusive max attempt index passed to `FocusRestorer.restore` (0...max).
    nonisolated static let maxRestoreAttempt = 4
}
