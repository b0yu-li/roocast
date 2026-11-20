import AppKit
import Foundation

/// Lightweight product-site update check (no Sparkle).
///
/// Fetches `roocast/latest.json` from the product site, compares dotted semver
/// to the running build, and either reports up-to-date or opens the DMG URL.
enum UpdateCheck {
    static let feedURL = URL(string: "https://rooby.shop/roocast/latest.json")!
    static let siteURL = URL(string: "https://rooby.shop/")!

    struct Feed: Decodable, Equatable {
        let version: String
        let dmg_url: String
        let released: String?
    }

    enum Outcome: Equatable {
        case upToDate(current: String)
        case available(latest: String, dmgURL: URL)
        case failed
    }

    /// Compare dotted semver strings (`0.11.0`). Missing trailing components count as 0.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = versionParts(candidate)
        let rhs = versionParts(current)
        let count = max(lhs.count, rhs.count)
        for i in 0..<count {
            let a = i < lhs.count ? lhs[i] : 0
            let b = i < rhs.count ? rhs[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    nonisolated static func outcome(
        feed: Feed,
        currentVersion: String
    ) -> Outcome {
        guard let dmgURL = URL(string: feed.dmg_url), !feed.version.isEmpty else {
            return .failed
        }
        if isNewer(feed.version, than: currentVersion) {
            return .available(latest: feed.version, dmgURL: dmgURL)
        }
        return .upToDate(current: currentVersion)
    }

    nonisolated static func decodeFeed(from data: Data) throws -> Feed {
        try JSONDecoder().decode(Feed.self, from: data)
    }

    /// Network check against the product-site feed.
    static func check(
        session: URLSession = .shared,
        currentVersion: String = AppVersion.string
    ) async -> Outcome {
        do {
            var request = URLRequest(url: feedURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .failed
            }
            let feed = try decodeFeed(from: data)
            return outcome(feed: feed, currentVersion: currentVersion)
        } catch {
            return .failed
        }
    }

    /// Present the outcome after the launcher panel is dismissed.
    @MainActor
    static func present(_ outcome: Outcome) {
        switch outcome {
        case .upToDate(let current):
            let alert = NSAlert()
            alert.messageText = "Roocast is up to date"
            alert.informativeText = "You’re on v\(current)."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()

        case .available(let latest, let dmgURL):
            NSWorkspace.shared.open(dmgURL)
            let alert = NSAlert()
            alert.messageText = "Update available"
            alert.informativeText =
                "Roocast v\(latest) is ready. The download page opened — install the DMG when it finishes."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()

        case .failed:
            let alert = NSAlert()
            alert.messageText = "Couldn’t check for updates"
            alert.informativeText = "Check your network, or open the website to download manually."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Website")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(siteURL)
            }
        }
    }

    nonisolated private static func versionParts(_ version: String) -> [Int] {
        version
            .split(separator: ".")
            .map { Int($0.filter(\.isNumber)) ?? 0 }
    }
}
