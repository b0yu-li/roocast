import XCTest
import CryptoKit
@testable import Roocast

/// In-process integration tests for core user paths (2+ modules composed).
///
/// See `docs/TESTING.md` — Integration layer. No AppKit panel automation.
@MainActor
final class CoreUserPathIntegrationTests: XCTestCase {

    // MARK: - Countdown: Tab-lock → argument → lead row

    func testTabLockTimerThenArgumentYieldsReadyCountdownLead() {
        let session = SearchSession()
        session.query = "tim"
        XCTAssertTrue(session.tryLockCommand())
        XCTAssertEqual(session.lockedVerb, "timer")
        XCTAssertEqual(session.argument, "")
        XCTAssertEqual(session.searchQuery, "timer")

        let hint = AppSearch.results(query: session.searchQuery, apps: [], folders: [])
        XCTAssertEqual(hint.first?.kind, .countdownHint)

        session.argument = "2h"
        XCTAssertEqual(session.searchQuery, "timer 2h")

        let ready = AppSearch.results(query: session.searchQuery, apps: [], folders: [])
        guard case .countdown(let seconds) = ready.first?.kind else {
            return XCTFail("expected ready countdown lead after lock + 2h")
        }
        XCTAssertEqual(seconds, 2 * 3600)
        XCTAssertEqual(ready.first?.name, "2:00:00")
    }

    func testUnlockCommandRestoresComposedFreeText() {
        let session = SearchSession()
        session.query = "timer"
        XCTAssertTrue(session.tryLockCommand())
        session.argument = "90s"
        XCTAssertTrue(session.unlockCommand())
        XCTAssertNil(session.lockedVerb)
        XCTAssertEqual(session.query, "timer 90s")
        XCTAssertEqual(session.argument, "")

        let results = AppSearch.results(query: session.query, apps: [], folders: [])
        guard case .countdown(let seconds) = results.first?.kind else {
            return XCTFail("expected countdown after unlock")
        }
        XCTAssertEqual(seconds, 90)
    }

    func testClearResetsLockChipAndArgument() {
        let session = SearchSession()
        session.query = "coun"
        XCTAssertTrue(session.tryLockCommand())
        session.argument = "5m"
        XCTAssertTrue(session.showsClearButton)
        session.clear()
        XCTAssertNil(session.lockedVerb)
        XCTAssertEqual(session.query, "")
        XCTAssertEqual(session.argument, "")
        XCTAssertFalse(session.showsClearButton)
        XCTAssertEqual(session.searchQuery, "")
    }

    func testPrefixTimeLocksAndShowsTimerHint() {
        let session = SearchSession()
        session.query = "time"
        XCTAssertTrue(session.tryLockCommand())
        XCTAssertEqual(session.lockedVerb, "timer")
        let results = AppSearch.results(
            query: session.searchQuery,
            apps: [AppItem.stub(name: "Time Machine")],
            folders: []
        )
        XCTAssertEqual(results.first?.kind, .countdownHint)
        XCTAssertEqual(results.first?.name, "Timer")
    }

    // MARK: - Ranking: prefs demote → AppSearch

    func testDemoteLevelsFromPrefsSinkAppBelowPeerInResults() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("roocast-int-rank-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: temp) }

        let notes = AppItem.stub(name: "Notes")
        let notebook = AppItem.stub(name: "Notebook")
        let prefs = SearchRankPreferences(fileURL: temp)
        prefs.decreaseRanking(for: notes.id)

        let ranked = AppSearch.results(
            query: "no",
            apps: [notes, notebook],
            folders: [],
            demoteLevels: prefs.demoteLevels
        )
        XCTAssertEqual(ranked.map(\.name), ["Notebook", "Notes"])

        let reloaded = SearchRankPreferences(fileURL: temp)
        let again = AppSearch.results(
            query: "no",
            apps: [notes, notebook],
            folders: [],
            demoteLevels: reloaded.demoteLevels
        )
        XCTAssertEqual(again.map(\.name), ["Notebook", "Notes"])
    }

    // MARK: - Calculator lead over apps

    func testCalculatorLeadsOverMatchingAppStub() {
        let results = AppSearch.results(
            query: "2+2",
            apps: [AppItem.stub(name: "22")],
            folders: []
        )
        guard case .calculator(let copyText) = results.first?.kind else {
            return XCTFail("expected calculator lead")
        }
        XCTAssertEqual(copyText, "4")
    }

    // MARK: - Window snap: search hit → target frame (no AX)

    func testLeftHalfSearchHitMapsToTargetFrame() {
        let results = AppSearch.results(query: "lh", apps: [], folders: [])
        XCTAssertEqual(results.first?.kind, .leftHalf)

        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let frame = WindowSnap.targetFrame(of: visible, command: .left)
        XCTAssertEqual(frame.origin.x, 0, accuracy: 0.5)
        XCTAssertEqual(frame.width, 500, accuracy: 0.5)
        XCTAssertEqual(frame.height, visible.height, accuracy: 0.5)
    }

