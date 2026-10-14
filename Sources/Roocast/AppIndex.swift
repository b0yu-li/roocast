import SwiftUI
import AppKit

struct AppItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let path: String
    let icon: NSImage?
    let isRunning: Bool
    let profile: String?  // Profile name for multi-instance apps (e.g., Firefox)

    init(url: URL, isRunning: Bool = false, profile: String? = nil) {
        self.id = UUID()
        self.name = url.deletingPathExtension().lastPathComponent
        self.path = url.path
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
        self.icon?.size = NSSize(width: 32, height: 32)
        self.isRunning = isRunning
        self.profile = profile
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

    init() {
        indexApps()
    }

    func indexApps() {
        let found = Self.scanApps()
        self.apps = found
    }

    private static func scanApps() -> [AppItem] {
        var found: [AppItem] = []
        
        // Get list of running app bundle paths
        let runningApps = NSWorkspace.shared.runningApplications
        let runningBundlePaths = Set(runningApps.compactMap { $0.bundleURL?.path })
        
        // Detect Firefox profiles
        let firefoxProfiles = ProfileManager.detectFirefoxProfiles()
        let runningFirefoxProfiles = ProfileManager.detectRunningProfiles()

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
                    if fileURL.lastPathComponent == "Firefox.app" && !firefoxProfiles.isEmpty {
                        // Create separate AppItem for each profile
                        for profile in firefoxProfiles {
                            let profileIsRunning = runningFirefoxProfiles[profile.name] != nil
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
        guard !query.isEmpty else { return [] }
        let lowered = query.lowercased()
        return apps.filter { app in
            app.searchText.lowercased().contains(lowered)
        }
    }
}
