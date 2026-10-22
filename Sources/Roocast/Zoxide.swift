import Foundation

/// Thin wrapper around the `zoxide` CLI for frecent directory jumps.
///
/// Trigger in the launcher: type `z <keywords>` (e.g. `z downloads`). Roocast runs
/// `zoxide query <keywords>` and opens the best match in Finder.
///
/// Process spawn must stay off SwiftUI body / `AppIndex.search` — only from
/// `AppIndex.scheduleZoxide(for:)` on a detached task. Sync `waitUntilExit` during
/// layout nested the run loop and aborted AttributeGraph. Typical CLI latency ~6–8ms.
enum Zoxide {
    /// `(executable, arguments) -> (exitStatus, stdout, stderr)`
    typealias Runner = (String, [String]) -> (status: Int32, stdout: String, stderr: String)

    /// Common install locations — GUI apps often lack Homebrew on `PATH`.
    nonisolated static let candidateExecutables: [String] = [
        "/opt/homebrew/bin/zoxide",
        "/usr/local/bin/zoxide",
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/zoxide",
    ]

    /// Keywords after a `z ` prefix, or `nil` when the query is not zoxide mode.
    ///
    /// Requires at least one non-empty keyword so bare `z` / `z ` does not steal
    /// normal app search (e.g. Zoom) or dump the entire frecent list.
    nonisolated static func keywords(from query: String) -> [String]? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        let lowered = trimmed.lowercased()
        guard lowered.hasPrefix("z") else { return nil }
        let afterZ = trimmed.dropFirst()
        guard let first = afterZ.first, first.isWhitespace else { return nil }
        let rest = afterZ.drop(while: { $0.isWhitespace })
        let parts = rest.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !parts.isEmpty else { return nil }
        return parts
    }

    /// Best frecent match for `keywords`, or `nil` when zoxide is missing / no match.
    ///
    /// Bare `~` is a Roocast shortcut to `$HOME` — `zoxide query ~` does not expand tilde.
    nonisolated static func bestMatch(
        keywords: [String],
        executable: String? = nil,
        run: Runner = { executable, arguments in runProcess(executable, arguments) }
    ) -> String? {
        guard !keywords.isEmpty else { return nil }
        if keywords == ["~"] {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        guard let exe = executable ?? resolveExecutable() else { return nil }

        let result = run(exe, ["query"] + keywords)
        guard result.status == 0 else { return nil }
        let path = result.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)
        guard let path, !path.isEmpty else { return nil }
        return path
    }

    /// Shorten `$HOME` prefix to `~` for quiet path labels in the result row.
    nonisolated static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    nonisolated static func resolveExecutable() -> String? {
        let fm = FileManager.default
        for path in candidateExecutables where fm.isExecutableFile(atPath: path) {
            return path
        }
        // Fall back to PATH (useful when launched from a configured shell).
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let candidate = "\(dir)/zoxide"
                if fm.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    nonisolated private static func runProcess(
        _ executable: String,
        _ arguments: [String]
    ) -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        // Inherit env so `_ZO_DATA_DIR` / HOME resolve the same DB as the user's shell.
        process.environment = ProcessInfo.processInfo.environment
        process.standardInput = FileHandle.nullDevice

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return (status: -1, stdout: "", stderr: error.localizedDescription)
        }
        process.waitUntilExit()

        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
