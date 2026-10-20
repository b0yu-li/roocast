import SwiftUI
import AppKit

struct AppItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case app
        case quit
    }

    let id: UUID
    let name: String
    let path: String
    let icon: NSImage?
    let isRunning: Bool
    let profile: String?  // Profile name for multi-instance apps (e.g., Firefox)
    let kind: Kind

    init(url: URL, isRunning: Bool = false, profile: String? = nil) {
        self.id = UUID()
        self.name = url.deletingPathExtension().lastPathComponent
        self.path = url.path
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
        self.icon?.size = NSSize(width: 32, height: 32)
        self.isRunning = isRunning
        self.profile = profile
        self.kind = .app
    }

    private init(
        id: UUID,
        name: String,
        path: String,
        icon: NSImage?,
        isRunning: Bool,
        profile: String?,
        kind: Kind
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.icon = icon
        self.isRunning = isRunning
        self.profile = profile
        self.kind = kind
    }

    /// Built-in command: quit the Roocast process. Stable id so list selection stays stable.
    static let quitRoocast: AppItem = {
        let icon = NSImage(
            systemSymbolName: "power.circle.fill",
            accessibilityDescription: "Quit Roocast"
        )
        icon?.size = NSSize(width: 32, height: 32)
        return AppItem(
            id: UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!,
            name: "Quit Roocast",
            path: "Command",
            icon: icon,
            isRunning: false,
            profile: nil,
            kind: .quit
        )
    }()

    /// Lightweight item for unit tests / ranking — no disk icon lookup.
    static func stub(
        name: String,
        profile: String? = nil,
        path: String = "/Applications/Stub.app",
        isRunning: Bool = false
    ) -> AppItem {
        AppItem(
            id: UUID(),
            name: name,
            path: path,
            icon: nil,
            isRunning: isRunning,
            profile: profile,
            kind: .app
        )
    }

    // Searchable text includes profile name
    var searchText: String {
        if let profile = profile {
            return "\(name) \(profile)"
        }
        return name
    }
}

@MainActor
final class AppIndex: ObservableObject {
    @Published private var apps: [AppItem] = []
    /// Coalesce overlapping refreshes (init + panel-show) so flock probes never race.
    private var isIndexing = false
    private var needsReindex = false

    init() {
        // Index off the critical path so panel creation never blocks on disk I/O.
        Task { await indexApps() }
    }

    func indexApps() async {
        if isIndexing {
            needsReindex = true
            return
        }
        isIndexing = true
        defer { isIndexing = false }

        repeat {
            needsReindex = false
            let found = await Task.detached(priority: .userInitiated) {
                Self.scanApps()
            }.value
            self.apps = found
        } while needsReindex
    }

    private nonisolated static func scanApps() -> [AppItem] {
        var found: [AppItem] = []
        
        // Get list of running app bundle paths
        let runningApps = NSWorkspace.shared.runningApplications
        let runningBundlePaths = Set(runningApps.compactMap { $0.bundleURL?.path })
        
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
        AppSearch.results(query: query, apps: apps)
    }

    /// Matches as the user types toward "quit" / "quit roocast".
    nonisolated static func matchesQuitCommand(_ query: String) -> Bool {
        AppSearch.matchesQuitCommand(query)
    }
}
