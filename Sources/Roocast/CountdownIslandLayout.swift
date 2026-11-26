import CoreGraphics
import Foundation

/// Pure geometry for the countdown island (testable; AppKit panel consumes these frames).
///
/// Idle: compact centered digits. Hover/drag: × badge overlays the top-left corner
/// without reflowing the time label.
enum CountdownIslandLayout {
    /// Compact pill body (AC1) — smaller than the legacy 148×36 chrome.
    static let pillSize = CGSize(width: 100, height: 28)
    static let badgeDiameter: CGFloat = 18
    /// Half the badge sits outside the pill so the center hits the top-left corner.
    static var badgeOutset: CGFloat { badgeDiameter / 2 }

    static var chromeSize: CGSize {
        CGSize(
            width: pillSize.width + badgeOutset,
            height: pillSize.height + badgeOutset
        )
    }

    /// Pill sits inset from the left/top of chrome so the badge fits.
    nonisolated static func pillFrame(
        chromeSize: CGSize = chromeSize
    ) -> CGRect {
        CGRect(
            x: badgeOutset,
            y: 0,
            width: pillSize.width,
            height: pillSize.height
        )
    }

    /// Badge centered on the pill's top-left corner (AC3 overlay).
    nonisolated static func badgeFrame(pillFrame: CGRect) -> CGRect {
        CGRect(
            x: pillFrame.minX - badgeOutset,
            y: pillFrame.maxY - badgeOutset,
            width: badgeDiameter,
            height: badgeDiameter
        )
    }

    /// Time label centered in the pill (AC2); independent of badge visibility (AC3).
    nonisolated static func timeLabelFrame(in pill: CGRect, textSize: CGSize) -> CGRect {
        CGRect(
            x: pill.midX - textSize.width / 2,
            y: pill.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
    }

    /// Rough monospace estimate for tests / initial layout (panel still uses real fonts).
    nonisolated static func estimatedTextSize(for text: String) -> CGSize {
        // ~8.2 pt per digit at 13pt monospaced semibold; colon similar.
        let width = CGFloat(text.count) * 8.2
        return CGSize(width: max(width, 36), height: 16)
    }

    /// Default under-notch placement (AC5).
    nonisolated static func defaultOrigin(
        visibleFrame: CGRect,
        chromeSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: visibleFrame.midX - chromeSize.width / 2,
            y: visibleFrame.maxY - chromeSize.height - 10
        )
    }
}

/// Grab-offset window dragging (AC4) — origin = cursor + offset, constant for a gesture.
enum CountdownIslandDrag {
    nonisolated static func grabOffset(pillOrigin: CGPoint, cursor: CGPoint) -> CGPoint {
        CGPoint(x: pillOrigin.x - cursor.x, y: pillOrigin.y - cursor.y)
    }

    nonisolated static func origin(cursor: CGPoint, grabOffset: CGPoint) -> CGPoint {
        CGPoint(x: cursor.x + grabOffset.x, y: cursor.y + grabOffset.y)
    }
}
