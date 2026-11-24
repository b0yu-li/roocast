import XCTest
@testable import Roocast

final class CommandLockTests: XCTestCase {

    func testUniqueCompletionTimerPrefix() {
        XCTAssertEqual(CommandLock.uniqueCompletion(forToken: "t")?.verb, "timer")
        XCTAssertEqual(CommandLock.uniqueCompletion(forToken: "tim")?.verb, "timer")
        XCTAssertEqual(CommandLock.uniqueCompletion(forToken: "timer")?.verb, "timer")
        XCTAssertEqual(CommandLock.uniqueCompletion(forToken: "TIM")?.verb, "timer")
    }

    func testUniqueCompletionCountdown() {
        XCTAssertEqual(CommandLock.uniqueCompletion(forToken: "c")?.verb, "countdown")
        XCTAssertEqual(CommandLock.uniqueCompletion(forToken: "coun")?.verb, "countdown")
        XCTAssertEqual(CommandLock.uniqueCompletion(forToken: "countdown")?.verb, "countdown")
    }

    func testUniqueCompletionRejectsUnknown() {
        XCTAssertNil(CommandLock.uniqueCompletion(forToken: "z"))
        XCTAssertNil(CommandLock.uniqueCompletion(forToken: "max"))
        XCTAssertNil(CommandLock.uniqueCompletion(forToken: ""))
        XCTAssertNil(CommandLock.uniqueCompletion(forToken: "   "))
    }

    func testLockAttemptFromPrefix() {
        let locked = CommandLock.lockAttempt(from: "tim")
        XCTAssertEqual(locked?.verb, "timer")
        XCTAssertEqual(locked?.argument, "")
    }

    func testLockAttemptFromFullVerbWithArgs() {
        let locked = CommandLock.lockAttempt(from: "timer 2h")
        XCTAssertEqual(locked?.verb, "timer")
        XCTAssertEqual(locked?.argument, "2h")
    }

    func testLockAttemptCountdownArgs() {
        let locked = CommandLock.lockAttempt(from: "countdown 90s")
        XCTAssertEqual(locked?.verb, "countdown")
        XCTAssertEqual(locked?.argument, "90s")
    }

    func testLockAttemptRejectsNonCommand() {
        XCTAssertNil(CommandLock.lockAttempt(from: "notes"))
        XCTAssertNil(CommandLock.lockAttempt(from: "tim extra"))
        XCTAssertNil(CommandLock.lockAttempt(from: ""))
    }

    func testComposedQuery() {
        XCTAssertEqual(CommandLock.composedQuery(verb: "timer", argument: ""), "timer")
        XCTAssertEqual(CommandLock.composedQuery(verb: "timer", argument: " 2h "), "timer 2h")
    }

    func testComposedQueryParsesCountdown() {
        let q = CommandLock.composedQuery(verb: "timer", argument: "5m")
        XCTAssertEqual(Countdown.parse(q)?.seconds, 300)
    }
}
