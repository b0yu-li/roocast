import XCTest
@testable import Roocast

@MainActor
final class SearchRankPreferencesTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("roocast-rank-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
        try await super.tearDown()
    }

    func testDecreaseAndResetPersist() {
        let id = UUID()
        let prefs = SearchRankPreferences(fileURL: tempURL)
        XCTAssertFalse(prefs.isDemoted(id))

        prefs.decreaseRanking(for: id)
        XCTAssertEqual(prefs.level(for: id), 1)
        XCTAssertTrue(prefs.isDemoted(id))

        prefs.decreaseRanking(for: id)
        XCTAssertEqual(prefs.level(for: id), 2)

        // Reload from disk.
        let reloaded = SearchRankPreferences(fileURL: tempURL)
        XCTAssertEqual(reloaded.level(for: id), 2)

        reloaded.resetRanking(for: id)
        XCTAssertFalse(reloaded.isDemoted(id))

        let cleared = SearchRankPreferences(fileURL: tempURL)
        XCTAssertEqual(cleared.level(for: id), 0)
    }
}
