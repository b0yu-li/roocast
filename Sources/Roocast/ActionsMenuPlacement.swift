import CoreGraphics
import Foundation

/// Pure layout for the ⌘K actions menu overlay.
///
/// The overlay must fill the *live* results viewport. Deriving height from
/// `panel − headerConst − footer` disagreed with SwiftUI's measured header by
/// 1pt and reflowed the list on every open/close (the ⌘K twitch).
enum ActionsMenuPlacement {
    static let gap: CGFloat = 6
    static let margin: CGFloat = 8

    /// Overlay sizes to the parent results area — never a constant-derived frame.
    nonisolated static let sizesToLiveViewport = true

    /// Menu center inside `viewport`, preferring below the row; flips above when needed.
    nonisolated static func center(
        anchor: CGRect,
        menuWidth: CGFloat,
        menuHeight: CGFloat,
        viewport: CGSize
    ) -> CGPoint {
        let belowCenter = anchor.maxY + gap + menuHeight / 2
        let aboveCenter = anchor.minY - gap - menuHeight / 2
        let useBelow =
            belowCenter + menuHeight / 2 <= viewport.height
            || aboveCenter - menuHeight / 2 < 0
        let centerX = min(
            max(anchor.midX, menuWidth / 2 + margin),
            viewport.width - menuWidth / 2 - margin
        )
        let centerY = min(
            max(useBelow ? belowCenter : aboveCenter, menuHeight / 2 + margin),
            viewport.height - menuHeight / 2 - margin
        )
        return CGPoint(x: centerX, y: centerY)
    }
}
