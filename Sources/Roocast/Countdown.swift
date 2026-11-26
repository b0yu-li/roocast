import Foundation

/// CLI-style ad-hoc countdown: `timer 5m` / `countdown 90s` / `timer 1h30m`.
enum Countdown {
    struct Spec: Equatable {
        /// Whole seconds to count down (≥ 1).
        let seconds: Int
        /// Display for the lead row / island (`5:00`, `1:30:00`).
        let display: String
    }

    /// Lead row for the launcher: ready to start, or verb recognized but needs a duration.
    enum Lead: Equatable {
        case ready(Spec)
        /// Verb matched (`timer` / `countdown`) but duration missing or invalid.
        case needsDuration(verb: String)
    }

    /// Parse a launcher query into a countdown lead (ready or hint).
    /// Returns `nil` when this is not timer/countdown mode (fall through to search).
    ///
    /// Matches the full verb (`timer`) **or** a unique Tab-lock prefix (`tim` / `time`),
    /// so the lead row appears as soon as the command is unambiguous.
    nonisolated static func lead(for query: String) -> Lead? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let first = parts.first else { return nil }
        let lowered = first.lowercased()

        let verb: String
        if lowered == "timer" || lowered == "countdown" {
            verb = lowered
        } else if let cmd = CommandLock.uniqueCompletion(forToken: lowered) {
            // Same uniqueness rule as Tab-lock (`time` → timer).
            verb = cmd.verb
        } else {
            return nil
        }

        if parts.count >= 2 {
            let durationToken = parts.dropFirst().joined()
            if let seconds = parseDuration(durationToken), seconds >= 1 {
                return .ready(Spec(seconds: seconds, display: format(seconds: seconds)))
            }
            // Verb + junk / incomplete duration — still show the timer entry.
            return .needsDuration(verb: verb)
        }
        return .needsDuration(verb: verb)
    }

    /// Ready-to-start parse only (`timer 5m`). Prefer `lead(for:)` for search UI.
    nonisolated static func parse(_ query: String) -> Spec? {
        if case .ready(let spec) = lead(for: query) { return spec }
        return nil
    }

    /// `5m`, `90s`, `1h`, `1h30m`, bare `25` (= 25 minutes).
    nonisolated static func parseDuration(_ token: String) -> Int? {
        let lowered = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else { return nil }

        if lowered.allSatisfy(\.isNumber) {
            guard let minutes = Int(lowered), minutes >= 1 else { return nil }
            return minutes * 60
        }

        var total = 0
        var number = 0
        var sawUnit = false
        for ch in lowered {
            if ch.isNumber {
                number = number * 10 + (Int(String(ch)) ?? 0)
                continue
            }
            let multiplier: Int
            switch ch {
            case "h": multiplier = 3600
            case "m": multiplier = 60
            case "s": multiplier = 1
            default: return nil
            }
            // Require a number before each unit (`m` alone is invalid).
            guard number > 0 || sawUnit else { return nil }
            if number == 0 { return nil }
            total += number * multiplier
            number = 0
            sawUnit = true
        }
        // Trailing digits without a unit are invalid when units were used (`1h30`).
        guard number == 0, sawUnit, total >= 1 else { return nil }
        return total
    }

    nonisolated static func format(seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%d:%02d", m, sec)
    }
}
