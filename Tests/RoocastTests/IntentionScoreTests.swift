import XCTest
@testable import Roocast

final class IntentionScoreTests: XCTestCase {

    func testPrefersPrefixOverSubstring() {
        // Typing "no" should intend Notes, not Keynote (mid-string "no").
        let notes = IntentionScore.score(query: "no", name: "Notes", searchText: "Notes")
        let keynote = IntentionScore.score(query: "no", name: "Keynote", searchText: "Keynote")
        XCTAssertGreaterThan(notes, keynote)
        XCTAssertGreaterThan(notes, 0)
        XCTAssertGreaterThan(keynote, 0)
    }

    func testExactBeatsPrefix() {
        let exact = IntentionScore.score(query: "notes", name: "Notes", searchText: "Notes")
        let prefix = IntentionScore.score(query: "no", name: "Notes", searchText: "Notes")
        XCTAssertGreaterThan(exact, prefix)
    }

    func testPrefersShorterPrefixMatch() {
        let notes = IntentionScore.score(query: "no", name: "Notes", searchText: "Notes")
        let notebook = IntentionScore.score(query: "no", name: "Notebook", searchText: "Notebook")
        XCTAssertGreaterThan(notes, notebook)
    }

    func testNoMatchIsZero() {
        XCTAssertEqual(IntentionScore.score(query: "xyz", name: "Notes", searchText: "Notes"), 0)
        XCTAssertEqual(IntentionScore.score(query: "", name: "Notes", searchText: "Notes"), 0)
    }

    func testProfileWordPrefix() {
        let work = IntentionScore.score(
            query: "wor",
            name: "Firefox",
            searchText: "Firefox work"
        )
        let personal = IntentionScore.score(
            query: "wor",
            name: "Firefox",
            searchText: "Firefox personal"
        )
        XCTAssertGreaterThan(work, 0)
        XCTAssertEqual(personal, 0)
    }

    func testScoreViaAppItem() {
        let notes = AppItem.stub(name: "Notes")
        let keynote = AppItem.stub(name: "Keynote")
        XCTAssertGreaterThan(
            IntentionScore.score(query: "no", app: notes),
            IntentionScore.score(query: "no", app: keynote)
        )
    }

    /// `"fi"` used to rank FindMy above Firefox purely because the name is one char shorter.
    func testRunningFirefoxBeatsIdleFindMyForFi() {
        let findMy = AppItem.stub(name: "FindMy", path: "/System/Applications/FindMy.app")
        let firefox = AppItem.stub(
            name: "Firefox",
            profile: "default-release",
            path: "/Applications/Firefox.app",
            isRunning: true
        )
        XCTAssertGreaterThan(
            IntentionScore.score(query: "fi", app: firefox),
            IntentionScore.score(query: "fi", app: findMy)
        )
    }

    func testRunningBoostDoesNotOverturnPrefixVsSubstring() {
        // Idle Notes (prefix) must still beat running Keynote (mid-string "no").
        let notes = AppItem.stub(name: "Notes", isRunning: false)
        let keynote = AppItem.stub(name: "Keynote", isRunning: true)
        XCTAssertGreaterThan(
            IntentionScore.score(query: "no", app: notes),
            IntentionScore.score(query: "no", app: keynote)
        )
    }

    func testSwitchScoreOnlyRunningApps() {
        let running = AppItem.stub(name: "Slack", path: "/Applications/Slack.app", isRunning: true)
        let idle = AppItem.stub(name: "Notes", path: "/Applications/Notes.app", isRunning: false)
        XCTAssertGreaterThan(IntentionScore.switchScore(app: running, frontmostPath: nil), 0)
        XCTAssertEqual(IntentionScore.switchScore(app: idle, frontmostPath: nil), 0)
    }

    func testSwitchScoreExcludesFrontmostRegularApp() {
        let path = "/Applications/Ghostty.app"
        let front = AppItem.stub(name: "Ghostty", path: path, isRunning: true)
        let other = AppItem.stub(name: "Slack", path: "/Applications/Slack.app", isRunning: true)
        XCTAssertEqual(IntentionScore.switchScore(app: front, frontmostPath: path), 0)
        XCTAssertGreaterThan(IntentionScore.switchScore(app: other, frontmostPath: path), 0)
    }

    func testSwitchScoreKeepsFirefoxProfilesWhenFirefoxFrontmost() {
        let firefoxPath = "/Applications/Firefox.app"
        let work = AppItem.stub(name: "Firefox", profile: "work", path: firefoxPath, isRunning: true)
        let personal = AppItem.stub(
            name: "Firefox",
            profile: "personal",
            path: firefoxPath,
            isRunning: true
        )
        XCTAssertGreaterThan(IntentionScore.switchScore(app: work, frontmostPath: firefoxPath), 0)
        XCTAssertGreaterThan(
            IntentionScore.switchScore(app: personal, frontmostPath: firefoxPath),
            0
        )
    }

    func testSwitchScoreExcludesSelfLauncher() {
        let selfPath = "/Applications/Roocast.app"
        let selfApp = AppItem.stub(name: "Roocast", path: selfPath, isRunning: true)
        let other = AppItem.stub(name: "Slack", path: "/Applications/Slack.app", isRunning: true)
        XCTAssertEqual(
            IntentionScore.switchScore(app: selfApp, frontmostPath: nil, selfPath: selfPath),
            0
        )
        XCTAssertGreaterThan(
            IntentionScore.switchScore(app: other, frontmostPath: nil, selfPath: selfPath),
            0
        )
    }
}
