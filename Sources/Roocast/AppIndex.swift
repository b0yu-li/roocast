import SwiftUI
import AppKit

@MainActor
final class AppIndex: ObservableObject {
    /// Readable so the UI can refresh arrow bounds when indexing finishes (empty summon).
    @Published private(set) var apps: [AppItem] = []
    /// Coalesce overlapping refreshes (init + panel-show) so flock probes never race.
    private var isIndexing = false
    private var needsReindex = false

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

    /// Matches as the user types toward "quit" / "quit roocast".
    nonisolated static func matchesQuitCommand(_ query: String) -> Bool {
        AppSearch.matchesQuitCommand(query)
    }
}
