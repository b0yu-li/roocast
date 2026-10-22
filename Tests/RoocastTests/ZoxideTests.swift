import XCTest
@testable import Roocast

final class ZoxideTests: XCTestCase {

    func testKeywordsRequiresZSpaceAndToken() {
        XCTAssertNil(Zoxide.keywords(from: ""))
        XCTAssertNil(Zoxide.keywords(from: "z"))
        XCTAssertNil(Zoxide.keywords(from: "Z"))
        XCTAssertNil(Zoxide.keywords(from: "z "))
        XCTAssertNil(Zoxide.keywords(from: "zoom"))
        XCTAssertNil(Zoxide.keywords(from: "zdownloads"))
        XCTAssertEqual(Zoxide.keywords(from: "z downloads"), ["downloads"])
        XCTAssertEqual(Zoxide.keywords(from: "z ~"), ["~"])
        XCTAssertEqual(Zoxide.keywords(from: "Z Down Loads"), ["Down", "Loads"])
        XCTAssertEqual(Zoxide.keywords(from: "  z   foo  bar  "), ["foo", "bar"])
    }

    func testBestMatchTildeIsHomeWithoutCLI() {
        final class Capture: @unchecked Sendable {
            var called = false
        }
        let capture = Capture()
        let path = Zoxide.bestMatch(
            keywords: ["~"],
            executable: "/fake/zoxide",
            run: { _, _ in
                capture.called = true
                return (status: 1, stdout: "", stderr: "should not run")
            }
        )
        XCTAssertEqual(path, FileManager.default.homeDirectoryForCurrentUser.path)
        XCTAssertFalse(capture.called)
    }

    func testBestMatchUsesQueryArgsAndParsesStdout() {
        final class Capture: @unchecked Sendable {
            var executable: String?
            var args: [String]?
        }
        let capture = Capture()
        let path = Zoxide.bestMatch(
            keywords: ["downloads"],
            executable: "/fake/zoxide",
            run: { exe, args in
                capture.executable = exe
                capture.args = args
                return (status: 0, stdout: "/Users/test/Downloads\n", stderr: "")
            }
        )
        XCTAssertEqual(path, "/Users/test/Downloads")
        XCTAssertEqual(capture.executable, "/fake/zoxide")
        XCTAssertEqual(capture.args, ["query", "downloads"])
    }

    func testBestMatchReturnsNilOnFailure() {
        XCTAssertNil(
            Zoxide.bestMatch(
                keywords: ["missing"],
                executable: "/fake/zoxide",
                run: { _, _ in (status: 1, stdout: "", stderr: "zoxide: no match found\n") }
            )
        )
        XCTAssertNil(
            Zoxide.bestMatch(
                keywords: ["downloads"],
                executable: "/fake/zoxide",
                run: { _, _ in (status: 0, stdout: "   \n", stderr: "") }
            )
        )
        XCTAssertNil(Zoxide.bestMatch(keywords: [], executable: "/fake/zoxide"))
    }

    func testAbbreviateHomePrefix() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(Zoxide.abbreviate(home), "~")
        XCTAssertEqual(Zoxide.abbreviate(home + "/Downloads"), "~/Downloads")
        XCTAssertEqual(Zoxide.abbreviate("/tmp/scratch"), "/tmp/scratch")
    }

    func testZoxideAppItemIsFolderWithQuietPath() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = home + "/Downloads"
        let item = AppItem.zoxide(path: path)
        XCTAssertEqual(item.kind, .folder)
        XCTAssertEqual(item.name, "Downloads")
        XCTAssertEqual(item.path, path)
        XCTAssertEqual(item.profile, "~/Downloads")
    }

    func testZoxideAppItemHomeShowsTilde() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let item = AppItem.zoxide(path: home)
        XCTAssertEqual(item.kind, .folder)
        XCTAssertEqual(item.name, "~")
        XCTAssertEqual(item.path, home)
        XCTAssertNil(item.profile)
    }

    @MainActor
    func testSearchZModeIsSyncEmptyWithoutPublishedMatch() {
        // Regression: search must not spawn zoxide during SwiftUI body evaluation.
        let index = AppIndex()
        XCTAssertEqual(index.search("z downloads"), [])
        XCTAssertNil(index.zoxideItem)
    }
}
