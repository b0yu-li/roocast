import XCTest
@testable import Roocast

final class AppLauncherTests: XCTestCase {

    // MARK: - AppItem

    func testAppItemWithProfile() {
        let url = URL(fileURLWithPath: "/Applications/Firefox.app")
        let appItem = AppItem(url: url, isRunning: true, profile: "work")

        XCTAssertEqual(appItem.name, "Firefox")
        XCTAssertEqual(appItem.profile, "work")
        XCTAssertTrue(appItem.isRunning)
        XCTAssertEqual(appItem.kind, .app)
    }

    func testAppItemWithoutProfile() {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let appItem = AppItem(url: url, isRunning: false)

        XCTAssertEqual(appItem.name, "Safari")
        XCTAssertNil(appItem.profile)
        XCTAssertFalse(appItem.isRunning)
    }

    func testAppItemSearchTextWithProfile() {
        let url = URL(fileURLWithPath: "/Applications/Firefox.app")
        let appItem = AppItem(url: url, isRunning: true, profile: "work")

        XCTAssertTrue(appItem.searchText.contains("Firefox"))
        XCTAssertTrue(appItem.searchText.contains("work"))
    }

    func testAppItemSearchTextWithoutProfile() {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let appItem = AppItem(url: url, isRunning: false)

        XCTAssertEqual(appItem.searchText, "Safari")
    }

    func testAppItemStub() {
        let item = AppItem.stub(name: "Notes", profile: nil, isRunning: true)
        XCTAssertEqual(item.name, "Notes")
        XCTAssertNil(item.icon)
        XCTAssertTrue(item.isRunning)
        XCTAssertEqual(item.searchText, "Notes")
    }

    // MARK: - Quit command (via AppIndex facade)

    func testQuitCommandMatchesPrefixes() {
        XCTAssertTrue(AppIndex.matchesQuitCommand("q"))
        XCTAssertTrue(AppIndex.matchesQuitCommand("quit"))
        XCTAssertFalse(AppIndex.matchesQuitCommand("quite"))
    }

    func testQuitCommandItemKind() {
        XCTAssertEqual(AppItem.quitRoocast.kind, .quit)
        XCTAssertEqual(AppItem.quitRoocast.name, "Quit Roocast")
    }

    @MainActor
    func testSearchReturnsQuitCommand() {
        let index = AppIndex()
        let results = index.search("quit")
        XCTAssertTrue(results.contains { $0.kind == .quit })
        XCTAssertEqual(results.first?.kind, .quit)
    }

    // MARK: - Layout / version

    func testLauncherLayoutIsCompact() {
        XCTAssertEqual(LauncherLayout.width, 640)
        XCTAssertEqual(LauncherLayout.height, 400)
        XCTAssertGreaterThan(LauncherLayout.cornerRadius, 0)
    }

    func testAppVersionString() {
        XCTAssertEqual(AppVersion.string, "0.5.3")
        XCTAssertEqual(AppVersion.major, 0)
        XCTAssertEqual(AppVersion.minor, 5)
        XCTAssertEqual(AppVersion.patch, 3)
    }

    /// Reindex must reuse the same id or the switcher ForEach rebuilds every row (visible jump).
    func testAppItemIDStableAcrossRunningFlag() {
        let a = AppItem.stub(name: "Notes", path: "/Applications/Notes.app", isRunning: true)
        let b = AppItem.stub(name: "Notes", path: "/Applications/Notes.app", isRunning: false)
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(a.id, AppItem.stableID(path: "/Applications/Notes.app"))
    }

    func testAppItemIDDiffersByProfile() {
        let work = AppItem.stub(
            name: "Firefox",
            profile: "work",
            path: "/Applications/Firefox.app"
        )
        let personal = AppItem.stub(
            name: "Firefox",
            profile: "personal",
            path: "/Applications/Firefox.app"
        )
        XCTAssertNotEqual(work.id, personal.id)
    }
}
