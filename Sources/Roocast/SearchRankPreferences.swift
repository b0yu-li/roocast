import Foundation

/// Persisted Decrease Ranking levels for launcher search rows.
///
/// Stored as plain JSON under Application Support (same tree uninstall cleans).
/// Keys are `AppItem.id` UUID strings; values are demote levels (≥ 1).
@MainActor
final class SearchRankPreferences: ObservableObject {
    /// Published so SwiftUI re-runs `filteredApps` after demote/reset.
    @Published private(set) var demoteLevels: [UUID: Int] = [:]

    private let fileURL: URL

    /// Default on-disk path under Application Support.
    nonisolated static var defaultFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Application Support/Roocast", isDirectory: true)
            .appendingPathComponent("search-rank-preferences.json", isDirectory: false)
    }

    init(fileURL: URL = SearchRankPreferences.defaultFileURL) {
        self.fileURL = fileURL
        demoteLevels = Self.load(from: fileURL)
    }

    func level(for id: UUID) -> Int {
        demoteLevels[id] ?? 0
    }

    func isDemoted(_ id: UUID) -> Bool {
        level(for: id) > 0
    }

    /// Raycast-style Decrease Ranking — bumps the penalty one level.
    func decreaseRanking(for id: UUID) {
        demoteLevels[id] = level(for: id) + 1
        persist()
    }

    /// Clears any demote levels for this id.
    func resetRanking(for id: UUID) {
        guard demoteLevels[id] != nil else { return }
        demoteLevels.removeValue(forKey: id)
        persist()
    }

    private func persist() {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let payload = Payload(
                demoteLevels: Dictionary(
                    uniqueKeysWithValues: demoteLevels.map { ($0.key.uuidString, $0.value) }
                )
            )
            let data = try JSONEncoder().encode(payload)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Ranking prefs are best-effort — never crash the launcher.
            FocusRestorer.log("search-rank: failed to persist \(error.localizedDescription)")
        }
    }

    nonisolated private static func load(from url: URL) -> [UUID: Int] {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return [:]
        }
        var result: [UUID: Int] = [:]
        for (key, value) in payload.demoteLevels where value > 0 {
            guard let id = UUID(uuidString: key) else { continue }
            result[id] = value
        }
        return result
    }

    private struct Payload: Codable {
        var demoteLevels: [String: Int]
    }
}
