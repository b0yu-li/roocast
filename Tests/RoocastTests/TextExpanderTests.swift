import XCTest
@testable import Roocast

final class TextExpanderTests: XCTestCase {
    func testFormattedDateUsesSortableLocalPattern() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)! // UTC+8
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 21
        components.hour = 11
        components.minute = 57
        let date = calendar.date(from: components)!

        XCTAssertEqual(
            TextExpanderSnippets.formattedDate(date, calendar: calendar),
            "2026-10-21-11-57"
        )
    }

    func testExpansionForDateKeyword() {
        XCTAssertNotNil(TextExpanderSnippets.expansion(forKeyword: "$date"))
        XCTAssertNotNil(TextExpanderSnippets.expansion(forKeyword: "$DATE"))
        XCTAssertNil(TextExpanderSnippets.expansion(forKeyword: "$time"))
    }

    func testPolicyMatchesDateSuffix() {
        var policy = TextExpanderPolicy(now: { Date(timeIntervalSince1970: 1_761_000_000) })
        XCTAssertNil(policy.process(.text("$")))
        XCTAssertNil(policy.process(.text("d")))
        XCTAssertNil(policy.process(.text("a")))
        XCTAssertNil(policy.process(.text("t")))
        let match = policy.process(.text("e"))
        XCTAssertEqual(match?.keyword, "$date")
        XCTAssertEqual(match?.deletionCount, 5)
        XCTAssertEqual(match?.expansion.count, "2026-10-21-11-57".count)
        XCTAssertTrue(match?.expansion.split(separator: "-").count == 5)
    }

    func testPolicyIsCaseInsensitive() {
        var policy = TextExpanderPolicy()
        for ch in ["$", "D", "A", "T"] {
            XCTAssertNil(policy.process(.text(ch)))
        }
        XCTAssertNotNil(policy.process(.text("E")))
    }

    func testPolicyDeleteBackwardAndReset() {
        var policy = TextExpanderPolicy()
        _ = policy.process(.text("$"))
        _ = policy.process(.text("d"))
        _ = policy.process(.deleteBackward)
        _ = policy.process(.text("d"))
        _ = policy.process(.text("a"))
        _ = policy.process(.text("t"))
        XCTAssertNil(policy.process(.reset))
        XCTAssertNil(policy.process(.text("e"))) // buffer was cleared
    }

    func testClassifyInputIgnoresSyntheticAndModifiers() {
        XCTAssertEqual(
            TextExpanderPolicy.classifyInput(
                text: "a",
                isSynthetic: true,
                secureEventInputEnabled: false,
                isFlagsChanged: false,
                isKeyDown: true,
                hasCommandOrControl: false,
                isResetKey: false,
                isDeleteBackward: false
            ),
            .ignored
        )
        XCTAssertEqual(
            TextExpanderPolicy.classifyInput(
                text: "a",
                isSynthetic: false,
                secureEventInputEnabled: false,
                isFlagsChanged: false,
                isKeyDown: true,
                hasCommandOrControl: true,
                isResetKey: false,
                isDeleteBackward: false
            ),
            .reset
        )
        XCTAssertEqual(
            TextExpanderPolicy.classifyInput(
                text: nil,
                isSynthetic: false,
                secureEventInputEnabled: false,
                isFlagsChanged: false,
                isKeyDown: true,
                hasCommandOrControl: false,
                isResetKey: false,
                isDeleteBackward: true
            ),
            .deleteBackward
        )
    }
}
