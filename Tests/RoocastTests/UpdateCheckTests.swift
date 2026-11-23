import XCTest
import CryptoKit
@testable import Roocast

final class UpdateCheckTests: XCTestCase {

    func testIsNewerSemver() {
        XCTAssertTrue(UpdateCheck.isNewer("0.12.0", than: "0.11.0"))
        XCTAssertTrue(UpdateCheck.isNewer("1.0.0", than: "0.11.0"))
        XCTAssertTrue(UpdateCheck.isNewer("0.11.1", than: "0.11.0"))
        XCTAssertFalse(UpdateCheck.isNewer("0.11.0", than: "0.11.0"))
        XCTAssertFalse(UpdateCheck.isNewer("0.10.9", than: "0.11.0"))
        XCTAssertTrue(UpdateCheck.isNewer("0.11", than: "0.10.9"))
        XCTAssertFalse(UpdateCheck.isNewer("0.11", than: "0.11.0"))
    }

    func testDecodeFeedRequiresGoldFields() throws {
        let json = """
        {
          "version": "0.12.0",
          "dmg_url": "https://example.com/downloads/Roocast-0.12.0.dmg",
          "sha256": "abc",
          "ed25519": "sig",
          "released": "2026-12-01"
        }
        """.data(using: .utf8)!
        let feed = try UpdateCheck.decodeFeed(from: json)
        XCTAssertEqual(feed.version, "0.12.0")
        XCTAssertEqual(feed.sha256, "abc")
        XCTAssertEqual(feed.ed25519, "sig")
    }

    func testDecodeFeedFailsWithoutGoldFields() {
        let json = """
        {
          "version": "0.12.0",
          "dmg_url": "https://example.com/downloads/Roocast-0.12.0.dmg",
          "released": "2026-12-01"
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try UpdateCheck.decodeFeed(from: json))
    }

    func testOutcomeUpToDateWhenSigned() throws {
        let keys = TestUpdateKeys.generate()
        let version = "0.11.0"
        let sha = "deadbeef"
        let url = "https://example.com/downloads/Roocast-0.11.0.dmg"
        let sig = keys.sign(version: version, sha256: sha, dmgURL: url)
        let feed = UpdateCheck.Feed(
            version: version,
            dmg_url: url,
            sha256: sha,
            ed25519: sig,
            released: nil
        )
        XCTAssertEqual(
            UpdateCheck.outcome(
                feed: feed,
                currentVersion: "0.11.0",
                publicKeyBase64: keys.publicKeyBase64
            ),
            .upToDate(current: "0.11.0")
        )
    }

    func testOutcomeAvailableWhenSignedAndNewer() throws {
        let keys = TestUpdateKeys.generate()
        let version = "0.12.0"
        let sha = "cafebabe"
        let url = "https://example.com/downloads/Roocast-0.12.0.dmg"
        let sig = keys.sign(version: version, sha256: sha, dmgURL: url)
        let feed = UpdateCheck.Feed(
            version: version,
            dmg_url: url,
            sha256: sha,
            ed25519: sig,
            released: "2026-12-01"
        )
        let outcome = UpdateCheck.outcome(
            feed: feed,
            currentVersion: "0.11.0",
            publicKeyBase64: keys.publicKeyBase64
        )
        guard case .available(let latest, let dmgURL, let sha256) = outcome else {
            return XCTFail("expected available")
        }
        XCTAssertEqual(latest, "0.12.0")
        XCTAssertEqual(dmgURL.absoluteString, url)
        XCTAssertEqual(sha256, sha)
    }

    func testOutcomeFailedBadSignature() {
        let keys = TestUpdateKeys.generate()
        let feed = UpdateCheck.Feed(
            version: "0.12.0",
            dmg_url: "https://example.com/downloads/Roocast-0.12.0.dmg",
            sha256: "abc",
            ed25519: keys.sign(version: "0.12.0", sha256: "abc", dmgURL: "https://evil.example/x.dmg"),
            released: nil
        )
        XCTAssertEqual(
            UpdateCheck.outcome(
                feed: feed,
                currentVersion: "0.11.0",
                publicKeyBase64: keys.publicKeyBase64
            ),
            .failed
        )
    }

    func testOutcomeFailedEmptyURL() {
        let keys = TestUpdateKeys.generate()
        let sig = keys.sign(version: "0.12.0", sha256: "abc", dmgURL: "")
        let feed = UpdateCheck.Feed(
            version: "0.12.0",
            dmg_url: "",
            sha256: "abc",
            ed25519: sig,
            released: nil
        )
        XCTAssertEqual(
            UpdateCheck.outcome(
                feed: feed,
                currentVersion: "0.11.0",
                publicKeyBase64: keys.publicKeyBase64
            ),
            .failed
        )
    }

    func testSHA256Helper() throws {
        let dir = FileManager.default.temporaryDirectory
        let file = dir.appendingPathComponent("roocast-sha-test-\(UUID().uuidString)")
        try Data("hello".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let hex = try AppUpdater.sha256Hex(ofFile: file)
        XCTAssertEqual(
            hex,
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
        XCTAssertThrowsError(try AppUpdater.verifySHA256(file: file, expectedHex: "00"))
        try AppUpdater.verifySHA256(file: file, expectedHex: hex)
    }
}

/// Ephemeral Ed25519 pair for unit tests only — not the production release key.
private struct TestUpdateKeys {
    let privateKey: Curve25519.Signing.PrivateKey
    var publicKeyBase64: String {
        privateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    static func generate() -> TestUpdateKeys {
        TestUpdateKeys(privateKey: Curve25519.Signing.PrivateKey())
    }

    func sign(version: String, sha256: String, dmgURL: String) -> String {
        let message = UpdateSigning.canonicalMessage(
            version: version,
            sha256: sha256,
            dmgURL: dmgURL
        )
        let sig = try! privateKey.signature(for: message)
        return sig.base64EncodedString()
    }
}
