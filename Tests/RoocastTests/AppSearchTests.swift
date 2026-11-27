import XCTest
@testable import Roocast

/// Integration-leaning: most cases call `AppSearch.results` with stubs (compose
/// search + scoring + built-ins). Pure matcher helpers are still unit-shaped.
/// See `docs/TESTING.md` — Integration / AppSearch + stubs.
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

    func testMatchesCheckForUpdatesCommand() {
        XCTAssertTrue(AppSearch.matchesCheckForUpdatesCommand("u"))
        XCTAssertTrue(AppSearch.matchesCheckForUpdatesCommand("upd"))
        XCTAssertTrue(AppSearch.matchesCheckForUpdatesCommand("update"))
        XCTAssertTrue(AppSearch.matchesCheckForUpdatesCommand("check"))
        XCTAssertTrue(AppSearch.matchesCheckForUpdatesCommand("check for"))
        XCTAssertTrue(AppSearch.matchesCheckForUpdatesCommand("check for updates"))
        XCTAssertTrue(AppSearch.matchesCheckForUpdatesCommand("check updates"))
        XCTAssertFalse(AppSearch.matchesCheckForUpdatesCommand(""))
        XCTAssertFalse(AppSearch.matchesCheckForUpdatesCommand("updater"))
        XCTAssertFalse(AppSearch.matchesCheckForUpdatesCommand("quit"))
    }

    func testMatchesUninstallCommand() {
        XCTAssertTrue(AppSearch.matchesUninstallCommand("uni"))
        XCTAssertTrue(AppSearch.matchesUninstallCommand("uninstall"))
        XCTAssertTrue(AppSearch.matchesUninstallCommand("uninstall roo"))
        XCTAssertTrue(AppSearch.matchesUninstallCommand("uninstall roocast"))
        XCTAssertTrue(AppSearch.matchesUninstallCommand("remo"))
        XCTAssertTrue(AppSearch.matchesUninstallCommand("remove"))
        XCTAssertTrue(AppSearch.matchesUninstallCommand("remove roocast"))
        // Short prefixes must not false-fire via "remove roocast".
        XCTAssertFalse(AppSearch.matchesUninstallCommand("re"))
        XCTAssertFalse(AppSearch.matchesUninstallCommand("rem"))
        XCTAssertFalse(AppSearch.matchesUninstallCommand(""))
        XCTAssertFalse(AppSearch.matchesUninstallCommand("update"))
        XCTAssertFalse(AppSearch.matchesUninstallCommand("quit"))
    }

    func testResultsRePrefersReasonableSizeOverUninstall() {
        let results = AppSearch.results(query: "re", apps: [], folders: [])
        XCTAssertFalse(results.contains { $0.kind == .uninstall })
        XCTAssertEqual(results.first?.kind, .reasonableSize)
    }

    func testBuiltInsRankByIntentionNotInsertionOrder() {
        // "r" matches Right Half (name prefix) and Reasonable Size (name prefix).
        // Shorter name wins among equal prefix strength.
        let results = AppSearch.results(query: "r", apps: [], folders: [])
        let kinds = results.map(\.kind)
        XCTAssertTrue(kinds.contains(.rightHalf))
        XCTAssertTrue(kinds.contains(.reasonableSize))
        XCTAssertEqual(results.first?.kind, .rightHalf)
    }

    func testDemotePenaltySinksItemBelowPeers() {
        let notes = AppItem.stub(name: "Notes")
        let notebook = AppItem.stub(name: "Notebook")
        let demoted = AppSearch.results(
            query: "no",
            apps: [notes, notebook],
            folders: [],
            demoteLevels: [notes.id: 1]
        )
        XCTAssertEqual(demoted.map(\.name), ["Notebook", "Notes"])
        // Still appears after demote.
        XCTAssertEqual(demoted.count, 2)
    }

    func testResultsPutsCheckForUpdates() {
        let results = AppSearch.results(
            query: "update",
            apps: [AppItem.stub(name: "Notes")],
            folders: []
        )
        XCTAssertEqual(results.first?.kind, .checkForUpdates)
        XCTAssertEqual(results.first?.name, "Check for Updates")
    }

    func testResultsPutsUninstall() {
        let results = AppSearch.results(
            query: "uninstall",
            apps: [AppItem.stub(name: "Notes")],
            folders: []
        )
        XCTAssertEqual(results.first?.kind, .uninstall)
        XCTAssertEqual(results.first?.name, "Uninstall Roocast")
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

    func testResultsPutsCalculatorFirst() {
        let results = AppSearch.results(query: "2+2", apps: [AppItem.stub(name: "Notes")], folders: [])
        guard case .calculator(let copyText) = results.first?.kind else {
            return XCTFail("expected calculator lead row")
        }
        XCTAssertEqual(copyText, "4")
        XCTAssertEqual(results.first?.name, "4")
        XCTAssertEqual(results.first?.profile, "2+2")
    }

    func testResultsNoCalculatorForPlainText() {
        let results = AppSearch.results(query: "notes", apps: [AppItem.stub(name: "Notes")], folders: [])
        XCTAssertFalse(results.contains {
            if case .calculator = $0.kind { return true }
            return false
        })
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

    func testResultsPutsTopAndBottomHalfFirst() {
        XCTAssertEqual(AppSearch.results(query: "top", apps: []).first?.kind, .topHalf)
        XCTAssertEqual(AppSearch.results(query: "th", apps: []).first?.kind, .topHalf)
        XCTAssertEqual(AppSearch.results(query: "bottom", apps: []).first?.kind, .bottomHalf)
        XCTAssertEqual(AppSearch.results(query: "bh", apps: []).first?.kind, .bottomHalf)
    }

    func testResultsPutsThirdCommandsFirst() {
        XCTAssertEqual(AppSearch.results(query: "first third", apps: []).first?.kind, .firstThird)
        XCTAssertEqual(AppSearch.results(query: "ft", apps: []).first?.kind, .firstThird)
        XCTAssertEqual(
            AppSearch.results(query: "last two thirds", apps: []).first?.kind,
            .lastTwoThirds
        )
        XCTAssertEqual(AppSearch.results(query: "ltt", apps: []).first?.kind, .lastTwoThirds)
    }

    func testResultsPutsMoveToCommandsFirst() {
        XCTAssertEqual(AppSearch.results(query: "move to top", apps: []).first?.kind, .moveToTop)
        XCTAssertEqual(AppSearch.results(query: "mtt", apps: []).first?.kind, .moveToTop)
        XCTAssertEqual(
            AppSearch.results(query: "move to bottom", apps: []).first?.kind,
            .moveToBottom
        )
        XCTAssertEqual(AppSearch.results(query: "move left", apps: []).first?.kind, .moveToLeft)
        XCTAssertEqual(AppSearch.results(query: "mtr", apps: []).first?.kind, .moveToRight)

        let moveResults = AppSearch.results(query: "move", apps: [])
        XCTAssertTrue(moveResults.contains { $0.kind == .moveToTop })
        XCTAssertTrue(moveResults.contains { $0.kind == .moveToBottom })
        XCTAssertTrue(moveResults.contains { $0.kind == .moveToLeft })
        XCTAssertTrue(moveResults.contains { $0.kind == .moveToRight })
        // Bare "top" still prefers Top Half, not Move to Top.
        XCTAssertEqual(AppSearch.results(query: "top", apps: []).first?.kind, .topHalf)
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

    func testTypedQueryExcludesSelfLauncherButKeepsQuitCommand() {
        let apps = [
            AppItem.stub(name: "Roocast", path: "/Applications/Roocast.app"),
            AppItem.stub(name: "Notes", path: "/Applications/Notes.app"),
        ]
        let roo = AppSearch.results(
            query: "roo",
            apps: apps,
            folders: [],
            selfPath: "/Applications/Roocast.app"
        )
        XCTAssertFalse(roo.contains { $0.kind == .app && $0.name == "Roocast" })

        let quit = AppSearch.results(
            query: "quit",
            apps: apps,
            folders: [],
            selfPath: "/Applications/Roocast.app"
        )
        XCTAssertEqual(quit.first?.kind, .quit)
        XCTAssertFalse(quit.contains { $0.kind == .app && $0.name == "Roocast" })
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

    // MARK: - Smart Ranking (usage)

    /// North star: 1-char query prefers the app habitually opened with that term.
    func testUsageTermHitSteersOneCharPrefixAmongPeers() {
        let finder = AppItem.stub(name: "Finder", path: "/System/Library/CoreServices/Finder.app")
        let firefox = AppItem.stub(name: "Firefox", path: "/Applications/Firefox.app")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let visit = UsageRanking.applyingVisit(previous: nil, query: "f", at: now)
        let usage = UsageRankingStore.Snapshot(
            visits: [firefox.id.uuidString: visit],
            now: now
        )

        let without = AppSearch.results(
            query: "f",
            apps: [finder, firefox],
            folders: []
        )
        // Built-ins also match "f"; assert among app peers only.
        let withoutApps = without.filter { $0.kind == .app }
        // Shorter name prefix: Finder before Firefox without usage.
        XCTAssertEqual(withoutApps.first?.name, "Finder")

        let with = AppSearch.results(
            query: "f",
            apps: [finder, firefox],
            folders: [],
            usage: usage
        )
        let withApps = with.filter { $0.kind == .app }
        XCTAssertEqual(withApps.first?.name, "Firefox")
    }

    func testUsageDemoteStillSinksHabitualApp() {
        let notes = AppItem.stub(name: "Notes", path: "/Applications/Notes.app")
        let notebook = AppItem.stub(name: "Notebook", path: "/Applications/Notebook.app")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var visit: UsageVisit?
        for i in 0..<5 {
            visit = UsageRanking.applyingVisit(
                previous: visit,
                query: "no",
                at: now.addingTimeInterval(TimeInterval(i))
            )
        }
        let usage = UsageRankingStore.Snapshot(
            visits: [notes.id.uuidString: visit!],
            now: now.addingTimeInterval(10)
        )

        let boosted = AppSearch.results(
            query: "no",
            apps: [notes, notebook],
            folders: [],
            usage: usage
        )
        XCTAssertEqual(boosted.first?.name, "Notes")

        let demoted = AppSearch.results(
            query: "no",
            apps: [notes, notebook],
            folders: [],
            demoteLevels: [notes.id: 1],
            usage: usage
        )
        XCTAssertEqual(demoted.first?.name, "Notebook")
        XCTAssertEqual(demoted.map(\.name), ["Notebook", "Notes"])
    }

    func testSwitchSuggestionsPreferFrecentRunningApp() {
        let slack = AppItem.stub(
            name: "Slack",
            path: "/Applications/Slack.app",
            isRunning: true
        )
        let zoom = AppItem.stub(
            name: "Zoom",
            path: "/Applications/Zoom.app",
            isRunning: true
        )
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var visit: UsageVisit?
        for i in 0..<3 {
            visit = UsageRanking.applyingVisit(
                previous: visit,
                query: nil,
                at: now.addingTimeInterval(TimeInterval(i))
            )
        }
        let usage = UsageRankingStore.Snapshot(
            visits: [zoom.id.uuidString: visit!],
            now: now.addingTimeInterval(10)
        )

        let ranked = AppSearch.switchSuggestions(apps: [slack, zoom], usage: usage)
        XCTAssertEqual(ranked.first?.name, "Zoom")
    }
}
