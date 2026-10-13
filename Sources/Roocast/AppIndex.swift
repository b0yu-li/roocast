import SwiftUI
import AppKit

struct AppItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let path: String
    let icon: NSImage?

    init(url: URL) {
        self.id = UUID()
        self.name = url.deletingPathExtension().lastPathComponent
        self.path = url.path
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
        self.icon?.size = NSSize(width: 32, height: 32)
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
                    found.append(AppItem(url: fileURL))
                }
            }
        }

        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func search(_ query: String) -> [AppItem] {
        guard !query.isEmpty else { return [] }
        let lowered = query.lowercased()
        return apps.filter { app in
            app.name.lowercased().contains(lowered)
        }
    }
}
