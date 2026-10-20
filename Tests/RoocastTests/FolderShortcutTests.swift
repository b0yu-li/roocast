import XCTest
@testable import Roocast

final class FolderShortcutTests: XCTestCase {

    func testDownloadsPathIsHomeDownloads() {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
        XCTAssertEqual(FolderShortcut.downloads.path, expected)
        XCTAssertEqual(FolderShortcut.downloads.name, "Downloads")
    }

    func testBuiltInsContainsOnlyDownloads() {
        XCTAssertEqual(FolderShortcut.builtIns.map(\.name), ["Downloads"])
        XCTAssertEqual(FolderShortcut.builtIns.first?.id, FolderShortcut.downloads.id)
    }

    func testDownloadsIdIsStable() {
        XCTAssertEqual(
            FolderShortcut.downloads.id,
            UUID(uuidString: "B2C3D4E5-F6A7-8901-BCDE-F12345678901")
        )
    }

    func testSearchTextIncludesAliases() {
        XCTAssertEqual(FolderShortcut.downloads.searchText, "Downloads dl")
    }

    func testAppItemFolderMapsShortcut() {
        let item = AppItem.folder(.downloads)
        XCTAssertEqual(item.kind, .folder)
        XCTAssertEqual(item.id, FolderShortcut.downloads.id)
        XCTAssertEqual(item.name, "Downloads")
        XCTAssertEqual(item.path, FolderShortcut.downloads.path.path)
        XCTAssertEqual(item.aliases, ["dl"])
        XCTAssertFalse(item.isRunning)
        XCTAssertNil(item.profile)
        XCTAssertEqual(item.searchText, "Downloads dl")
    }
}
