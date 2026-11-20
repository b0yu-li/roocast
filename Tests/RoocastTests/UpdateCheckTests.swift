import XCTest
@testable import Roocast

final class UpdateCheckTests: XCTestCase {

    func testIsNewerSemver() {
        XCTAssertTrue(UpdateCheck.isNewer("0.12.0", than: "0.11.0"))
        XCTAssertTrue(UpdateCheck.isNewer("1.0.0", than: "0.11.0"))
        XCTAssertTrue(UpdateCheck.isNewer("0.11.1", than: "0.11.0"))
        XCTAssertFalse(UpdateCheck.isNewer("0.11.0", than: "0.11.0"))
        XCTAssertFalse(UpdateCheck.isNewer("0.10.9", than: "0.11.0"))
        XCTAssertTrue(UpdateCheck.isNewer("0.11", than: "0.10.9"))
        XCTAssertFalse(UpdateCheck.isNewer("0.11", than: "0.11.0"))
    }

    func testDecodeFeed() throws {
        let json = """
        {
          "version": "0.12.0",
          "dmg_url": "https://example.com/downloads/Roocast-0.12.0.dmg",
          "released": "2026-12-01"
        }
        """.data(using: .utf8)!
        let feed = try UpdateCheck.decodeFeed(from: json)
        XCTAssertEqual(feed.version, "0.12.0")
        XCTAssertEqual(feed.dmg_url, "https://example.com/downloads/Roocast-0.12.0.dmg")
        XCTAssertEqual(feed.released, "2026-12-01")
    }

    func testOutcomeUpToDate() throws {
        let feed = UpdateCheck.Feed(
            version: "0.11.0",
            dmg_url: "https://example.com/downloads/Roocast-0.11.0.dmg",
            released: nil
        )
        XCTAssertEqual(
            UpdateCheck.outcome(feed: feed, currentVersion: "0.11.0"),
            .upToDate(current: "0.11.0")
        )
    }

    func testOutcomeAvailable() throws {
        let feed = UpdateCheck.Feed(
            version: "0.12.0",
            dmg_url: "https://example.com/downloads/Roocast-0.12.0.dmg",
            released: "2026-12-01"
        )
        let outcome = UpdateCheck.outcome(feed: feed, currentVersion: "0.11.0")
        guard case .available(let latest, let url) = outcome else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(latest, "0.12.0")
        XCTAssertEqual(url.absoluteString, "https://example.com/downloads/Roocast-0.12.0.dmg")
    }

    func testOutcomeFailedBadURL() {
        let feed = UpdateCheck.Feed(version: "0.12.0", dmg_url: "", released: nil)
        XCTAssertEqual(UpdateCheck.outcome(feed: feed, currentVersion: "0.11.0"), .failed)
    }
}
