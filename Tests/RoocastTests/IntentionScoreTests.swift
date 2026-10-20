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
}
