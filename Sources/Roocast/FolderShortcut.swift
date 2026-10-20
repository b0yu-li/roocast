import Foundation

/// A named directory the launcher can open in Finder.
///
/// Built-ins live in `builtIns`; v1 ships Downloads only. Add Desktop/Documents
/// (or custom paths later) as more static entries without changing search/UI.
struct FolderShortcut: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let path: URL
    let aliases: [String]
    let systemSymbolName: String

    var searchText: String {
        ([name] + aliases).joined(separator: " ")
    }

    static let downloads: FolderShortcut = FolderShortcut(
        id: UUID(uuidString: "B2C3D4E5-F6A7-8901-BCDE-F12345678901")!,
        name: "Downloads",
        path: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true),
        aliases: ["dl"],
        systemSymbolName: "arrow.down.circle.fill"
    )

    static let builtIns: [FolderShortcut] = [.downloads]
}
