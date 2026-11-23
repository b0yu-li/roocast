import XCTest
@testable import Roocast

final class CountdownTests: XCTestCase {

    func testParseTimerMinutes() {
        let spec = Countdown.parse("timer 5m")
        XCTAssertEqual(spec?.seconds, 300)
        XCTAssertEqual(spec?.display, "5:00")
    }

    func testParseCountdownSeconds() {
        let spec = Countdown.parse("countdown 90s")
        XCTAssertEqual(spec?.seconds, 90)
        XCTAssertEqual(spec?.display, "1:30")
    }

    func testParseCombinedHoursMinutes() {
        let spec = Countdown.parse("timer 1h30m")
        XCTAssertEqual(spec?.seconds, 5400)
        XCTAssertEqual(spec?.display, "1:30:00")
    }

    func testParseBareIntegerAsMinutes() {
        let spec = Countdown.parse("countdown 25")
        XCTAssertEqual(spec?.seconds, 25 * 60)
        XCTAssertEqual(spec?.display, "25:00")
    }

    func testParseCaseInsensitiveVerb() {
        XCTAssertEqual(Countdown.parse("Timer 10s")?.seconds, 10)
        XCTAssertEqual(Countdown.parse("COUNTDOWN 1m")?.seconds, 60)
    }

    func testParseRejectsMissingDuration() {
        XCTAssertNil(Countdown.parse("timer"))
        XCTAssertNil(Countdown.parse("countdown"))
        XCTAssertNil(Countdown.parse("timer "))
    }

    func testParseRejectsUnparsable() {
        XCTAssertNil(Countdown.parse("timer xyz"))
        XCTAssertNil(Countdown.parse("timer 0"))
        XCTAssertNil(Countdown.parse("timer 0m"))
        XCTAssertNil(Countdown.parse("timer 1h30"))
        XCTAssertNil(Countdown.parse("notes"))
        XCTAssertNil(Countdown.parse(""))
    }

    func testParseDurationUnits() {
        XCTAssertEqual(Countdown.parseDuration("45s"), 45)
        XCTAssertEqual(Countdown.parseDuration("2m"), 120)
        XCTAssertEqual(Countdown.parseDuration("1h"), 3600)
        XCTAssertEqual(Countdown.parseDuration("2h15m30s"), 2 * 3600 + 15 * 60 + 30)
        XCTAssertEqual(Countdown.parseDuration("10"), 600)
    }

    func testFormat() {
        XCTAssertEqual(Countdown.format(seconds: 5), "0:05")
        XCTAssertEqual(Countdown.format(seconds: 65), "1:05")
        XCTAssertEqual(Countdown.format(seconds: 3661), "1:01:01")
    }

    func testResultsPutsCountdownLeadRow() {
        let results = AppSearch.results(
            query: "timer 5m",
            apps: [AppItem.stub(name: "Notes")],
            folders: []
        )
        guard case .countdown(let seconds) = results.first?.kind else {
            return XCTFail("expected countdown lead row")
        }
        XCTAssertEqual(seconds, 300)
        XCTAssertEqual(results.first?.name, "5:00")
    }

    func testResultsCountdownDoesNotFireForPlainQuery() {
        let results = AppSearch.results(
            query: "timer",
            apps: [],
            folders: []
        )
        XCTAssertFalse(results.contains {
            if case .countdown = $0.kind { return true }
            return false
        })
    }
}
