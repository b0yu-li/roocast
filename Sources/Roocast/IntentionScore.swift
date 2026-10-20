import Foundation

/// Ranks how likely a typed query was meant for a given app name.
///
/// Prefix matches beat mid-string substring matches so typing `no` prefers
/// Notes over Keynote (`Key`**`no`**`te`).
enum IntentionScore {
    /// Higher is a stronger match. Returns 0 when the query does not match.
    nonisolated static func score(query: String, name: String, searchText: String) -> Int {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return 0 }

        let nameLower = name.lowercased()
        let searchLower = searchText.lowercased()

        // Exact matches win outright.
        if nameLower == q { return 100_000 }
        if searchLower == q { return 99_000 }

        // Prefix of the primary name — strongest intention signal.
        // "no" → Notes (prefix) beats Keynote (mid-string "no").
        if nameLower.hasPrefix(q) {
            // Among prefixes, prefer the shorter name (Notes > Notebook).
            return 80_000 - nameLower.count
        }

        // Prefix of any word in searchable text (profiles, multi-word names).
        for word in searchLower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) where !word.isEmpty {
            if word.hasPrefix(q) {
                return 70_000 - word.count
            }
        }

        // Substring in the name — later positions score lower.
        if let range = nameLower.range(of: q) {
            let position = nameLower.distance(from: nameLower.startIndex, to: range.lowerBound)
            return 30_000 - (position * 1_000) - nameLower.count
        }

        // Substring elsewhere in searchable text.
        if let range = searchLower.range(of: q) {
            let position = searchLower.distance(from: searchLower.startIndex, to: range.lowerBound)
            return 20_000 - (position * 1_000)
        }

        return 0
    }

    nonisolated static func score(query: String, app: AppItem) -> Int {
        score(query: query, name: app.name, searchText: app.searchText)
    }

    /// Empty-query switch intention: how likely the user wants to jump to this app.
    ///
    /// Only running apps score. Excludes:
    /// - the frontmost regular app (no profile) — you're already there
    /// - Roocast itself (`selfPath`) — the launcher is already open
    ///
    /// Firefox profile rows keep scoring so you can jump between profiles even when
    /// Firefox is frontmost.
    ///
    /// - Parameter frontmostPath: Bundle path of the frontmost app, if known.
    /// - Parameter selfPath: Bundle path of this launcher, if known.
    nonisolated static func switchScore(
        app: AppItem,
        frontmostPath: String?,
        selfPath: String? = nil
    ) -> Int {
        guard app.kind == .app, app.isRunning else { return 0 }

        if let selfPath, app.path == selfPath {
            return 0
        }

        if let frontmostPath,
           app.profile == nil,
           app.path == frontmostPath {
            return 0
        }

        // Same shorter-name preference as typed prefix ranking (Notes before Notebook).
        var score = 50_000 - min(app.name.count, 10_000)
        // Profile rows are explicit switch targets when multi-instance apps are running.
        if app.profile != nil {
            score += 1_000
        }
        return score
    }
}
