import XCTest
@testable import Roocast

final class UsageRankingTests: XCTestCase {

    // MARK: - Frecent decay / visit weight / floor

    func testFirstVisitLandsAboveFloor() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let visit = UsageRanking.applyingVisit(previous: nil, query: "f", at: now)
        let score = UsageRanking.frecency(anchor: visit.anchor, at: now)
        XCTAssertEqual(score, 1 + UsageRanking.visitWeight, accuracy: 0.01)
    }

    func testSecondVisitStacksWeight() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let first = UsageRanking.applyingVisit(previous: nil, query: "f", at: t0)
        let t1 = t0.addingTimeInterval(60)
        let second = UsageRanking.applyingVisit(previous: first, query: "f", at: t1)
        let score = UsageRanking.frecency(anchor: second.anchor, at: t1)
        XCTAssertEqual(score, 1 + 2 * UsageRanking.visitWeight, accuracy: 0.5)
    }

    func testFrecencyHalvesOverHalfLife() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let visit = UsageRanking.applyingVisit(previous: nil, query: nil, at: now)
        let later = now.addingTimeInterval(UsageRanking.halfLife)
        let decayed = UsageRanking.frecency(anchor: visit.anchor, at: later)
        // ~101 / 2 ≈ 50.5
        XCTAssertEqual(decayed, (1 + UsageRanking.visitWeight) / 2, accuracy: 0.5)
    }

    func testFrecencyNeverBelowOne() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let visit = UsageRanking.applyingVisit(previous: nil, query: nil, at: now)
        let far = now.addingTimeInterval(UsageRanking.halfLife * 20)
        XCTAssertEqual(UsageRanking.frecency(anchor: visit.anchor, at: far), 1, accuracy: 0.001)
    }

    // MARK: - Terms

    func testNormalizeFoldsCaseAndWhitespace() {
        XCTAssertEqual(UsageRanking.normalize("  FiRe  "), "fire")
    }

    func testTermsDedupedAndCappedAtThree() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        var visit = UsageRanking.applyingVisit(previous: nil, query: "a", at: t0)
        visit = UsageRanking.applyingVisit(previous: visit, query: "b", at: t0.addingTimeInterval(1))
        visit = UsageRanking.applyingVisit(previous: visit, query: "c", at: t0.addingTimeInterval(2))
        visit = UsageRanking.applyingVisit(previous: visit, query: "d", at: t0.addingTimeInterval(3))
        XCTAssertEqual(visit.searchTerms, ["b", "c", "d"])
        // Re-visit "b" moves it to the end.
        visit = UsageRanking.applyingVisit(previous: visit, query: "b", at: t0.addingTimeInterval(4))
        XCTAssertEqual(visit.searchTerms, ["c", "d", "b"])
    }

    func testTermWindowGatesSearchTerms() {
        let opened = Date(timeIntervalSince1970: 1_700_000_000)
        let visit = UsageRanking.applyingVisit(previous: nil, query: "ff", at: opened)
        let fresh = UsageRanking.signals(of: visit, at: opened.addingTimeInterval(60))
        XCTAssertEqual(fresh.searchTerms, ["ff"])
        let stale = UsageRanking.signals(
            of: visit,
            at: opened.addingTimeInterval(UsageRanking.termWindow + 1)
        )
        // Frecency may still be >1 briefly, but past termWindow terms are empty.
        // After termWindow with only one visit, frecency may be near floor —
        // either way terms must be empty.
        XCTAssertTrue(stale.searchTerms.isEmpty)
    }

    // MARK: - scoreBoost

    func testTermHitBoostBeatsFrecencyAlone() {
        let withTerm = UsageSignals(frecency: 2, searchTerms: ["f"])
        let frecentOnly = UsageSignals(frecency: 10_000, searchTerms: [])
        let termBoost = UsageRanking.scoreBoost(query: "f", usage: withTerm)
        let frecBoost = UsageRanking.scoreBoost(query: "f", usage: frecentOnly)
        XCTAssertGreaterThan(termBoost, frecBoost)
        XCTAssertGreaterThanOrEqual(termBoost, UsageRanking.termHitBoost)
    }

    func testFrecencyBoostCaps() {
        let huge = UsageSignals(frecency: exp(20), searchTerms: [])
        XCTAssertEqual(
            UsageRanking.scoreBoost(query: "x", usage: huge),
            UsageRanking.frecencyBoostCap
        )
    }

    func testUnusedHasZeroBoost() {
        XCTAssertEqual(UsageRanking.scoreBoost(query: "f", usage: .unused), 0)
        XCTAssertEqual(UsageRanking.switchBoost(usage: .unused), 0)
    }

    func testSwitchBoostIgnoresTerms() {
        let usage = UsageSignals(frecency: 101, searchTerms: ["firefox"])
        XCTAssertEqual(
            UsageRanking.switchBoost(usage: usage),
            UsageRanking.frecencyBoost(101)
        )
        XCTAssertNotEqual(
            UsageRanking.switchBoost(usage: usage),
            UsageRanking.scoreBoost(query: "f", usage: usage)
        )
    }

    func testLiveDropsExpiredAnchors() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let liveVisit = UsageRanking.applyingVisit(previous: nil, query: "a", at: now)
        let dead = UsageVisit(
            anchor: now.addingTimeInterval(-1),
            openedAt: now.addingTimeInterval(-100),
            searchTerms: ["z"]
        )
        let table = UsageRanking.live(
            ["live": liveVisit, "dead": dead, "": liveVisit],
            at: now
        )
        XCTAssertEqual(Set(table.keys), ["live"])
    }
}
