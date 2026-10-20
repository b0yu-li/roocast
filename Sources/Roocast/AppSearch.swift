import Foundation

/// Pure search ranking: quit command + intention-scored apps and folders.
///
/// Kept free of `AppIndex` / disk I/O so ranking stays unit-testable.
enum AppSearch {
    /// Matches as the user types toward "quit" / "quit roocast".
    nonisolated static func matchesQuitCommand(_ query: String) -> Bool {
        let lowered = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else { return false }
        return "quit".hasPrefix(lowered) || "quit roocast".hasPrefix(lowered)
    }

    /// Quit (if matched) first, then apps + folders ranked together by `IntentionScore`.
    ///
    /// Empty / whitespace query returns running-app switch suggestions (no folders/quit).
    ///
    /// - Parameter folders: Folder shortcut rows. Defaults to built-in shortcuts.
    ///   Pass stubs in unit tests to avoid disk icon lookup.
    /// - Parameter frontmostPath: Bundle path of the frontmost app to exclude from
    ///   empty-query switch suggestions. Ignored when the query is non-empty.
    /// - Parameter selfPath: Bundle path of Roocast itself to exclude from switch
    ///   suggestions. Ignored when the query is non-empty.
    nonisolated static func results(
        query: String,
        apps: [AppItem],
        folders: [AppItem]? = nil,
        frontmostPath: String? = nil,
        selfPath: String? = nil
    ) -> [AppItem] {
        let lowered = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowered.isEmpty {
            return switchSuggestions(apps: apps, frontmostPath: frontmostPath, selfPath: selfPath)
        }

        let folderItems = folders ?? FolderShortcut.builtIns.map { AppItem.folder($0) }

        var output: [AppItem] = []
        if matchesQuitCommand(lowered) {
            output.append(.quitRoocast)
        }
        output.append(contentsOf: rank(query: lowered, apps: apps + folderItems))
        return output
    }

    /// Rank items by intention score (prefix > mid-string); ties break by name.
    nonisolated static func rank(query: String, apps: [AppItem]) -> [AppItem] {
        let lowered = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else { return [] }

        return apps
            .map { ($0, IntentionScore.score(query: lowered, app: $0)) }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
            }
            .map(\.0)
    }

    /// Empty-summon list: running apps ranked by switch intention.
    nonisolated static func switchSuggestions(
        apps: [AppItem],
        frontmostPath: String? = nil,
        selfPath: String? = nil
    ) -> [AppItem] {
        apps
            .map {
                (
                    $0,
                    IntentionScore.switchScore(app: $0, frontmostPath: frontmostPath, selfPath: selfPath)
                )
            }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
            }
            .map(\.0)
    }
}
