import XCTest
@testable import Roocast

final class AppSearchTests: XCTestCase {

    func testMatchesQuitCommandPrefixes() {
        XCTAssertTrue(AppSearch.matchesQuitCommand("q"))
        XCTAssertTrue(AppSearch.matchesQuitCommand("qui"))
        XCTAssertTrue(AppSearch.matchesQuitCommand("quit"))
        XCTAssertTrue(AppSearch.matchesQuitCommand("Quit"))
        XCTAssertTrue(AppSearch.matchesQuitCommand("quit roo"))
        XCTAssertFalse(AppSearch.matchesQuitCommand(""))
        XCTAssertFalse(AppSearch.matchesQuitCommand("safari"))
        XCTAssertFalse(AppSearch.matchesQuitCommand("quite"))
    }

    func testResultsPutsQuitFirst() {
        let apps = [
            AppItem.stub(name: "Notes"),
            AppItem.stub(name: "Quitter"),
        ]
        let results = AppSearch.results(query: "qui", apps: apps)
        XCTAssertEqual(results.first?.kind, .quit)
        XCTAssertTrue(results.contains { $0.name == "Quitter" })
    }

    func testResultsEmptyQueryIsEmpty() {
        XCTAssertTrue(AppSearch.results(query: "", apps: [AppItem.stub(name: "Notes")]).isEmpty)
        XCTAssertTrue(AppSearch.results(query: "   ", apps: [AppItem.stub(name: "Notes")]).isEmpty)
    }

    func testRankPrefersNotesOverKeynoteForNo() {
        let apps = [
            AppItem.stub(name: "Keynote"),
            AppItem.stub(name: "Notes"),
        ]
        let ranked = AppSearch.rank(query: "no", apps: apps)
        XCTAssertEqual(ranked.first?.name, "Notes")
        XCTAssertEqual(ranked.map(\.name), ["Notes", "Keynote"])
    }

    func testRankFiltersByProfileName() {
        let apps = [
            AppItem.stub(name: "Firefox", profile: "work"),
            AppItem.stub(name: "Firefox", profile: "personal"),
            AppItem.stub(name: "Safari"),
        ]
        let work = AppSearch.rank(query: "work", apps: apps)
        XCTAssertEqual(work.map(\.profile), ["work"])

        let firefox = AppSearch.rank(query: "firefox", apps: apps)
        XCTAssertEqual(firefox.count, 2)
        XCTAssertTrue(firefox.allSatisfy { $0.name == "Firefox" })
    }

    func testRankNameTieBreaksAlphabetically() {
        let apps = [
            AppItem.stub(name: "Notes"),
            AppItem.stub(name: "Notion"),
        ]
        // Both are exact-ish prefix for "no" with same length? Notes=5, Notion=6 → Notes wins by score.
        // Use equal-length names with same score via exact match on searchText — use identical scores
        // by matching mid-string at same position... simpler: query that matches both as prefixes
        // with same name length is hard. Instead verify stable sort for equal intention via
        // substring at different apps with forced equal path — "ab" against "Xab" and "Yab":
        let tied = [
            AppItem.stub(name: "Yab"),
            AppItem.stub(name: "Xab"),
        ]
        let ranked = AppSearch.rank(query: "ab", apps: tied)
        XCTAssertEqual(ranked.map(\.name), ["Xab", "Yab"])
    }

    func testResultsIncludesFolderForDownloadsPrefix() {
        let folders = [
            AppItem.folderStub(name: "Downloads", aliases: ["dl"]),
        ]
        let results = AppSearch.results(
            query: "dow",
            apps: [AppItem.stub(name: "Safari")],
            folders: folders
        )
        XCTAssertEqual(results.first?.kind, .folder)
        XCTAssertEqual(results.first?.name, "Downloads")
    }

    func testResultsMatchesFolderAlias() {
        let folders = [
            AppItem.folderStub(name: "Downloads", aliases: ["dl"]),
        ]
        let results = AppSearch.results(
            query: "dl",
            apps: [AppItem.stub(name: "Safari")],
            folders: folders
        )
        XCTAssertTrue(results.contains { $0.kind == .folder && $0.name == "Downloads" })
    }

    func testResultsRanksFolderAboveWeakAppMatch() {
        let folders = [
            AppItem.folderStub(name: "Downloads", aliases: ["dl"]),
        ]
        let apps = [AppItem.stub(name: "Shadow")]
        let results = AppSearch.results(query: "dow", apps: apps, folders: folders)
        XCTAssertEqual(results.first?.name, "Downloads")
        XCTAssertEqual(results.first?.kind, .folder)
    }

    func testResultsEmptyQueryStillEmptyWithFolders() {
        let folders = [AppItem.folderStub(name: "Downloads")]
        XCTAssertTrue(
            AppSearch.results(query: "", apps: [AppItem.stub(name: "Notes")], folders: folders).isEmpty
        )
    }
}
