import Foundation

/// Pure search ranking: built-in commands + intention-scored apps and folders.
///
/// Kept free of `AppIndex` / disk I/O so ranking stays unit-testable.
enum AppSearch {
    /// Matches as the user types toward "quit" / "quit roocast".
    nonisolated static func matchesQuitCommand(_ query: String) -> Bool {
        let lowered = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else { return false }
        return "quit".hasPrefix(lowered) || "quit roocast".hasPrefix(lowered)
    }

    /// Matches as the user types toward "update" / "check for updates" / "check updates".
    nonisolated static func matchesCheckForUpdatesCommand(_ query: String) -> Bool {
        matchesBuiltInCommand(
            query,
            phrases: ["update", "check for updates", "check updates"],
            aliases: []
        )
    }

    /// Matches as the user types toward "uninstall" / "uninstall roocast" / "remove roocast".
    ///
    /// `"remove roocast"` only matches once the query is at least 4 characters
    /// (`remo…`) so short prefixes like `"re"` / `"rem"` do not false-fire
    /// Uninstall ahead of Reasonable Size.
    nonisolated static func matchesUninstallCommand(_ query: String) -> Bool {
        let lowered = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else { return false }
        if matchesBuiltInCommand(
            lowered,
            phrases: ["uninstall", "uninstall roocast"],
            aliases: []
        ) {
            return true
        }
        // Require enough of "remove" so "re"/"rem" never match uninstall.
        guard lowered.count >= 4 else { return false }
        return "remove roocast".hasPrefix(lowered)
    }

    /// Matches as the user types toward "left" / "left half" / alias "lh".
    nonisolated static func matchesLeftHalfCommand(_ query: String) -> Bool {
        matchesWindowSnapCommand(
            query,
            phrases: ["left", "left half"],
            aliases: ["lh"]
        )
    }

    /// Matches as the user types toward "right" / "right half" / alias "rh".
    nonisolated static func matchesRightHalfCommand(_ query: String) -> Bool {
        matchesWindowSnapCommand(
            query,
            phrases: ["right", "right half"],
            aliases: ["rh"]
        )
    }

    /// Matches as the user types toward "max" / "maximize".
    /// Fills the current Space — not macOS fullscreen (another Space).
    nonisolated static func matchesMaximizeCommand(_ query: String) -> Bool {
        matchesWindowSnapCommand(
            query,
            phrases: ["max", "maximize"],
            aliases: ["max"]
        )
    }

    /// Matches as the user types toward "reasonable" / "reasonable size" / alias "rs".
    nonisolated static func matchesReasonableSizeCommand(_ query: String) -> Bool {
        matchesBuiltInCommand(
            query,
            phrases: ["reasonable", "reasonable size"],
            aliases: ["rs"]
        )
    }

    /// Matches as the user types toward "top" / "top half" / alias "th".
    nonisolated static func matchesTopHalfCommand(_ query: String) -> Bool {
        matchesWindowSnapCommand(
            query,
            phrases: ["top", "top half"],
            aliases: ["th"]
        )
    }

    /// Matches as the user types toward "bottom" / "bottom half" / alias "bh".
    nonisolated static func matchesBottomHalfCommand(_ query: String) -> Bool {
        matchesWindowSnapCommand(
            query,
            phrases: ["bottom", "bottom half"],
            aliases: ["bh"]
        )
    }

    /// Matches as the user types toward "first" / "first third" / alias "ft".
    nonisolated static func matchesFirstThirdCommand(_ query: String) -> Bool {
        matchesWindowSnapCommand(
            query,
            phrases: ["first", "first third", "third"],
            aliases: ["ft"]
        )
    }

    /// Matches as the user types toward "last two thirds" / alias "ltt".
    nonisolated static func matchesLastTwoThirdsCommand(_ query: String) -> Bool {
        matchesWindowSnapCommand(
            query,
            phrases: ["last two thirds", "last two", "two thirds"],
            aliases: ["ltt"]
        )
    }

    /// Matches as the user types toward "move to top" / "move top" / alias "mtt".
    nonisolated static func matchesMoveToTopCommand(_ query: String) -> Bool {
        matchesWindowSnapCommand(
            query,
            phrases: ["move to top", "move top"],
            aliases: ["mtt"]
        )
    }

    /// Matches as the user types toward "move to bottom" / "move bottom" / alias "mtb".
    nonisolated static func matchesMoveToBottomCommand(_ query: String) -> Bool {
        matchesWindowSnapCommand(
            query,
            phrases: ["move to bottom", "move bottom"],
            aliases: ["mtb"]
        )
    }

    /// Matches as the user types toward "move to left" / "move left" / alias "mtl".
    nonisolated static func matchesMoveToLeftCommand(_ query: String) -> Bool {
        matchesWindowSnapCommand(
            query,
            phrases: ["move to left", "move left"],
            aliases: ["mtl"]
        )
    }

    /// Matches as the user types toward "move to right" / "move right" / alias "mtr".
    nonisolated static func matchesMoveToRightCommand(_ query: String) -> Bool {
        matchesWindowSnapCommand(
            query,
            phrases: ["move to right", "move right"],
            aliases: ["mtr"]
        )
    }

    /// Prefix match on display phrases, or exact alias (e.g. `lh`).
    nonisolated private static func matchesBuiltInCommand(
        _ query: String,
        phrases: [String],
        aliases: [String]
    ) -> Bool {
        let lowered = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else { return false }
        if aliases.contains(lowered) { return true }
        return phrases.contains { $0.hasPrefix(lowered) }
    }

