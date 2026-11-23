import XCTest
import CryptoKit
@testable import Roocast

final class UpdateSigningTests: XCTestCase {
    func testCanonicalMessageFormat() {
        let data = UpdateSigning.canonicalMessage(
            version: "0.12.0",
            sha256: "abcd",
            dmgURL: "https://example.com/Roocast-0.12.0.dmg"
        )
        let text = String(data: data, encoding: .utf8)
        XCTAssertEqual(
            text,
            "roocast-update-v1\n0.12.0\nabcd\nhttps://example.com/Roocast-0.12.0.dmg"
        )
    }

    func testVerifyAcceptsValidSignature() {
        let privateKey = Curve25519.Signing.PrivateKey()
        let pub = privateKey.publicKey.rawRepresentation.base64EncodedString()
        let version = "0.12.0"
        let sha = "ff19"
        let url = "https://example.com/downloads/Roocast-0.12.0.dmg"
        let message = UpdateSigning.canonicalMessage(version: version, sha256: sha, dmgURL: url)
        let sig = try! privateKey.signature(for: message).base64EncodedString()
        XCTAssertTrue(
            UpdateSigning.verifyFeedSignature(
                version: version,
                sha256: sha,
                dmgURL: url,
                signatureBase64: sig,
                publicKeyBase64: pub
            )
        )
    }

    func testVerifyRejectsTamperedURL() {
        let privateKey = Curve25519.Signing.PrivateKey()
        let pub = privateKey.publicKey.rawRepresentation.base64EncodedString()
        let message = UpdateSigning.canonicalMessage(
            version: "0.12.0",
            sha256: "ff19",
            dmgURL: "https://good.example/a.dmg"
        )
        let sig = try! privateKey.signature(for: message).base64EncodedString()
        XCTAssertFalse(
            UpdateSigning.verifyFeedSignature(
                version: "0.12.0",
                sha256: "ff19",
                dmgURL: "https://evil.example/a.dmg",
                signatureBase64: sig,
                publicKeyBase64: pub
            )
        )
    }
}
