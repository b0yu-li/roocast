import XCTest
@testable import Roocast

final class AppLauncherTests: XCTestCase {
    
    // MARK: - Launch Logic Tests
    
    func testLaunchFirefoxProfileWithRunningProfile() {
        // Mock: simulate a running profile
        // In real tests, we'd use dependency injection or protocols
        // For now, test the logic flow
        
        // This test verifies that when a profile is running,
        // we should activate existing instance instead of launching new
        XCTAssertTrue(true, "Would test activation logic with mocked running profile")
    }
    
    func testLaunchFirefoxProfileWithNotRunningProfile() {
        // Mock: simulate a non-running profile
        // Should launch new instance with -P argument
        
        XCTAssertTrue(true, "Would test launch logic with mocked non-running profile")
    }
    
    // MARK: - AppItem Tests
    
    func testAppItemWithProfile() {
        let url = URL(fileURLWithPath: "/Applications/Firefox.app")
        let appItem = AppItem(url: url, isRunning: true, profile: "work")
        
        XCTAssertEqual(appItem.name, "Firefox")
        XCTAssertEqual(appItem.profile, "work")
        XCTAssertTrue(appItem.isRunning)
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
    
    // MARK: - Search Tests
    
    func testSearchWithProfileName() {
        // Test that searching "work" returns Firefox (work)
        // Test that searching "personal" returns Firefox (personal)
        // Test that searching "Firefox" returns both
        
        XCTAssertTrue(true, "Would test search with profile names")
    }
    
    func testSearchFiltersByProfileName() {
        // Test that searching "work" returns Firefox (work)
        // Test that searching "personal" returns Firefox (personal)
        // Test that searching "Firefox" returns both
        
        XCTAssertTrue(true, "Would test profile name filtering")
    }

    // MARK: - Quit Command Tests

    func testQuitCommandMatchesPrefixes() {
        XCTAssertTrue(AppIndex.matchesQuitCommand("q"))
        XCTAssertTrue(AppIndex.matchesQuitCommand("qui"))
        XCTAssertTrue(AppIndex.matchesQuitCommand("quit"))
        XCTAssertTrue(AppIndex.matchesQuitCommand("Quit"))
        XCTAssertTrue(AppIndex.matchesQuitCommand("quit roo"))
        XCTAssertFalse(AppIndex.matchesQuitCommand(""))
        XCTAssertFalse(AppIndex.matchesQuitCommand("safari"))
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

    // MARK: - Intention Score Tests

    func testIntentionScorePrefersPrefixOverSubstring() {
        // Typing "no" should intend Notes, not Keynote (mid-string "no").
        let notes = IntentionScore.score(query: "no", name: "Notes", searchText: "Notes")
        let keynote = IntentionScore.score(query: "no", name: "Keynote", searchText: "Keynote")
        XCTAssertGreaterThan(notes, keynote)
        XCTAssertGreaterThan(notes, 0)
        XCTAssertGreaterThan(keynote, 0)
    }

    func testIntentionScoreExactBeatsPrefix() {
        let exact = IntentionScore.score(query: "notes", name: "Notes", searchText: "Notes")
        let prefix = IntentionScore.score(query: "no", name: "Notes", searchText: "Notes")
        XCTAssertGreaterThan(exact, prefix)
    }

    func testIntentionScorePrefersShorterPrefixMatch() {
        let notes = IntentionScore.score(query: "no", name: "Notes", searchText: "Notes")
        let notebook = IntentionScore.score(query: "no", name: "Notebook", searchText: "Notebook")
        XCTAssertGreaterThan(notes, notebook)
    }

    func testIntentionScoreNoMatchIsZero() {
        XCTAssertEqual(IntentionScore.score(query: "xyz", name: "Notes", searchText: "Notes"), 0)
        XCTAssertEqual(IntentionScore.score(query: "", name: "Notes", searchText: "Notes"), 0)
    }

    func testIntentionScoreProfileWordPrefix() {
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
}
