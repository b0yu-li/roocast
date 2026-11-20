import XCTest
@testable import Roocast

final class UninstallRoocastTests: XCTestCase {

    func testDataURLsMatchBrewZap() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let urls = UninstallRoocast.dataURLs(home: home).map(\.path)
        XCTAssertEqual(
            urls,
            [
                "/Users/test/.config/roocast",
                "/Users/test/Library/Application Support/Roocast",
                "/Users/test/Library/Logs/Roocast",
            ]
        )
    }

    func testRemoveDataPreservesNotaryFolder() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(
            "roocast-uninstall-\(UUID().uuidString)",
            isDirectory: true
        )
        let appSupport = root
            .appendingPathComponent("Library/Application Support/Roocast", isDirectory: true)
        let notary = appSupport.appendingPathComponent("notary", isDirectory: true)
        let history = appSupport.appendingPathComponent("clipboard-history.json")
        let images = appSupport.appendingPathComponent("images", isDirectory: true)

        try fm.createDirectory(at: notary, withIntermediateDirectories: true)
        try fm.createDirectory(at: images, withIntermediateDirectories: true)
        try "secret".write(to: notary.appendingPathComponent("key.p8"), atomically: true, encoding: .utf8)
        try "[]".write(to: history, atomically: true, encoding: .utf8)

        let errors = UninstallRoocast.removeData(at: appSupport, fileManager: fm)
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: ", "))
        XCTAssertTrue(fm.fileExists(atPath: notary.path))
        XCTAssertTrue(fm.fileExists(atPath: notary.appendingPathComponent("key.p8").path))
        XCTAssertFalse(fm.fileExists(atPath: history.path))
        XCTAssertFalse(fm.fileExists(atPath: images.path))

        try? fm.removeItem(at: root)
    }

    func testRemoveDataDeletesWholeTreeWithoutNotary() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(
            "roocast-uninstall-clean-\(UUID().uuidString)",
            isDirectory: true
        )
        let logs = root.appendingPathComponent("Library/Logs/Roocast", isDirectory: true)
        try fm.createDirectory(at: logs, withIntermediateDirectories: true)
        try "log".write(to: logs.appendingPathComponent("focus.log"), atomically: true, encoding: .utf8)

        let errors = UninstallRoocast.removeData(at: logs, fileManager: fm)
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: ", "))
        XCTAssertFalse(fm.fileExists(atPath: logs.path))

        try? fm.removeItem(at: root)
    }

    func testPerformUninstallRefusesBundleWithoutIdentifier() throws {
        let fm = FileManager.default
        let fake = fm.temporaryDirectory.appendingPathComponent(
            "NotRoocast-\(UUID().uuidString).app",
            isDirectory: true
        )
        try fm.createDirectory(at: fake, withIntermediateDirectories: true)
        let errors = UninstallRoocast.performUninstall(bundleURL: fake, fileManager: fm)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].contains("Refusing"))
        XCTAssertTrue(fm.fileExists(atPath: fake.path), "refused uninstall must not delete the bundle")
        try? fm.removeItem(at: fake)
    }
}
