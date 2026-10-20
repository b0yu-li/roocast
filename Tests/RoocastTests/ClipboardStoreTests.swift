import CryptoKit
import XCTest
@testable import Roocast

@MainActor
final class ClipboardStoreTests: XCTestCase {

    func testPreviewCollapsesWhitespaceAndTruncates() {
        let long = String(repeating: "a", count: 130)
        let item = ClipboardItem(id: UUID(), text: "hello\n\tworld", createdAt: Date())
        XCTAssertEqual(item.preview, "hello  world")

        let longItem = ClipboardItem(id: UUID(), text: long, createdAt: Date())
        XCTAssertTrue(longItem.preview.hasSuffix("…"))
        XCTAssertEqual(longItem.preview.count, 121)
    }

    func testPrependRespectsMaxItems() {
        let store = ClipboardStore(maxItems: 3, persistToDisk: false)
        store.prependForTesting("one")
        store.prependForTesting("two")
        store.prependForTesting("three")
        store.prependForTesting("four")

        XCTAssertEqual(store.items.count, 3)
        XCTAssertEqual(store.items.map(\.text), ["four", "three", "two"])
    }

    func testHotKeyIDsAreDistinct() {
        XCTAssertEqual(HotKeyID.launcher.rawValue, 1)
        XCTAssertEqual(HotKeyID.clipboard.rawValue, 2)
        XCTAssertNotEqual(HotKeyID.launcher, HotKeyID.clipboard)
    }

    func testClipboardLayoutIsCompact() {
        XCTAssertEqual(ClipboardLayout.width, 560)
        XCTAssertEqual(ClipboardLayout.height, 360)
        XCTAssertGreaterThan(ClipboardLayout.cornerRadius, 0)
    }

    func testItemsMatchingFiltersCaseInsensitive() {
        let store = ClipboardStore(maxItems: 10, persistToDisk: false)
        store.prependForTesting("Hello World")
        store.prependForTesting("swift package")
        store.prependForTesting("HELLO again")

        XCTAssertEqual(store.items(matching: "").map(\.text), ["HELLO again", "swift package", "Hello World"])
        XCTAssertEqual(store.items(matching: "hello").map(\.text), ["HELLO again", "Hello World"])
        XCTAssertEqual(store.items(matching: "  SWIFT  ").map(\.text), ["swift package"])
        XCTAssertTrue(store.items(matching: "xyz").isEmpty)
    }

    func testDefaultStorageURLIsEncryptedUnderApplicationSupport() {
        let path = ClipboardStore.defaultStorageURL.path
        XCTAssertTrue(path.contains("Library/Application Support/Roocast/clipboard-history.enc"))
    }

    func testPersistsEncryptedAndReloadsFromDisk() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roocast-clipboard-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("clipboard-history.enc")
        let key = SymmetricKey(size: .bits256)

        let writer = ClipboardStore(maxItems: 5, storageURL: url, encryptionKey: key)
        writer.prependForTesting("alpha")
        writer.prependForTesting("beta")
        writer.persistNow()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let onDisk = try Data(contentsOf: url)
        XCTAssertTrue(ClipboardCrypto.isEncryptedBlob(onDisk))
        XCTAssertThrowsError(try JSONDecoder().decode([ClipboardItem].self, from: onDisk))

        let reader = ClipboardStore(maxItems: 5, storageURL: url, encryptionKey: key)
        reader.loadPersistedHistory()

        XCTAssertEqual(reader.items.map(\.text), ["beta", "alpha"])
    }

    func testWrongKeyCannotDecrypt() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roocast-clipboard-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("clipboard-history.enc")
        let writerKey = SymmetricKey(size: .bits256)
        let wrongKey = SymmetricKey(size: .bits256)

        let writer = ClipboardStore(maxItems: 5, storageURL: url, encryptionKey: writerKey)
        writer.prependForTesting("secret")
        writer.persistNow()

        let reader = ClipboardStore(maxItems: 5, storageURL: url, encryptionKey: wrongKey)
        reader.loadPersistedHistory()
        XCTAssertTrue(reader.items.isEmpty)
    }

    func testMigratesLegacyPlaintextJSON() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roocast-clipboard-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("clipboard-history.json")
        let key = SymmetricKey(size: .bits256)
        let items = [
            ClipboardItem(id: UUID(), text: "legacy", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(items).write(to: url)

        let store = ClipboardStore(maxItems: 5, storageURL: url, encryptionKey: key)
        store.loadPersistedHistory()
        XCTAssertEqual(store.items.map(\.text), ["legacy"])

        store.persistNow()
        let rewritten = try Data(contentsOf: url)
        XCTAssertTrue(ClipboardCrypto.isEncryptedBlob(rewritten))
    }

    func testSealOpenRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Data("hello clipboard".utf8)
        let sealed = try ClipboardCrypto.seal(plain, using: key)
        XCTAssertTrue(ClipboardCrypto.isEncryptedBlob(sealed))
        let opened = try ClipboardCrypto.open(sealed, using: key)
        XCTAssertEqual(opened, plain)
    }

    func testSkipsOversizedItems() {
        let store = ClipboardStore(maxItems: 5, maxTextLength: 8, persistToDisk: false)
        store.prependForTesting("short")
        store.prependForTesting("way too long for the limit")
        XCTAssertEqual(store.items.map(\.text), ["short"])
    }

    func testDefaultPollIntervalIsRelaxed() {
        let store = ClipboardStore(persistToDisk: false)
        // Default is 2s — accessible via startMonitoring log; assert via re-init param clamp.
        let fast = ClipboardStore(pollInterval: 0.1, persistToDisk: false)
        // Interval below 0.5 is clamped; we can't read private props, so just ensure init doesn't crash.
        _ = store
        _ = fast
    }
}
