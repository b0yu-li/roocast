import XCTest
@testable import Roocast

final class TextExpanderTests: XCTestCase {
    func testFormattedTimeUsesLocalDateTimePattern() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)! // UTC+8
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 21
        components.hour = 13
        components.minute = 50
        let date = calendar.date(from: components)!

        XCTAssertEqual(
            TextExpanderSnippets.formattedTime(date, calendar: calendar),
            "2026-10-21 13:50"
        )
    }

    func testExpansionForTimeKeyword() {
        XCTAssertNotNil(TextExpanderSnippets.expansion(forKeyword: "$time"))
        XCTAssertNotNil(TextExpanderSnippets.expansion(forKeyword: "$TIME"))
        XCTAssertNil(TextExpanderSnippets.expansion(forKeyword: "$date"))
    }

    func testPolicyMatchesTimeSuffix() {
        var policy = TextExpanderPolicy(now: { Date(timeIntervalSince1970: 1_761_000_000) })
        XCTAssertNil(policy.process(.text("$")))
        XCTAssertNil(policy.process(.text("t")))
        XCTAssertNil(policy.process(.text("i")))
        XCTAssertNil(policy.process(.text("m")))
        let match = policy.process(.text("e"))
        XCTAssertEqual(match?.keyword, "$time")
        XCTAssertEqual(match?.deletionCount, 5)
        XCTAssertEqual(match?.expansion.count, "2026-10-21 13:50".count)
        XCTAssertTrue(match?.expansion.contains(" ") == true)
        XCTAssertTrue(match?.expansion.contains(":") == true)
    }

    func testPolicyIsCaseInsensitive() {
        var policy = TextExpanderPolicy()
        for ch in ["$", "T", "I", "M"] {
            XCTAssertNil(policy.process(.text(ch)))
        }
        XCTAssertNotNil(policy.process(.text("E")))
    }

    func testPolicyDeleteBackwardAndReset() {
        var policy = TextExpanderPolicy()
        _ = policy.process(.text("$"))
        _ = policy.process(.text("t"))
        _ = policy.process(.deleteBackward)
        _ = policy.process(.text("t"))
        _ = policy.process(.text("i"))
        _ = policy.process(.text("m"))
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
