import XCTest
@testable import Roocast

final class FloatingPanelTests: XCTestCase {

    func testKeyCodesMatchCarbonVirtualKeys() {
        XCTAssertEqual(KeyCode.returnKey, 36)
        XCTAssertEqual(KeyCode.escape, 53)
        XCTAssertEqual(KeyCode.upArrow, 126)
        XCTAssertEqual(KeyCode.downArrow, 125)
    }

    func testHotKeyIDsAreDistinct() {
        XCTAssertEqual(HotKeyID.launcher.rawValue, 1)
        XCTAssertEqual(HotKeyID.clipboard.rawValue, 2)
        XCTAssertNotEqual(HotKeyID.launcher, HotKeyID.clipboard)
    }

    func testClipboardLayoutIsCompact() {
        XCTAssertEqual(ClipboardLayout.width, 560)
        XCTAssertEqual(ClipboardLayout.height, 360)
        XCTAssertGreaterThan(ClipboardLayout.cornerRadius, 0)
    }

    func testLauncherAndClipboardLayoutsDiffer() {
        // Panels share FloatingPanel chrome but keep distinct sizes.
        XCTAssertNotEqual(LauncherLayout.width, ClipboardLayout.width)
        XCTAssertNotEqual(LauncherLayout.height, ClipboardLayout.height)
    }
}
