import Foundation

/// Raycast-style lockable launcher verbs (v1: timer / countdown only).
enum CommandLock {
    struct Command: Equatable, Sendable {
        let verb: String
        /// Ghost placeholder shown after the chip (duration examples).
        let argumentPlaceholder: String
    }

    /// Built-in lockable commands.
    static let registry: [Command] = [
        Command(verb: "timer", argumentPlaceholder: "5m · 1h30m · 90s"),
        Command(verb: "countdown", argumentPlaceholder: "5m · 1h30m · 90s"),
    ]

    /// Exact verb match (case-insensitive), or `nil`.
    nonisolated static func command(forVerb verb: String) -> Command? {
        let lowered = verb.lowercased()
        return registry.first { $0.verb == lowered }
    }

    /// When `token` uniquely prefixes exactly one registry verb, return that command.
    /// `tim` → timer; `c` → nil (ambiguous with nothing else starting with c alone —
    /// countdown is the only `c*` verb, so `c` / `coun` → countdown).
    nonisolated static func uniqueCompletion(forToken token: String) -> Command? {
        let lowered = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else { return nil }
        let matches = registry.filter { $0.verb.hasPrefix(lowered) }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    /// Attempt to lock from a free-text query (`tim`, `timer`, `timer 2h`).
    /// Returns verb + remaining argument text when Tab/→ can lock.
    nonisolated static func lockAttempt(from query: String) -> (verb: String, argument: String)? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let first = parts.first else { return nil }

        // Already the full verb (with optional args).
        if let cmd = command(forVerb: first) {
            let argument = parts.dropFirst().joined(separator: " ")
            return (cmd.verb, argument)
        }

        // Unique prefix of the first token only (no args yet), e.g. `tim`.
        guard parts.count == 1, let cmd = uniqueCompletion(forToken: first) else {
            return nil
        }
        return (cmd.verb, "")
    }

    /// Compose the query AppSearch / Countdown.parse expect.
    nonisolated static func composedQuery(verb: String, argument: String) -> String {
        let arg = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        if arg.isEmpty { return verb }
        return "\(verb) \(arg)"
    }
}
