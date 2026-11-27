import Foundation

/// On-device launcher usage — Tinycast-style frecency + search terms.
///
/// Application Support JSON only. Never phones home (AGENTS.md).
@MainActor
final class UsageRankingStore: ObservableObject {
    nonisolated static var defaultFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Application Support/Roocast", isDirectory: true)
            .appendingPathComponent("launcher-usage.json", isDirectory: false)
    }

    private let fileURL: URL
    private let now: () -> Date

    /// Published so SwiftUI re-runs search after a visit.
    @Published private(set) var revision: UInt64 = 0

    private(set) var visits: [String: UsageVisit]
    private var writeTask: Task<Void, Never>?

    init(fileURL: URL = UsageRankingStore.defaultFileURL, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = now
        let decoded =
            (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String: UsageVisit].self, from: $0) } ?? [:]
        visits = UsageRanking.live(decoded, at: now())
    }

    var isEmpty: Bool { visits.isEmpty }

    /// Await pending persist (tests / flush before reload).
    func flush() async {
        await writeTask?.value
    }

    /// Record an activation. `query` nil when empty-summon / no typed search.
    func visit(itemKey: String, query: String?) {
        guard !itemKey.isEmpty else { return }
        let timestamp = now()
        let previous = visits[itemKey]
        visits[itemKey] = UsageRanking.applyingVisit(
            previous: previous,
            query: query,
            at: timestamp
        )
        let signals = UsageRanking.signals(of: visits[itemKey], at: timestamp)
        FocusRestorer.log(
            "usage: visit key=\(itemKey.prefix(8))… qLen=\(query?.count ?? 0) frecency=\(String(format: "%.1f", signals.frecency))"
        )
        didMutate()
    }

    func visit(itemID: UUID, query: String?) {
        visit(itemKey: itemID.uuidString, query: query)
    }

    func snapshot() -> Snapshot {
        Snapshot(visits: visits, now: now())
    }

    struct Snapshot: Sendable {
        let visits: [String: UsageVisit]
        let now: Date

        func usage(for itemKey: String) -> UsageSignals {
            UsageRanking.signals(of: visits[itemKey], at: now)
        }

        func usage(for itemID: UUID) -> UsageSignals {
            usage(for: itemID.uuidString)
        }
    }

    func reset(itemKey: String) {
        guard visits.removeValue(forKey: itemKey) != nil else { return }
        didMutate()
    }

    func resetAll() {
        guard !visits.isEmpty else { return }
        visits = [:]
        didMutate()
    }

    private func didMutate() {
        revision &+= 1
        let snapshot = visits
        let fileURL = fileURL
        let previous = writeTask
        writeTask = Task.detached(priority: .utility) {
            await previous?.value
            let directory = fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
