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
        let store = ClipboardStore(maxItems: 3)
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
        let store = ClipboardStore(maxItems: 10)
        store.prependForTesting("Hello World")
        store.prependForTesting("swift package")
        store.prependForTesting("HELLO again")

        XCTAssertEqual(store.items(matching: "").map(\.text), ["HELLO again", "swift package", "Hello World"])
        XCTAssertEqual(store.items(matching: "hello").map(\.text), ["HELLO again", "Hello World"])
        XCTAssertEqual(store.items(matching: "  SWIFT  ").map(\.text), ["swift package"])
        XCTAssertTrue(store.items(matching: "xyz").isEmpty)
    }
}