    /// Prefix match on display phrases, or exact alias (e.g. `lh`).
    nonisolated private static func matchesWindowSnapCommand(
        _ query: String,
        phrases: [String],
        aliases: [String]
    ) -> Bool {
        matchesBuiltInCommand(query, phrases: phrases, aliases: aliases)
    }

    /// Per-demote-level score penalty — large enough to sink below equal-intention peers.
    nonisolated static let demotePenaltyPerLevel = 50_000

    /// Built-in commands first (if matched, intention-scored), then apps + folders.
    ///
    /// Empty / whitespace query returns running-app switch suggestions (no folders/commands).
    ///
    /// - Parameter folders: Folder shortcut rows. Defaults to built-in shortcuts.
    ///   Pass stubs in unit tests to avoid disk icon lookup.
    /// - Parameter frontmostPath: Bundle path of the frontmost app to exclude from
    ///   empty-query switch suggestions. Ignored when the query is non-empty.
    /// - Parameter selfPath: Bundle path of Roocast itself — always excluded from
    ///   app rows (empty switch + typed search). Quit Roocast still matches as a command.
    /// - Parameter demoteLevels: Persisted Decrease Ranking levels keyed by `AppItem.id`.
    nonisolated static func results(
        query: String,
        apps: [AppItem],
        folders: [AppItem]? = nil,
        frontmostPath: String? = nil,
        selfPath: String? = nil,
        demoteLevels: [UUID: Int] = [:]
    ) -> [AppItem] {
        let appsExcludingSelf = excludingSelf(apps, selfPath: selfPath)
        let lowered = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lowered.isEmpty {
            return switchSuggestions(
                apps: appsExcludingSelf,
                frontmostPath: frontmostPath,
                selfPath: selfPath,
                demoteLevels: demoteLevels
            )
        }

        let folderItems = folders ?? FolderShortcut.builtIns.map { AppItem.folder($0) }

        var output: [AppItem] = []
        // Countdown / timer CLI leads when the query parses (`timer 5m`).
        if let countdown = Countdown.parse(query) {
            output.append(.countdown(countdown))
        }
        // Calculator leads when the raw query is a real expression (Tinycast-style).
        if let calc = Calculator.evaluate(query) {
            output.append(.calculator(calc))
        }

        var builtIns: [AppItem] = []
        if matchesQuitCommand(lowered) {
            builtIns.append(.quitRoocast)
        }
        if matchesUninstallCommand(lowered) {
            builtIns.append(.uninstallRoocast)
        }
        if matchesCheckForUpdatesCommand(lowered) {
            builtIns.append(.checkForUpdates)
        }
        if matchesLeftHalfCommand(lowered) {
            builtIns.append(.leftHalf)
        }
        if matchesRightHalfCommand(lowered) {
            builtIns.append(.rightHalf)
        }
        if matchesMaximizeCommand(lowered) {
            builtIns.append(.maximize)
        }
        if matchesReasonableSizeCommand(lowered) {
            builtIns.append(.reasonableSize)
        }
        if matchesTopHalfCommand(lowered) {
            builtIns.append(.topHalf)
        }
        if matchesBottomHalfCommand(lowered) {
            builtIns.append(.bottomHalf)
        }
        if matchesFirstThirdCommand(lowered) {
            builtIns.append(.firstThird)
        }
        if matchesLastTwoThirdsCommand(lowered) {
            builtIns.append(.lastTwoThirds)
        }
        if matchesMoveToTopCommand(lowered) {
            builtIns.append(.moveToTop)
        }
        if matchesMoveToBottomCommand(lowered) {
            builtIns.append(.moveToBottom)
        }
        if matchesMoveToLeftCommand(lowered) {
            builtIns.append(.moveToLeft)
        }
        if matchesMoveToRightCommand(lowered) {
            builtIns.append(.moveToRight)
        }
        output.append(contentsOf: rank(query: lowered, apps: builtIns, demoteLevels: demoteLevels))
        output.append(
            contentsOf: rank(
                query: lowered,
                apps: appsExcludingSelf + folderItems,
                demoteLevels: demoteLevels
            )
        )
        return output
    }

    /// Drop the launcher's own bundle from app rows (already open / not a switch target).
    nonisolated static func excludingSelf(_ apps: [AppItem], selfPath: String?) -> [AppItem] {
        guard let selfPath else { return apps }
        let selfCanon = AppIndex.canonicalPath(selfPath)
        return apps.filter { AppIndex.canonicalPath($0.path) != selfCanon }
    }

    /// Rank items by intention score (prefix > mid-string); ties break by name.
    /// Demote levels subtract `demotePenaltyPerLevel` each so user-demoted rows sink.
    nonisolated static func rank(
        query: String,
        apps: [AppItem],
        demoteLevels: [UUID: Int] = [:]
    ) -> [AppItem] {
        let lowered = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else { return [] }

        return apps
            .compactMap { app -> (AppItem, Int)? in
                let base = IntentionScore.score(query: lowered, app: app)
                guard base > 0 else { return nil }
                let demote = max(0, demoteLevels[app.id] ?? 0)
                // Penalty may go negative — item still appears; sort sinks it.
                return (app, base - demote * demotePenaltyPerLevel)
            }
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
        selfPath: String? = nil,
        demoteLevels: [UUID: Int] = [:]
    ) -> [AppItem] {
        apps
            .compactMap { app -> (AppItem, Int)? in
                let base = IntentionScore.switchScore(
                    app: app,
                    frontmostPath: frontmostPath,
                    selfPath: selfPath
                )
                guard base > 0 else { return nil }
                let demote = max(0, demoteLevels[app.id] ?? 0)
                return (app, base - demote * demotePenaltyPerLevel)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
            }
            .map(\.0)
    }
}
