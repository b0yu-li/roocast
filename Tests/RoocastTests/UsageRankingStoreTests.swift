import XCTest
@testable import Roocast

@MainActor
final class UsageRankingStoreTests: XCTestCase {

    func testPersistReloadRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roocast-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("launcher-usage.json")
        let id = UUID()
        let writer = UsageRankingStore(fileURL: url)
        writer.visit(itemID: id, query: "ff")
        writer.visit(itemID: id, query: "f")
        await writer.flush()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let reader = UsageRankingStore(fileURL: url)
        let usage = reader.snapshot().usage(for: id)
        XCTAssertGreaterThan(usage.frecency, 1)
        XCTAssertTrue(usage.searchTerms.contains("f"))
        XCTAssertTrue(usage.searchTerms.contains("ff") || usage.searchTerms.last == "f")
    }

    func testEmptyKeyIgnored() {
        let store = UsageRankingStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("roocast-usage-empty-\(UUID().uuidString).json")
        )
        store.visit(itemKey: "", query: "x")
        XCTAssertTrue(store.isEmpty)
    }

    func testRevisionBumpsOnVisit() {
        let store = UsageRankingStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("roocast-usage-rev-\(UUID().uuidString).json")
        )
        let before = store.revision
        store.visit(itemID: UUID(), query: "n")
        XCTAssertEqual(store.revision, before + 1)
    }
}
