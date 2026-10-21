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

    func testMatchesLeftHalfCommand() {
        XCTAssertTrue(AppSearch.matchesLeftHalfCommand("l"))
        XCTAssertTrue(AppSearch.matchesLeftHalfCommand("left"))
        XCTAssertTrue(AppSearch.matchesLeftHalfCommand("left h"))
        XCTAssertTrue(AppSearch.matchesLeftHalfCommand("left half"))
        XCTAssertTrue(AppSearch.matchesLeftHalfCommand("lh"))
        XCTAssertFalse(AppSearch.matchesLeftHalfCommand(""))
        XCTAssertFalse(AppSearch.matchesLeftHalfCommand("right"))
        XCTAssertFalse(AppSearch.matchesLeftHalfCommand("leftover"))
    }

    func testMatchesRightHalfCommand() {
        XCTAssertTrue(AppSearch.matchesRightHalfCommand("r"))
        XCTAssertTrue(AppSearch.matchesRightHalfCommand("right"))
        XCTAssertTrue(AppSearch.matchesRightHalfCommand("right half"))
        XCTAssertTrue(AppSearch.matchesRightHalfCommand("rh"))
        XCTAssertFalse(AppSearch.matchesRightHalfCommand("left"))
        XCTAssertFalse(AppSearch.matchesRightHalfCommand("rightly"))
    }

    func testMatchesMaximizeCommand() {
        XCTAssertTrue(AppSearch.matchesMaximizeCommand("m"))
        XCTAssertTrue(AppSearch.matchesMaximizeCommand("ma"))
        XCTAssertTrue(AppSearch.matchesMaximizeCommand("max"))
        XCTAssertTrue(AppSearch.matchesMaximizeCommand("maximize"))
        XCTAssertFalse(AppSearch.matchesMaximizeCommand(""))
        XCTAssertFalse(AppSearch.matchesMaximizeCommand("maximum"))
        XCTAssertFalse(AppSearch.matchesMaximizeCommand("fullscreen"))
    }

    func testMatchesReasonableSizeCommand() {
        XCTAssertTrue(AppSearch.matchesReasonableSizeCommand("re"))
        XCTAssertTrue(AppSearch.matchesReasonableSizeCommand("reasonable"))
        XCTAssertTrue(AppSearch.matchesReasonableSizeCommand("reasonable s"))
        XCTAssertTrue(AppSearch.matchesReasonableSizeCommand("reasonable size"))
        XCTAssertTrue(AppSearch.matchesReasonableSizeCommand("rs"))
        XCTAssertTrue(AppSearch.matchesReasonableSizeCommand("reason"))
        XCTAssertFalse(AppSearch.matchesReasonableSizeCommand(""))
        XCTAssertFalse(AppSearch.matchesReasonableSizeCommand("rss"))
        XCTAssertFalse(AppSearch.matchesReasonableSizeCommand("right"))
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

    func testResultsPutsLeftHalfFirst() {
        let apps = [AppItem.stub(name: "Letters")]
        let results = AppSearch.results(query: "left", apps: apps)
        XCTAssertEqual(results.first?.kind, .leftHalf)
        XCTAssertFalse(results.contains { $0.kind == .rightHalf })
    }

    func testResultsPutsRightHalfFirst() {
        let results = AppSearch.results(query: "right half", apps: [])
        XCTAssertEqual(results.map(\.kind), [.rightHalf])
    }

    func testResultsAliasLhAndRh() {
        XCTAssertEqual(AppSearch.results(query: "lh", apps: []).first?.kind, .leftHalf)
        XCTAssertEqual(AppSearch.results(query: "rh", apps: []).first?.kind, .rightHalf)
    }

    func testResultsPutsMaximizeFirst() {
        let apps = [AppItem.stub(name: "Mail")]
        let results = AppSearch.results(query: "max", apps: apps)
        XCTAssertEqual(results.first?.kind, .maximize)
    }

    func testResultsPutsReasonableSizeFirst() {
        let apps = [AppItem.stub(name: "Notes")]
        let results = AppSearch.results(query: "reasonable", apps: apps)
        XCTAssertEqual(results.first?.kind, .reasonableSize)
        XCTAssertEqual(AppSearch.results(query: "rs", apps: []).first?.kind, .reasonableSize)
    }

    func testResultsEmptyQueryShowsRunningSwitchSuggestions() {
        let apps = [
            AppItem.stub(name: "Notes", path: "/Applications/Notes.app", isRunning: false),
            AppItem.stub(name: "Slack", path: "/Applications/Slack.app", isRunning: true),
            AppItem.stub(name: "Ghostty", path: "/Applications/Ghostty.app", isRunning: true),
        ]
        let results = AppSearch.results(
            query: "",
            apps: apps,
            frontmostPath: "/Applications/Ghostty.app"
        )
        XCTAssertEqual(results.map(\.name), ["Slack"])
        XCTAssertTrue(
            AppSearch.results(query: "   ", apps: apps, frontmostPath: "/Applications/Ghostty.app")
                .map(\.name) == ["Slack"]
        )
    }

    func testResultsEmptyQueryNoRunningIsEmpty() {
        XCTAssertTrue(
            AppSearch.results(
                query: "",
                apps: [AppItem.stub(name: "Notes", isRunning: false)]
            ).isEmpty
        )
    }

    func testResultsEmptyQueryExcludesSelfLauncher() {
        let apps = [
            AppItem.stub(name: "Roocast", path: "/Applications/Roocast.app", isRunning: true),
            AppItem.stub(name: "Slack", path: "/Applications/Slack.app", isRunning: true),
        ]
        let results = AppSearch.results(
            query: "",
            apps: apps,
            selfPath: "/Applications/Roocast.app"
        )
        XCTAssertEqual(results.map(\.name), ["Slack"])
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

    /// Typing `note` must surface Notes — running Firefox profiles must not match.
    func testRankNoteFindsNotesNotFirefoxProfiles() {
        let apps = [
            AppItem.stub(
                name: "Firefox",
                profile: "default-release",
                path: "/Applications/Firefox.app",
                isRunning: true
            ),
            AppItem.stub(
                name: "Firefox",
                profile: "Profile 1",
                path: "/Applications/Firefox.app",
                isRunning: true
            ),
            AppItem.stub(name: "Notes", path: "/System/Applications/Notes.app"),
            AppItem.stub(name: "Keynote", path: "/Applications/Keynote.app"),
        ]
        let ranked = AppSearch.rank(query: "note", apps: apps)
        XCTAssertEqual(ranked.map(\.name), ["Notes", "Keynote"])
        XCTAssertEqual(ranked.first?.name, "Notes")
    }

    func testRankPrefersRunningFirefoxOverFindMyForFi() {
        let apps = [
            AppItem.stub(name: "FindMy", path: "/System/Applications/FindMy.app"),
            AppItem.stub(
                name: "Firefox",
                profile: "default-release",
                path: "/Applications/Firefox.app",
                isRunning: true
            ),
            AppItem.stub(
                name: "Firefox",
                profile: "Profile 1",
                path: "/Applications/Firefox.app",
                isRunning: true
            ),
            AppItem.stub(name: "Final Cut Pro"),
        ]
        let ranked = AppSearch.rank(query: "fi", apps: apps)
        XCTAssertEqual(ranked.first?.name, "Firefox")
        XCTAssertEqual(ranked.first?.profile, "default-release")
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

    /// Equal intention scores break alphabetically (Xab before Yab).
    func testRankNameTieBreaksAlphabetically() {
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

    func testResultsEmptyQueryIgnoresFolders() {
        let folders = [AppItem.folderStub(name: "Downloads")]
        let apps = [
            AppItem.stub(name: "Slack", path: "/Applications/Slack.app", isRunning: true),
        ]
        let results = AppSearch.results(query: "", apps: apps, folders: folders)
        XCTAssertEqual(results.map(\.name), ["Slack"])
        XCTAssertFalse(results.contains { $0.kind == .folder })
    }

    func testSwitchSuggestionsPreferShorterName() {
        let apps = [
            AppItem.stub(name: "Notebook", path: "/Applications/Notebook.app", isRunning: true),
            AppItem.stub(name: "Notes", path: "/Applications/Notes.app", isRunning: true),
        ]
        let ranked = AppSearch.switchSuggestions(apps: apps)
        XCTAssertEqual(ranked.first?.name, "Notes")
    }
}
