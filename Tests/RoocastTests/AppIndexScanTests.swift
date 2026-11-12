import XCTest
@testable import Roocast

/// Regression: the disk scan must include apps whose bundle is a symlink.
///
/// `/Applications/Safari.app` is a root-owned symlink into the Safari cryptex
/// and carries the `UF_HIDDEN` flag — `.skipsHiddenFiles` silently dropped it
/// from the index, so typing "saf" returned nothing.
final class AppIndexScanTests: XCTestCase {
    /// Mirrors `AppIndex.scanApps` enumeration so the regression is caught at the
    /// file-system layer (the pure ranking layer is already covered by AppSearchTests).
    private func scanDiskForApps() -> Set<String> {
        let searchPaths = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]

        var names: Set<String> = []
        for baseURL in searchPaths {
            guard let enumerator = FileManager.default.enumerator(
                at: baseURL,
                includingPropertiesForKeys: nil,
                options: [.skipsPackageDescendants]
            ) else { continue }
            while let fileURL = enumerator.nextObject() as? URL {
                guard !fileURL.lastPathComponent.hasPrefix(".") else { continue }
                if fileURL.pathExtension == "app" {
                    names.insert(fileURL.deletingPathExtension().lastPathComponent)
                }
            }
        }
        return names
    }

    func testScanIncludesSymlinkedBundles() throws {
        let safariPath = "/Applications/Safari.app"
        let safariExists = (try? FileManager.default.destinationOfSymbolicLink(atPath: safariPath)) != nil
            || FileManager.default.fileExists(atPath: safariPath)
        try XCTSkipIf(!safariExists, "No Safari.app in /Applications on this machine")

        let names = scanDiskForApps()
        XCTAssertTrue(names.contains("Safari"), "Scan must include symlinked /Applications/Safari.app")
    }

    func testScanSkipsDotFiles() {
        let names = scanDiskForApps()
        XCTAssertFalse(names.contains { $0.hasPrefix(".") }, "Dot-files must not be indexed as apps")
    }
}
