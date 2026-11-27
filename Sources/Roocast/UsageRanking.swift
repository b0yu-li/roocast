import Foundation

/// One entry's on-device usage: decaying frecency anchor + recent search terms.
struct UsageVisit: Codable, Hashable, Sendable, Equatable {
    /// When the decayed score falls back to 1 (later anchors score higher).
    var anchor: Date
    var openedAt: Date
    /// Distinct folded terms, most recent last, at most `UsageRanking.termLimit`.
    var searchTerms: [String]
}

/// What one ranking pass reads for a single item key.
struct UsageSignals: Sendable, Equatable {
    /// 1 when never opened or decayed to the floor.
    let frecency: Double
    /// Empty unless opened recently enough for terms to steer the query.
    let searchTerms: [String]

    static let unused = UsageSignals(frecency: 1, searchTerms: [])
}

/// Pure frecent math + score boost for Smart Ranking (Tinycast-shaped).
///
/// Local only — no network. Intention still gates matches; this breaks ties and
/// steers 1–2 character queries toward habitual launches.
enum UsageRanking {
    /// Each visit adds 100; score halves every ten days; never below 1.
    nonisolated static let halfLife: TimeInterval = 10 * 86_400
    nonisolated static let visitWeight = 100.0
    /// Past this since last open, search terms stop steering.
    nonisolated static let termWindow: TimeInterval = 408 * 3_600
    nonisolated static let termLimit = 3
    nonisolated static let queryLimit = 64

    /// Term hit boost — large enough to prefer habitual prefix among peers.
    nonisolated static let termHitBoost = 25_000
    /// Cap on log-scaled frecency additive boost.
    nonisolated static let frecencyBoostCap = 5_000

    private nonisolated static let exponentCeiling = 709.78
    private nonisolated static let decay = log(2) / halfLife

    /// Fold query the same way ranking will compare it.
    nonisolated static func normalize(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated static func frecency(anchor: Date, at timestamp: Date) -> Double {
        let exponent = decay * anchor.timeIntervalSince(timestamp)
        return max(1, exp(min(exponent, exponentCeiling)))
    }

    /// Anchor such that score is `score + visitWeight` at `timestamp`.
    nonisolated static func anchor(visitedWith score: Double, at timestamp: Date) -> Date {
        timestamp.addingTimeInterval(log(score + visitWeight) / decay)
    }

    /// Apply one visit onto a previous record (or nil).
    nonisolated static func applyingVisit(
        previous: UsageVisit?,
        query: String?,
        at timestamp: Date
    ) -> UsageVisit {
        let score = previous.map { frecency(anchor: $0.anchor, at: timestamp) } ?? 1
        var terms = previous?.searchTerms ?? []
        if let raw = query {
            let term = normalize(raw)
            if !term.isEmpty, term.count <= queryLimit {
                terms.removeAll { $0 == term }
                terms.append(term)
                terms = Array(terms.suffix(termLimit))
            }
        }
        return UsageVisit(
            anchor: anchor(visitedWith: score, at: timestamp),
            openedAt: timestamp,
            searchTerms: terms
        )
    }

    nonisolated static func signals(of visit: UsageVisit?, at timestamp: Date) -> UsageSignals {
        guard let visit else { return .unused }
        let frecency = frecency(anchor: visit.anchor, at: timestamp)
        let recent = frecency > 1 && timestamp.timeIntervalSince(visit.openedAt) < termWindow
        return UsageSignals(frecency: frecency, searchTerms: recent ? visit.searchTerms : [])
    }

    /// Drop expired anchors (score would already be the unused floor).
    nonisolated static func live(
        _ table: [String: UsageVisit],
        at timestamp: Date
    ) -> [String: UsageVisit] {
        table.filter { !$0.key.isEmpty && $0.value.anchor > timestamp }
    }

    /// Additive boost after intention match. Empty query → frecency only.
    nonisolated static func scoreBoost(query: String, usage: UsageSignals) -> Int {
        let q = normalize(query)
        var boost = 0
        if !q.isEmpty, hasTermHit(query: q, terms: usage.searchTerms) {
            boost += termHitBoost
        }
        boost += frecencyBoost(usage.frecency)
        return boost
    }

    /// Empty-summon / switch list: frecency only (no term steering).
    nonisolated static func switchBoost(usage: UsageSignals) -> Int {
        frecencyBoost(usage.frecency)
    }

    nonisolated static func hasTermHit(query: String, terms: [String]) -> Bool {
        let q = normalize(query)
        guard !q.isEmpty else { return false }
        return terms.contains { term in
            term.hasPrefix(q) || q.hasPrefix(term)
        }
    }

    /// log₂(frecency) scaled; unused (1) → 0; capped.
    nonisolated static func frecencyBoost(_ frecency: Double) -> Int {
        guard frecency > 1 else { return 0 }
        let raw = Int((log(frecency) / log(2.0)) * 500.0)
        return min(frecencyBoostCap, max(0, raw))
    }
}
