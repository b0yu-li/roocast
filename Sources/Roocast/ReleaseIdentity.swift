import Foundation

/// Packaging-time identity read from Info.plist (written by release.sh / dev-install.sh).
///
/// Official bundle id, product-site URLs, and update public key are **not** hardcoded
/// in source — they live in gitignored `Scripts/identity.env` and are stamped into
/// the .app at install/release time.
enum ReleaseIdentity {
    static let feedURLKey = "RoocastUpdateFeedURL"
    static let siteURLKey = "RoocastUpdateSiteURL"

    nonisolated static var feedURL: URL? {
        url(forInfoKey: feedURLKey)
    }

    nonisolated static var siteURL: URL? {
        url(forInfoKey: siteURLKey)
    }

    nonisolated private static func url(forInfoKey key: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !raw.isEmpty
        else {
            return nil
        }
        return URL(string: raw)
    }
}
