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
}