    func testReasonableSizeSearchHitMapsToCenteredFrame() {
        let results = AppSearch.results(query: "reasonable", apps: [], folders: [])
        XCTAssertEqual(results.first?.kind, .reasonableSize)

        let visible = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let frame = WindowSnap.targetFrame(of: visible, command: .reasonableSize)
        XCTAssertEqual(frame.midX, visible.midX, accuracy: 1)
        XCTAssertEqual(frame.midY, visible.midY, accuracy: 1)
    }

    // MARK: - Zoxide: published match → search returns folder

    func testPublishedZoxideMatchReturnedBySearch() {
        let index = AppIndex()
        let downloads = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true).path
        index.publishZoxideMatchForTesting(path: downloads, keywords: ["downloads"])

        let rows = index.search("z downloads")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.kind, .folder)
        XCTAssertEqual(rows.first?.path, downloads)

        index.scheduleZoxide(for: "notes")
        XCTAssertNil(index.zoxideItem)
        XCTAssertEqual(index.search("z downloads"), [])
    }

    func testZoomQueryIsNotZoxideMode() {
        XCTAssertNil(Zoxide.keywords(from: "zoom"))
        let results = AppSearch.results(
            query: "zoom",
            apps: [AppItem.stub(name: "zoom.us")],
            folders: []
        )
        XCTAssertEqual(results.first?.name, "zoom.us")
    }

    // MARK: - Navigation + countdown lead list

    func testNavigationSyncsToCountdownLeadList() {
        let results = AppSearch.results(
            query: "timer 5m",
            apps: [AppItem.stub(name: "Notes")],
            folders: []
        )
        XCTAssertGreaterThanOrEqual(results.count, 1)
        guard case .countdown = results.first?.kind else {
            return XCTFail("countdown should lead")
        }

        let nav = NavigationState()
        nav.sync(itemCount: results.count)
        XCTAssertEqual(nav.selectedIndex, 0)
        nav.moveDown()
        if results.count > 1 {
            XCTAssertEqual(nav.selectedIndex, 1)
        } else {
            XCTAssertEqual(nav.selectedIndex, 0)
        }
    }

    // MARK: - Clipboard: recopy + persist

    func testRecopySameTextPromotesAcrossPersistReload() throws {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("roocast-int-clip-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: temp) }

        let writer = ClipboardStore(storageURL: temp)
        writer.prependForTesting("alpha")
        writer.prependForTesting("beta")
        writer.prependForTesting("alpha")
        writer.persistNow()
        XCTAssertEqual(writer.items.map(\.text), ["alpha", "beta"])

        let reader = ClipboardStore(storageURL: temp)
        reader.loadPersistedHistory()
        XCTAssertEqual(reader.items.map(\.text), ["alpha", "beta"])
    }

    // MARK: - Updates: signed feed pipeline

    func testSignedFeedPipelineAvailableThenUpToDate() throws {
        let keys = IntegrationUpdateKeys.generate()
        let version = "9.9.9"
        let sha = "cafebabe"
        let url = "https://example.com/Roocast-\(version).dmg"
        let sig = keys.sign(version: version, sha256: sha, dmgURL: url)

        let json = """
        {"version":"\(version)","dmg_url":"\(url)","sha256":"\(sha)","ed25519":"\(sig)","released":"2026-01-01"}
        """.data(using: .utf8)!
        let feed = try UpdateCheck.decodeFeed(from: json)

        let available = UpdateCheck.outcome(
            feed: feed,
            currentVersion: "0.1.0",
            publicKeyBase64: keys.publicKeyBase64
        )
        guard case .available(let latest, let dmgURL, let sha256) = available else {
            return XCTFail("expected available, got \(available)")
        }
        XCTAssertEqual(latest, version)
        XCTAssertEqual(dmgURL.absoluteString, url)
        XCTAssertEqual(sha256, sha)

        let upToDate = UpdateCheck.outcome(
            feed: feed,
            currentVersion: version,
            publicKeyBase64: keys.publicKeyBase64
        )
        guard case .upToDate = upToDate else {
            return XCTFail("expected upToDate, got \(upToDate)")
        }
    }
}

/// Ephemeral Ed25519 pair for integration tests only.
private struct IntegrationUpdateKeys {
    let privateKey: Curve25519.Signing.PrivateKey
    var publicKeyBase64: String {
        privateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    static func generate() -> IntegrationUpdateKeys {
        IntegrationUpdateKeys(privateKey: Curve25519.Signing.PrivateKey())
    }

    func sign(version: String, sha256: String, dmgURL: String) -> String {
        let message = UpdateSigning.canonicalMessage(
            version: version,
            sha256: sha256,
            dmgURL: dmgURL
        )
        let sig = try! privateKey.signature(for: message)
        return sig.base64EncodedString()
    }
}
