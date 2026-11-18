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

    func testVerticalHalfFrameSplitsEvenHeight() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let top = WindowSnap.verticalHalfFrame(of: visible, side: .top)
        let bottom = WindowSnap.verticalHalfFrame(of: visible, side: .bottom)

        XCTAssertEqual(top, CGRect(x: 0, y: 0, width: 1440, height: 450))
        XCTAssertEqual(bottom, CGRect(x: 0, y: 450, width: 1440, height: 450))
        XCTAssertEqual(top.maxY, bottom.minY)
        XCTAssertEqual(top.height + bottom.height, visible.height)
    }

    func testVerticalHalfFrameOddPixelGoesBottom() {
        let visible = CGRect(x: 10, y: 20, width: 800, height: 501)
        let top = WindowSnap.verticalHalfFrame(of: visible, side: .top)
        let bottom = WindowSnap.verticalHalfFrame(of: visible, side: .bottom)

        XCTAssertEqual(top.height, 250)
        XCTAssertEqual(bottom.height, 251)
        XCTAssertEqual(top.height + bottom.height, visible.height)
        XCTAssertEqual(top.maxY, bottom.minY)
        XCTAssertEqual(top.width, visible.width)
        XCTAssertEqual(bottom.width, visible.width)
    }

    func testThirdFramesPartitionVisible() {
        // Tinycast reference display: evenly divisible by thirds.
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let first = WindowSnap.thirdFrame(of: visible, side: .firstThird)
        let lastTwo = WindowSnap.thirdFrame(of: visible, side: .lastTwoThirds)

        XCTAssertEqual(first, CGRect(x: 0, y: 0, width: 480, height: 900))
        XCTAssertEqual(lastTwo, CGRect(x: 480, y: 0, width: 960, height: 900))
        XCTAssertEqual(first.maxX, lastTwo.minX)
        XCTAssertEqual(first.union(lastTwo), visible)
        XCTAssertEqual(
            WindowSnap.targetFrame(of: visible, command: .firstThird),
            first
        )
        XCTAssertEqual(
            WindowSnap.targetFrame(of: visible, command: .lastTwoThirds),
            lastTwo
        )
    }

    func testThirdFramesShareEdgeOnOddWidth() {
        // Shared boundary must round identically so the columns still abut.
        for width in [1001, 1441, 1920] as [CGFloat] {
            let visible = CGRect(x: 0, y: 0, width: width, height: 900)
            let first = WindowSnap.thirdFrame(of: visible, side: .firstThird)
            let lastTwo = WindowSnap.thirdFrame(of: visible, side: .lastTwoThirds)
            XCTAssertEqual(first.maxX, lastTwo.minX, "width \(width)")
            XCTAssertEqual(first.union(lastTwo), visible, "width \(width)")
        }
    }

    func testMoveToTopAndBottomHoldX() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let current = CGRect(x: 200, y: 300, width: 400, height: 250)

        let top = WindowSnap.moveFrame(of: visible, current: current, command: .moveToTop)
        let bottom = WindowSnap.moveFrame(of: visible, current: current, command: .moveToBottom)

        XCTAssertEqual(top, CGRect(x: 200, y: 0, width: 400, height: 250))
        XCTAssertEqual(bottom, CGRect(x: 200, y: 650, width: 400, height: 250))
        XCTAssertEqual(top.width, current.width)
        XCTAssertEqual(top.height, current.height)
        XCTAssertEqual(top.minX, current.minX)
        XCTAssertEqual(bottom.minX, current.minX)
        XCTAssertFalse(WindowSnap.Command.moveToTop.resizes)
        XCTAssertEqual(
            WindowSnap.targetFrame(of: visible, command: .moveToTop, current: current),
            top
        )
    }

    func testMoveToLeftAndRightHoldY() {
        let visible = CGRect(x: 0, y: 40, width: 1440, height: 860)
        let current = CGRect(x: 500, y: 200, width: 320, height: 180)

        let left = WindowSnap.moveFrame(of: visible, current: current, command: .moveToLeft)
        let right = WindowSnap.moveFrame(of: visible, current: current, command: .moveToRight)

        XCTAssertEqual(left, CGRect(x: 0, y: 200, width: 320, height: 180))
        XCTAssertEqual(right, CGRect(x: 1120, y: 200, width: 320, height: 180))
        XCTAssertEqual(left.minY, current.minY)
        XCTAssertEqual(right.minY, current.minY)
        XCTAssertEqual(left.size, current.size)
        XCTAssertEqual(right.size, current.size)
    }

    func testMoveToClampsHeldAxisOntoVisible() {
        // Window partly off-display: flushing top must also pull X back in.
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let current = CGRect(x: -80, y: 400, width: 400, height: 250)
        let top = WindowSnap.moveFrame(of: visible, current: current, command: .moveToTop)

        XCTAssertEqual(top.minX, 0)
        XCTAssertEqual(top.minY, 0)
        XCTAssertEqual(top.size, current.size)
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
        XCTAssertEqual(AppItem.topHalf.kind, .topHalf)
        XCTAssertEqual(AppItem.topHalf.name, "Top Half")
        XCTAssertTrue(AppItem.topHalf.aliases.contains("th"))
        XCTAssertEqual(AppItem.bottomHalf.kind, .bottomHalf)
        XCTAssertEqual(AppItem.bottomHalf.name, "Bottom Half")
        XCTAssertTrue(AppItem.bottomHalf.aliases.contains("bh"))
        XCTAssertEqual(AppItem.firstThird.kind, .firstThird)
        XCTAssertEqual(AppItem.firstThird.name, "First Third")
        XCTAssertTrue(AppItem.firstThird.aliases.contains("ft"))
        XCTAssertEqual(AppItem.lastTwoThirds.kind, .lastTwoThirds)
        XCTAssertEqual(AppItem.lastTwoThirds.name, "Last Two Thirds")
        XCTAssertTrue(AppItem.lastTwoThirds.aliases.contains("ltt"))
        XCTAssertEqual(AppItem.moveToTop.kind, .moveToTop)
        XCTAssertEqual(AppItem.moveToTop.name, "Move to Top")
        XCTAssertTrue(AppItem.moveToTop.aliases.contains("mtt"))
        XCTAssertEqual(AppItem.moveToBottom.kind, .moveToBottom)
        XCTAssertEqual(AppItem.moveToBottom.name, "Move to Bottom")
        XCTAssertEqual(AppItem.moveToLeft.kind, .moveToLeft)
        XCTAssertEqual(AppItem.moveToLeft.name, "Move to Left")
        XCTAssertEqual(AppItem.moveToRight.kind, .moveToRight)
        XCTAssertEqual(AppItem.moveToRight.name, "Move to Right")
        XCTAssertEqual(AppItem.maximize.kind, .maximize)
        XCTAssertEqual(AppItem.maximize.name, "Maximize")
        XCTAssertTrue(AppItem.maximize.aliases.contains("max"))
        XCTAssertEqual(AppItem.reasonableSize.kind, .reasonableSize)
        XCTAssertEqual(AppItem.reasonableSize.name, "Reasonable Size")
        XCTAssertTrue(AppItem.reasonableSize.aliases.contains("rs"))
    }
}
