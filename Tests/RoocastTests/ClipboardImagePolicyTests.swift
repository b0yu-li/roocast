import XCTest
@testable import Roocast

final class ClipboardImagePolicyTests: XCTestCase {

    // MARK: - AC1: durable Finder image → pointer (no owned blob)

    func testDurableImageFileDoesNotStoreOwnedBlob() {
        XCTAssertFalse(
            ClipboardImagePolicy.storesOwnedBlob(hasDurableImageFileURL: true)
        )
    }

    // MARK: - AC2: bare inline image → owned blob

    func testInlineImageStoresOwnedBlob() {
        XCTAssertTrue(
            ClipboardImagePolicy.storesOwnedBlob(hasDurableImageFileURL: false)
        )
    }

    // MARK: - AC3: paste publishes file pointer, never image bytes

    func testPasteUsesFilePointerNotImageBytes() {
        XCTAssertFalse(ClipboardImagePolicy.pastesImageBytes)
        XCTAssertTrue(ClipboardImagePolicy.pastesFileURL)
        XCTAssertTrue(ClipboardImagePolicy.pastesPathAsString)
    }

    // MARK: - AC4: soft-cap only owned blobs

    func testOnlyOwnedBlobsCountTowardImageCap() {
        XCTAssertTrue(ClipboardImagePolicy.countsTowardImageCap(isOwnedBlob: true))
        XCTAssertFalse(ClipboardImagePolicy.countsTowardImageCap(isOwnedBlob: false))
    }

    // MARK: - Preview label

    func testPreviewLabelPrefersFilenameForPointers() {
        XCTAssertEqual(
            ClipboardImagePolicy.previewLabel(displayName: "shot.png", isOwnedBlob: false),
            "shot.png"
        )
        XCTAssertEqual(
            ClipboardImagePolicy.previewLabel(displayName: "shot.png", isOwnedBlob: true),
            "Image"
        )
        XCTAssertEqual(
            ClipboardImagePolicy.previewLabel(displayName: nil, isOwnedBlob: false),
            "Image"
        )
    }
}
