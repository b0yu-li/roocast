import XCTest
@testable import Roocast

final class NavigationStateTests: XCTestCase {

    func testMoveDownRespectsMaxIndex() {
        let nav = NavigationState()
        nav.maxIndex = 2
        nav.selectedIndex = 0

        nav.moveDown()
        XCTAssertEqual(nav.selectedIndex, 1)
        nav.moveDown()
        XCTAssertEqual(nav.selectedIndex, 2)
        nav.moveDown()
        XCTAssertEqual(nav.selectedIndex, 2)
    }

    func testMoveUpRespectsZero() {
        let nav = NavigationState()
        nav.maxIndex = 3
        nav.selectedIndex = 1

        nav.moveUp()
        XCTAssertEqual(nav.selectedIndex, 0)
        nav.moveUp()
        XCTAssertEqual(nav.selectedIndex, 0)
    }

    func testResetReturnsToZero() {
        let nav = NavigationState()
        nav.maxIndex = 5
        nav.selectedIndex = 4
        nav.reset()
        XCTAssertEqual(nav.selectedIndex, 0)
    }

    /// Empty-summon bug: list can render while maxIndex is still 0 (index not synced yet).
    func testMoveDownStuckWhenMaxIndexZero() {
        let nav = NavigationState()
        nav.maxIndex = 0
        nav.selectedIndex = 0
        nav.moveDown()
        XCTAssertEqual(nav.selectedIndex, 0)
    }

    func testUpdateBoundsClampsSelectedIndex() {
        let nav = NavigationState()
        nav.selectedIndex = 5
        nav.updateBounds(itemCount: 3)
        XCTAssertEqual(nav.maxIndex, 2)
        XCTAssertEqual(nav.selectedIndex, 2)
    }

    func testUpdateBoundsEmptyList() {
        let nav = NavigationState()
        nav.selectedIndex = 2
        nav.updateBounds(itemCount: 0)
        XCTAssertEqual(nav.maxIndex, 0)
        XCTAssertEqual(nav.selectedIndex, 0)
    }

    func testSyncResetsAndAppliesBounds() {
        let nav = NavigationState()
        nav.selectedIndex = 4
        nav.sync(itemCount: 10)
        XCTAssertEqual(nav.selectedIndex, 0)
        XCTAssertEqual(nav.maxIndex, 9)
    }
}
