import XCTest
@testable import Roocast

final class WindowSnapTests: XCTestCase {

    func testHalfFrameSplitsEvenWidth() {
        let visible = CGRect(x: 100, y: 50, width: 800, height: 600)
        let left = WindowSnap.halfFrame(of: visible, side: .left)
        let right = WindowSnap.halfFrame(of: visible, side: .right)

        XCTAssertEqual(left, CGRect(x: 100, y: 50, width: 400, height: 600))
        XCTAssertEqual(right, CGRect(x: 500, y: 50, width: 400, height: 600))
        XCTAssertEqual(left.maxX, right.minX)
        XCTAssertEqual(left.width + right.width, visible.width)
    }

    func testHalfFrameOddPixelGoesRight() {
        let visible = CGRect(x: 0, y: 0, width: 1001, height: 500)
        let left = WindowSnap.halfFrame(of: visible, side: .left)
        let right = WindowSnap.halfFrame(of: visible, side: .right)

        XCTAssertEqual(left.width, 500)
        XCTAssertEqual(right.width, 501)
        XCTAssertEqual(left.width + right.width, visible.width)
        XCTAssertEqual(left.maxX, right.minX)
    }

    func testFlipConvertsAppKitBottomLeftToAX() {
        // AppKit frame sitting on the bottom of a 1000pt-tall primary display.
        let frame = CGRect(x: 10, y: 100, width: 200, height: 300)
        let ax = WindowSnap.flip(frame, primaryScreenHeight: 1000)
        // Top of window in AX = primaryHeight - maxY = 1000 - 400 = 600
        XCTAssertEqual(ax, CGRect(x: 10, y: 600, width: 200, height: 300))
        XCTAssertEqual(WindowSnap.flip(ax, primaryScreenHeight: 1000), frame)
    }

    func testHalfFrameOnFlippedVisibleMatchesAXLeftEdge() {
        // AppKit visible frame with menu bar / dock insets, flipped like Tinycast.
        let appKitVisible = CGRect(x: 0, y: 40, width: 1440, height: 860)
        let axVisible = WindowSnap.flip(appKitVisible, primaryScreenHeight: 900)
        let left = WindowSnap.halfFrame(of: axVisible, side: .left)
        let right = WindowSnap.halfFrame(of: axVisible, side: .right)

        XCTAssertEqual(left.minX, axVisible.minX)
        XCTAssertEqual(right.maxX, axVisible.maxX)
        XCTAssertEqual(left.width + right.width, axVisible.width)
        XCTAssertEqual(left.height, axVisible.height)
    }

    func testTargetFrameMaximizeFillsVisible() {
        let visible = CGRect(x: 0, y: 40, width: 1440, height: 860)
        XCTAssertEqual(
            WindowSnap.targetFrame(of: visible, command: .maximize),
            visible
        )
        XCTAssertEqual(
            WindowSnap.targetFrame(of: visible, command: .left),
            WindowSnap.halfFrame(of: visible, side: .left)
        )
    }

    func testReasonableSizeIsSixtyPercentCenteredCapped() {
        // Typical laptop visible frame — 60% fits under the 1025×900 cap.
        let visible = CGRect(x: 0, y: 40, width: 1440, height: 860)
        let frame = WindowSnap.reasonableSizeFrame(of: visible)

        XCTAssertEqual(frame.width, (1440 * 0.6).rounded())
        XCTAssertEqual(frame.height, (860 * 0.6).rounded())
        XCTAssertEqual(frame.midX, visible.midX, accuracy: 0.5)
        XCTAssertEqual(frame.midY, visible.midY, accuracy: 0.5)
        XCTAssertEqual(
            WindowSnap.targetFrame(of: visible, command: .reasonableSize),
            frame
        )
    }

    func testReasonableSizeCapsOnLargeDisplay() {
        // 5K-ish canvas: 60% would exceed Tinycast's 1025×900 ceiling.
        let visible = CGRect(x: 0, y: 0, width: 5120, height: 2880)
        let frame = WindowSnap.reasonableSizeFrame(of: visible)

        XCTAssertEqual(frame.width, 1025)
        XCTAssertEqual(frame.height, 900)
        XCTAssertEqual(frame.midX, visible.midX, accuracy: 0.5)
        XCTAssertEqual(frame.midY, visible.midY, accuracy: 0.5)
    }

    func testWindowSnapCommandItems() {
        XCTAssertEqual(AppItem.leftHalf.kind, .leftHalf)
        XCTAssertEqual(AppItem.leftHalf.name, "Left Half")
        XCTAssertEqual(AppItem.rightHalf.kind, .rightHalf)
        XCTAssertEqual(AppItem.rightHalf.name, "Right Half")
        XCTAssertEqual(AppItem.maximize.kind, .maximize)
        XCTAssertEqual(AppItem.maximize.name, "Maximize")
        XCTAssertTrue(AppItem.maximize.aliases.contains("max"))
        XCTAssertEqual(AppItem.reasonableSize.kind, .reasonableSize)
        XCTAssertEqual(AppItem.reasonableSize.name, "Reasonable Size")
        XCTAssertTrue(AppItem.reasonableSize.aliases.contains("rs"))
    }
}
