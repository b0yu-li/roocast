import XCTest
@testable import Roocast

/// Regression: the disk scan must include apps whose bundle is a symlink,
/// plus Finder (CoreServices sibling) and Simulator (inside Xcode.app).
///
/// `/Applications/Safari.app` is a root-owned symlink into the Safari cryptex
/// and carries the `UF_HIDDEN` flag — `.skipsHiddenFiles` silently dropped it
/// from the index, so typing "saf" returned nothing.
final class AppIndexScanTests: XCTestCase {
    /// Mirrors `AppIndex.scanApps` enumeration so the regression is caught at the
    /// file-system layer (the pure ranking layer is already covered by AppSearchTests).
    private func scanDiskForApps() -> Set<String> {
        var names: Set<String> = []
        for baseURL in AppIndex.applicationSearchRoots {
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
        for bundleURL in AppIndex.extraApplicationBundles
        where FileManager.default.fileExists(atPath: bundleURL.path) {
            names.insert(bundleURL.deletingPathExtension().lastPathComponent)
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

    func testScanIncludesFinder() throws {
        let finder = "/System/Library/CoreServices/Finder.app"
        try XCTSkipIf(
            !FileManager.default.fileExists(atPath: finder),
            "No Finder.app on this machine"
        )
        let names = scanDiskForApps()
        XCTAssertTrue(
            names.contains("Finder"),
            "Scan must include /System/Library/CoreServices/Finder.app"
        )
    }

    func testScanIncludesSimulator() throws {
        let simulator =
            "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app"
        try XCTSkipIf(
            !FileManager.default.fileExists(atPath: simulator),
            "No Simulator.app under Xcode on this machine"
        )
        let names = scanDiskForApps()
        XCTAssertTrue(
            names.contains("Simulator"),
            "Scan must include Simulator inside Xcode Developer Applications"
        )
    }

    func testScanSkipsDotFiles() {
        let names = scanDiskForApps()
        XCTAssertFalse(names.contains { $0.hasPrefix(".") }, "Dot-files must not be indexed as apps")
    }
}
