import AppKit
import Foundation

/// Product-site update check + user-initiated in-app install (no Sparkle, no auto-update).
///
/// Feed/site URLs and Ed25519 public key come from Info.plist (packaging-time), not source.
/// Updates run only when the user chooses Check for Updates → Install Update.
enum UpdateCheck {
    struct Feed: Decodable, Equatable {
        let version: String
        let dmg_url: String
        let sha256: String
        let ed25519: String
        let released: String?
    }

    enum Outcome: Equatable {
        case upToDate(current: String)
        case available(latest: String, dmgURL: URL, sha256: String)
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

    /// Fail closed unless sha256 + ed25519 verify; then compare semver.
    nonisolated static func outcome(
        feed: Feed,
        currentVersion: String,
        publicKeyBase64: String
    ) -> Outcome {
        guard !feed.version.isEmpty,
              !feed.sha256.isEmpty,
              !feed.ed25519.isEmpty,
              let dmgURL = URL(string: feed.dmg_url),
              !feed.dmg_url.isEmpty
        else {
            return .failed
        }
        guard UpdateSigning.verifyFeedSignature(
            version: feed.version,
            sha256: feed.sha256,
            dmgURL: feed.dmg_url,
            signatureBase64: feed.ed25519,
            publicKeyBase64: publicKeyBase64
        ) else {
            return .failed
        }
        if isNewer(feed.version, than: currentVersion) {
            return .available(latest: feed.version, dmgURL: dmgURL, sha256: feed.sha256)
        }
        return .upToDate(current: currentVersion)
    }

    nonisolated static func decodeFeed(from data: Data) throws -> Feed {
        try JSONDecoder().decode(Feed.self, from: data)
    }

    /// Network check against the product-site feed stamped into this build.
    static func check(
        session: URLSession = .shared,
        currentVersion: String = AppVersion.string
    ) async -> Outcome {
        guard let feedURL = ReleaseIdentity.feedURL,
              let publicKey = UpdateSigning.embeddedPublicKeyBase64,
              !publicKey.isEmpty
        else {
            return .failed
        }
        do {
            var request = URLRequest(url: feedURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return .failed
            }
            let feed = try decodeFeed(from: data)
            return outcome(
                feed: feed,
                currentVersion: currentVersion,
                publicKeyBase64: publicKey
            )
        } catch {
            return .failed
        }
    }

    /// Present the outcome after the launcher panel is dismissed.
    /// Install path is user-confirmed only — never automatic.
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

        case .available(let latest, let dmgURL, let sha256):
            let alert = NSAlert()
            alert.messageText = "Update available"
            alert.informativeText =
                "Roocast v\(latest) is ready. Install now to replace this copy and relaunch."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Install Update")
            alert.addButton(withTitle: "Later")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            beginInstall(latest: latest, dmgURL: dmgURL, sha256: sha256)

        case .failed:
            let alert = NSAlert()
            alert.messageText = "Couldn’t check for updates"
            alert.informativeText = "Check your network, or open the website to download manually."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open Website")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                openSite()
            }
        }
    }

    @MainActor
    private static func openSite() {
        if let site = ReleaseIdentity.siteURL {
            NSWorkspace.shared.open(site)
        }
    }

    /// Retains the progress panel while an install runs (target/action + Task).
    @MainActor private static var activeProgressPanel: UpdateProgressPanel?

    @MainActor
    private static func beginInstall(latest: String, dmgURL: URL, sha256: String) {
        let panel = UpdateProgressPanel()
        activeProgressPanel = panel
        panel.show()
        let task = Task { @MainActor in
            defer { activeProgressPanel = nil }
            do {
                try await AppUpdater.install(
                    latest: latest,
                    dmgURL: dmgURL,
                    expectedSHA256: sha256,
                    progress: { value in
                        Task { @MainActor in
                            activeProgressPanel?.setProgress(value)
                        }
                    }
                )
            } catch {
                panel.close()
                if let updaterError = error as? AppUpdater.UpdaterError,
                   updaterError == .cancelled {
                    return
                }
                let alert = NSAlert()
                alert.messageText = "Update failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open Website")
                alert.addButton(withTitle: "OK")
                if alert.runModal() == .alertFirstButtonReturn {
                    openSite()
                }
            }
        }
        panel.onCancel = {
            task.cancel()
            panel.close()
            activeProgressPanel = nil
        }
    }

    nonisolated private static func versionParts(_ version: String) -> [Int] {
        version
            .split(separator: ".")
            .map { Int($0.filter(\.isNumber)) ?? 0 }
    }
}

// MARK: - Progress UI

@MainActor
final class UpdateProgressPanel: NSObject {
    private let window: NSPanel
    private let indicator: NSProgressIndicator
    private let label: NSTextField
    var onCancel: (() -> Void)?

    override init() {
        let rect = NSRect(x: 0, y: 0, width: 320, height: 110)
        let panel = NSPanel(
            contentRect: rect,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "Updating Roocast"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.center()

        let title = NSTextField(labelWithString: "Downloading update…")
        title.frame = NSRect(x: 20, y: 70, width: 280, height: 20)
        title.font = .systemFont(ofSize: 13)

        let bar = NSProgressIndicator(frame: NSRect(x: 20, y: 42, width: 280, height: 16))
        bar.minValue = 0
        bar.maxValue = 1
        bar.isIndeterminate = false
        bar.doubleValue = 0

        window = panel
        label = title
        indicator = bar
        super.init()

        let cancel = NSButton(frame: NSRect(x: 220, y: 12, width: 80, height: 24))
        cancel.title = "Cancel"
        cancel.bezelStyle = .rounded
        cancel.target = self
        cancel.action = #selector(cancelTapped)

        window.contentView?.addSubview(label)
        window.contentView?.addSubview(indicator)
        window.contentView?.addSubview(cancel)
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setProgress(_ value: Double) {
        indicator.doubleValue = value
        if value >= 0.99 {
            label.stringValue = "Verifying and installing…"
        }
    }

    func close() {
        window.orderOut(nil)
    }

    @objc private func cancelTapped() {
        onCancel?()
    }
}

extension AppUpdater.UpdaterError: Equatable {
    static func == (lhs: AppUpdater.UpdaterError, rhs: AppUpdater.UpdaterError) -> Bool {
        switch (lhs, rhs) {
        case (.badFeed, .badFeed),
             (.downloadFailed, .downloadFailed),
             (.cancelled, .cancelled),
             (.sha256Mismatch, .sha256Mismatch),
             (.mountFailed, .mountFailed),
             (.appNotFoundInDMG, .appNotFoundInDMG),
             (.codeInvalid, .codeInvalid),
             (.teamMismatch, .teamMismatch),
             (.bundleIDMismatch, .bundleIDMismatch):
            return true
        case (.helperFailed(let a), .helperFailed(let b)):
            return a == b
        default:
            return false
        }
    }
}
