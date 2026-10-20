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
    /// - Parameter folders: Folder shortcut rows. Defaults to built-in shortcuts.
    ///   Pass stubs in unit tests to avoid disk icon lookup.
    nonisolated static func results(
        query: String,
        apps: [AppItem],
        folders: [AppItem]? = nil
    ) -> [AppItem] {
        let lowered = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else { return [] }

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
}
