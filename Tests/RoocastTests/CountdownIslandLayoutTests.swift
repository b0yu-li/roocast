import XCTest
@testable import Roocast

/// ACs for the countdown island chrome (compact + centered + overlay × + drag).
final class CountdownIslandLayoutTests: XCTestCase {

    // MARK: AC1 — Compact idle pill

    func testPillIsCompactVersusLegacy148x36() {
        XCTAssertLessThan(CountdownIslandLayout.pillSize.width, 120)
        XCTAssertLessThan(CountdownIslandLayout.pillSize.height, 34)
        XCTAssertGreaterThanOrEqual(CountdownIslandLayout.pillSize.width, 90)
        XCTAssertGreaterThanOrEqual(CountdownIslandLayout.pillSize.height, 26)
    }

    // MARK: AC2 — Digits horizontally centered in pill (idle)

    func testTimeLabelCenteredInPill() {
        let pill = CountdownIslandLayout.pillFrame()
        for text in ["0:05", "9:59", "49:24", "59:59", "1:00:00"] as [String] {
            // Approximate monospace digit width used by layout helper.
            let textSize = CountdownIslandLayout.estimatedTextSize(for: text)
            let frame = CountdownIslandLayout.timeLabelFrame(in: pill, textSize: textSize)
            let pillMidX = pill.midX
            let textMidX = frame.midX
            XCTAssertEqual(
                textMidX, pillMidX, accuracy: 1,
                "expected \(text) centered in pill (pillMid=\(pillMidX) textMid=\(textMidX))"
            )
            XCTAssertEqual(frame.midY, pill.midY, accuracy: 1)
        }
    }

    // MARK: AC3 — Overlay × on top-left; digits do not reflow

    func testBadgeOverlapsTopLeftCornerOfPill() {
        let pill = CountdownIslandLayout.pillFrame()
        let badge = CountdownIslandLayout.badgeFrame(pillFrame: pill)
        // Badge center sits on the pill's top-left corner.
        XCTAssertEqual(badge.midX, pill.minX, accuracy: 1)
        XCTAssertEqual(badge.midY, pill.maxY, accuracy: 1)
        // Protrudes outside the pill (overlay, not an inset trailing slot).
        XCTAssertLessThan(badge.minX, pill.minX)
        XCTAssertGreaterThan(badge.maxY, pill.maxY)
    }

    func testTimeLabelFrameIndependentOfBadgeVisibility() {
        let pill = CountdownIslandLayout.pillFrame()
        let textSize = CountdownIslandLayout.estimatedTextSize(for: "49:24")
        let idle = CountdownIslandLayout.timeLabelFrame(in: pill, textSize: textSize)
        let hovering = CountdownIslandLayout.timeLabelFrame(in: pill, textSize: textSize)
        XCTAssertEqual(idle, hovering)
    }

    func testChromeContainsPillAndBadge() {
        let chrome = CountdownIslandLayout.chromeSize
        let pill = CountdownIslandLayout.pillFrame()
        let badge = CountdownIslandLayout.badgeFrame(pillFrame: pill)
        let chromeRect = CGRect(origin: .zero, size: chrome)
        XCTAssertTrue(chromeRect.contains(pill))
        XCTAssertTrue(chromeRect.contains(badge))
    }

    // MARK: AC4 — Grab-offset drag (no drift)

    func testGrabOffsetKeepsCursorGluedAcrossMoves() {
        let startOrigin = CGPoint(x: 400, y: 700)
        let startCursor = CGPoint(x: 430, y: 715)
        let grab = CountdownIslandDrag.grabOffset(pillOrigin: startOrigin, cursor: startCursor)
        XCTAssertEqual(
            CountdownIslandDrag.origin(cursor: startCursor, grabOffset: grab),
            startOrigin
        )

        let path: [CGPoint] = [
            CGPoint(x: 500, y: 800),
            CGPoint(x: 520.5, y: 760.25),
            CGPoint(x: 100, y: 900),
            CGPoint(x: 430, y: 715),
        ]
        for cursor in path {
            let origin = CountdownIslandDrag.origin(cursor: cursor, grabOffset: grab)
            let glued = CGPoint(x: origin.x - cursor.x, y: origin.y - cursor.y)
            XCTAssertEqual(glued.x, grab.x, accuracy: 0.001)
            XCTAssertEqual(glued.y, grab.y, accuracy: 0.001)
        }
    }

    // MARK: AC5 — Default notch placement helper

    func testDefaultPositionCentersUnderMenuBarBand() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let chrome = CountdownIslandLayout.chromeSize
        let origin = CountdownIslandLayout.defaultOrigin(
            visibleFrame: visible,
            chromeSize: chrome
        )
        XCTAssertEqual(origin.x + chrome.width / 2, visible.midX, accuracy: 1)
        XCTAssertEqual(origin.y, visible.maxY - chrome.height - 10, accuracy: 1)
    }
}
