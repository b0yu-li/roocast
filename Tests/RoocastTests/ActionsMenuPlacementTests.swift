import XCTest
@testable import Roocast

final class ActionsMenuPlacementTests: XCTestCase {

    // MARK: - AC1: overlay must not use constant-derived viewport height

    func testOverlaySizesToLiveViewport() {
        // Fixed const height (panel − headerConst − footer) caused the 1pt twitch.
        XCTAssertTrue(ActionsMenuPlacement.sizesToLiveViewport)
    }

    // MARK: - Placement: prefer below, flip above, clamp edges

    func testCentersBelowAnchorWhenSpaceAllows() {
        let anchor = CGRect(x: 100, y: 40, width: 200, height: 36)
        let point = ActionsMenuPlacement.center(
            anchor: anchor,
            menuWidth: 260,
            menuHeight: 108,
            viewport: CGSize(width: 640, height: 351)
        )
        let expectedY = anchor.maxY + ActionsMenuPlacement.gap + 108 / 2
        XCTAssertEqual(point.y, expectedY, accuracy: 0.001)
        XCTAssertEqual(point.x, anchor.midX, accuracy: 0.001)
    }

    func testFlipsAboveWhenBelowWouldOverflow() {
        let anchor = CGRect(x: 100, y: 280, width: 200, height: 36)
        let menuHeight: CGFloat = 108
        let viewport = CGSize(width: 640, height: 351)
        let point = ActionsMenuPlacement.center(
            anchor: anchor,
            menuWidth: 260,
            menuHeight: menuHeight,
            viewport: viewport
        )
        let expectedY = anchor.minY - ActionsMenuPlacement.gap - menuHeight / 2
        XCTAssertEqual(point.y, expectedY, accuracy: 0.001)
    }

    func testClampsHorizontallyInsideViewport() {
        let anchor = CGRect(x: 0, y: 40, width: 40, height: 36)
        let point = ActionsMenuPlacement.center(
            anchor: anchor,
            menuWidth: 260,
            menuHeight: 108,
            viewport: CGSize(width: 640, height: 351)
        )
        XCTAssertEqual(
            point.x,
            260 / 2 + ActionsMenuPlacement.margin,
            accuracy: 0.001
        )
    }

    func testUsesLiveViewportHeightNotAssumedConstant() {
        // Same anchor; a 1pt shorter live viewport must change vertical clamp.
        let anchor = CGRect(x: 100, y: 10, width: 200, height: 36)
        let tall = ActionsMenuPlacement.center(
            anchor: anchor,
            menuWidth: 260,
            menuHeight: 300,
            viewport: CGSize(width: 640, height: 352)
        )
        let short = ActionsMenuPlacement.center(
            anchor: anchor,
            menuWidth: 260,
            menuHeight: 300,
            viewport: CGSize(width: 640, height: 351)
        )
        XCTAssertNotEqual(tall.y, short.y)
        XCTAssertEqual(short.y, 351 - 300 / 2 - ActionsMenuPlacement.margin, accuracy: 0.001)
    }
}
