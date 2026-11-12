import XCTest
@testable import Roocast

/// Regression: the running-indicator path match must survive symlinked bundles.
///
/// The running Safari announces `/System/Volumes/Preboot/Cryptexes/App/System/
/// Applications/Safari.app` while the index holds the `/Applications/Safari.app`
/// symlink — exact string comparison never matched, so the open dot never showed.
final class AppIndexCanonicalPathTests: XCTestCase {
    func testCanonicalPathResolvesSafariCryptexSymlink() throws {
        let symlinkPath = "/Applications/Safari.app"
        let cryptexPath = "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"
        let cryptexExists = FileManager.default.fileExists(atPath: cryptexPath)
        let symlinkExists = (try? FileManager.default.destinationOfSymbolicLink(atPath: symlinkPath)) != nil
        try XCTSkipIf(!(cryptexExists && symlinkExists), "No Safari cryptex layout on this machine")

        XCTAssertEqual(
            AppIndex.canonicalPath(symlinkPath),
            AppIndex.canonicalPath(cryptexPath),
            "Indexed symlink path and running-app cryptex path must canonicalize to the same path"
        )
    }

    func testCanonicalPathIsStableForPlainPaths() {
        // Non-symlinked paths must survive canonicalization unchanged (firmlink /private prefix aside).
        XCTAssertEqual(
            AppIndex.canonicalPath("/Applications/Firefox.app"),
            URL(fileURLWithPath: "/Applications/Firefox.app").resolvingSymlinksInPath().path
        )
    }
}
