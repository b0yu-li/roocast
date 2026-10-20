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
}
