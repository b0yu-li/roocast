import Foundation
import CryptoKit

/// Ed25519 feed signatures for in-app updates (Sparkle-parity, no Sparkle).
///
/// The **public** key is injected into Info.plist at package time
/// (`RoocastUpdatePublicKey`) from gitignored `Scripts/identity.env` — not
/// hardcoded in source. Private key never ships and never enters git.
enum UpdateSigning {
    /// Info.plist key written by `release.sh` / `dev-install.sh`.
    static let publicKeyInfoKey = "RoocastUpdatePublicKey"

    /// Public key from the running app’s Info.plist, if this build was packaged with one.
    nonisolated static var embeddedPublicKeyBase64: String? {
        Bundle.main.object(forInfoDictionaryKey: publicKeyInfoKey) as? String
    }

    /// Exact UTF-8 message `release.sh` signs and the app verifies.
    nonisolated static func canonicalMessage(
        version: String,
        sha256: String,
        dmgURL: String
    ) -> Data {
        let text = "roocast-update-v1\n\(version)\n\(sha256)\n\(dmgURL)"
        return Data(text.utf8)
    }

    /// Returns true when `signatureBase64` is a valid Ed25519 signature over the canonical message.
    nonisolated static func verifyFeedSignature(
        version: String,
        sha256: String,
        dmgURL: String,
        signatureBase64: String,
        publicKeyBase64: String
    ) -> Bool {
        guard let keyData = Data(base64Encoded: publicKeyBase64),
              let signature = Data(base64Encoded: signatureBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else {
            return false
        }
        let message = canonicalMessage(version: version, sha256: sha256, dmgURL: dmgURL)
        return publicKey.isValidSignature(signature, for: message)
    }
}
