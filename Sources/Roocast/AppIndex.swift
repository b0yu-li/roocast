import SwiftUI
import AppKit

@MainActor
final class AppIndex: ObservableObject {
    /// Readable so the UI can refresh arrow bounds when indexing finishes (empty summon).
    @Published private(set) var apps: [AppItem] = []
    /// Latest zoxide folder row for the active `z <keywords>` query (async; never from body).
    @Published private(set) var zoxideItem: AppItem? = nil
    /// Coalesce overlapping refreshes (init + panel-show) so flock probes never race.
    private var isIndexing = false
    private var needsReindex = false
    /// Cancels in-flight `zoxide query` when the user keeps typing (`z abc` → `z abcd`).
    private var zoxideTask: Task<Void, Never>?
    private var zoxideGeneration = 0
    /// Keywords key that `zoxideItem` (or a confirmed miss) corresponds to.
    private var zoxideKey: String?

    init() {
        // Index off the critical path so panel creation never blocks on disk I/O.
        Task { await indexApps() }
    }

    func indexApps() async {
        if isIndexing {
            // Coalesce with the in-flight scan, then wait so callers (e.g. empty-summon
            // sync) don't run against a still-empty index.
            needsReindex = true
            while isIndexing {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            return
        }
        isIndexing = true
        defer { isIndexing = false }

        // Publish once after coalesced scans — intermediate assigns made the switch list jump.
        var latest: [AppItem] = []
        repeat {
            needsReindex = false
            latest = await Task.detached(priority: .userInitiated) {
                Self.scanApps()
            }.value
        } while needsReindex
        publishApps(latest)
    }

    /// Skip no-op publishes so SwiftUI does not reshuffle an unchanged switch list.
    private func publishApps(_ found: [AppItem]) {
        if apps.count == found.count,
           zip(apps, found).allSatisfy({
               $0.id == $1.id && $0.isRunning == $1.isRunning && $0.profile == $1.profile
           }) {
            return
        }
        apps = found
    }

    private nonisolated static func scanApps() -> [AppItem] {
        var found: [AppItem] = []
        
        // Only `.regular` apps count as running for indicators / switch suggestions.
        // Background agents (e.g. Books with `.prohibited`) stay in the process list
        // without a switchable UI; accessory apps (Roocast) are not switch targets.
        let runningBundlePaths = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { $0.bundleURL?.path }
        )
        
        // Detect Firefox profiles once; running state uses the same list (no double detect).
        let firefoxProfiles = ProfileManager.detectFirefoxProfiles()
        let runningFirefoxProfiles = ProfileManager.detectRunningProfiles(among: firefoxProfiles)
        var emittedFirefox = false

        let searchPaths = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]

        for baseURL in searchPaths {
            guard let enumerator = FileManager.default.enumerator(
                at: baseURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.pathExtension == "app" {
                    let isRunning = runningBundlePaths.contains(fileURL.path)
                    
                    // Check if this is Firefox with profiles
                    if fileURL.lastPathComponent == "Firefox.app", !firefoxProfiles.isEmpty {
                        // One Firefox.app on disk is enough — avoid duplicating profile rows
                        // if the bundle appears under multiple search roots.
                        guard !emittedFirefox else { continue }
                        emittedFirefox = true
                        for profile in firefoxProfiles {
                            // Defense in depth: never list stub folders (no prefs, not running).
                            let profileIsRunning = runningFirefoxProfiles[profile.name] != nil
                            guard ProfileManager.hasPrefsJS(at: profile.path) || profileIsRunning else {
                                continue
                            }
                            found.append(AppItem(
                                url: fileURL,
                                isRunning: profileIsRunning,
                                profile: profile.name
                            ))
                        }
                    } else {
                        found.append(AppItem(url: fileURL, isRunning: isRunning))
                    }
                }
            }
        }

        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func search(_ query: String) -> [AppItem] {
        // Zoxide mode: never spawn a process here — `filteredApps` runs during SwiftUI
        // body/layout. Sync `Process.waitUntilExit` nested the run loop and aborted
        // AttributeGraph (see Roocast-2026-10-22-110706.ips). Results come from
        // `scheduleZoxide(for:)` → `@Published zoxideItem`.
        if let keywords = Zoxide.keywords(from: query) {
            let key = Self.makeZoxideKey(keywords)
            if let item = zoxideItem, zoxideKey == key {
                return [item]
            }
            return []
        }

        // Nonactivating panel keeps the prior app frontmost — use it to drop
        // the app the user is already in from empty-query switch suggestions.
        let frontmostPath = NSWorkspace.shared.frontmostApplication?.bundleURL?.path
        return AppSearch.results(
            query: query,
            apps: apps,
            frontmostPath: frontmostPath,
            selfPath: Bundle.main.bundlePath
        )
    }

    /// Kick off / cancel zoxide CLI work as the query changes. Safe to call from
    /// `onChange(of: query)` — never from a View body computed property.
    func scheduleZoxide(for query: String) {
        guard let keywords = Zoxide.keywords(from: query) else {
            clearZoxide()
            return
        }
        let key = Self.makeZoxideKey(keywords)
        // Already have a settled answer for this exact keyword set.
        if zoxideKey == key { return }

        // Drop the previous row so we never show a stale folder for a newer query.
        if zoxideItem != nil {
            zoxideItem = nil
        }
        zoxideKey = nil
        zoxideTask?.cancel()
        zoxideGeneration += 1
        let generation = zoxideGeneration
        FocusRestorer.log("zoxide: query gen=\(generation) \(keywords.joined(separator: " "))")

        zoxideTask = Task { [weak self] in
            let path = await Task.detached(priority: .userInitiated) {
                Zoxide.bestMatch(keywords: keywords)
            }.value
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, generation == self.zoxideGeneration else { return }
                if let path {
                    self.zoxideItem = AppItem.zoxide(path: path)
                    self.zoxideKey = key
                    FocusRestorer.log("zoxide: match gen=\(generation) \(path)")
                } else {
                    self.zoxideItem = nil
                    self.zoxideKey = key
                    FocusRestorer.log("zoxide: no match gen=\(generation)")
                }
            }
        }
    }

    private func clearZoxide() {
        zoxideTask?.cancel()
        zoxideTask = nil
        zoxideGeneration += 1
        guard zoxideItem != nil || zoxideKey != nil else { return }
        zoxideItem = nil
        zoxideKey = nil
    }

    private nonisolated static func makeZoxideKey(_ keywords: [String]) -> String {
        keywords.joined(separator: "\u{1f}")
    }

    /// Matches as the user types toward "quit" / "quit roocast".
    nonisolated static func matchesQuitCommand(_ query: String) -> Bool {
        AppSearch.matchesQuitCommand(query)
    }
}
