import XCTest
@testable import Roocast

final class PanelFocusPolicyTests: XCTestCase {

    func testNonactivatingRequiresHidesOnDeactivateFalse() {
        // Invisible-but-key bug: nonactivating + hidesOnDeactivate=true never composites.
        XCTAssertTrue(PanelFocusPolicy.usesNonactivatingStyle)
        XCTAssertFalse(PanelFocusPolicy.hidesOnDeactivate)
    }

    func testShouldRestoreFocusOnlyWhenRequestedAndStolen() {
        XCTAssertTrue(
            PanelFocusPolicy.shouldRestoreFocus(restoreRequested: true, didStealActivation: true)
        )
        XCTAssertFalse(
            PanelFocusPolicy.shouldRestoreFocus(restoreRequested: true, didStealActivation: false)
        )
        XCTAssertFalse(
            PanelFocusPolicy.shouldRestoreFocus(restoreRequested: false, didStealActivation: true)
        )
        XCTAssertFalse(
            PanelFocusPolicy.shouldRestoreFocus(restoreRequested: false, didStealActivation: false)
        )
    }

    func testShouldFallbackActivateWhenNotKey() {
        XCTAssertTrue(PanelFocusPolicy.shouldFallbackActivate(isKeyWindow: false))
        XCTAssertFalse(PanelFocusPolicy.shouldFallbackActivate(isKeyWindow: true))
    }

    func testCGEventPointFlipsYAgainstPrimaryHeight() {
        let ax = CGPoint(x: 100, y: 200)
        let cg = PanelFocusPolicy.cgEventPoint(fromAX: ax, primaryScreenHeight: 1000)
        XCTAssertEqual(cg.x, 100)
        XCTAssertEqual(cg.y, 800)
    }

    func testShouldClickOnRestoreAttemptsOneAndThree() {
        XCTAssertFalse(PanelFocusPolicy.shouldClickOnRestoreAttempt(0))
        XCTAssertTrue(PanelFocusPolicy.shouldClickOnRestoreAttempt(1))
        XCTAssertFalse(PanelFocusPolicy.shouldClickOnRestoreAttempt(2))
        XCTAssertTrue(PanelFocusPolicy.shouldClickOnRestoreAttempt(3))
        XCTAssertFalse(PanelFocusPolicy.shouldClickOnRestoreAttempt(4))
    }

    func testRestoreDelayGrowsWithAttempt() {
        let d0 = PanelFocusPolicy.restoreDelaySeconds(forAttempt: 0)
        let d1 = PanelFocusPolicy.restoreDelaySeconds(forAttempt: 1)
        XCTAssertEqual(d0, 0.05, accuracy: 0.0001)
        XCTAssertEqual(d1, 0.10, accuracy: 0.0001)
        XCTAssertGreaterThan(d1, d0)
    }

    func testMaxRestoreAttemptIsPositive() {
        XCTAssertGreaterThan(PanelFocusPolicy.maxRestoreAttempt, 0)
    }
}
