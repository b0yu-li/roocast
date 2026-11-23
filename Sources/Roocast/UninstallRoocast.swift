import AppKit
import Foundation

/// Clean uninstall: remove local data (Homebrew zap paths) + trash the .app, then quit.
///
/// Preserves `~/Library/Application Support/Roocast/notary/` so a maintainer
/// machine does not lose Apple API keys when dogfooding this command.
enum UninstallRoocast {
    /// Paths removed on uninstall (aligned with the Homebrew cask `zap`).
    nonisolated static func dataURLs(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            home.appendingPathComponent(".config/roocast"),
            home.appendingPathComponent("Library/Application Support/Roocast"),
            home.appendingPathComponent("Library/Logs/Roocast"),
        ]
    }

    /// Confirm, wipe data, trash the running bundle, then terminate.
    @MainActor
    static func run() {
        let alert = NSAlert()
        alert.messageText = "Uninstall Roocast?"
        alert.informativeText = """
        This removes Roocast from this Mac, including clipboard history and local config.

        If you installed with Homebrew, also run:
        brew uninstall --cask roocast
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let errors = performUninstall(bundleURL: Bundle.main.bundleURL)
        if !errors.isEmpty {
            let fail = NSAlert()
            fail.messageText = "Uninstall didn’t finish cleanly"
            fail.informativeText = errors.joined(separator: "\n")
            fail.alertStyle = .critical
            fail.addButton(withTitle: "OK")
            fail.runModal()
        }

        NSApplication.shared.terminate(nil)
    }

    /// Testable core: remove data dirs + trash (or delete) the app bundle.
    ///
    /// - Parameter expectedBundleID: Defaults to the running app’s id so source
    ///   never hardcodes a shipping identifier.
    nonisolated static func performUninstall(
        bundleURL: URL,
        expectedBundleID: String? = Bundle.main.bundleIdentifier,
        fileManager: FileManager = .default
    ) -> [String] {
        var errors: [String] = []

        guard bundleURL.pathExtension == "app" else {
            return ["Refusing to remove \(bundleURL.path) — not an .app bundle."]
        }
        guard let id = Bundle(url: bundleURL)?.bundleIdentifier else {
            return ["Refusing to remove \(bundleURL.path) — could not read bundle id."]
        }
        guard let expectedBundleID else {
            return ["Refusing to remove \(bundleURL.path) — no expected bundle id."]
        }
        guard id == expectedBundleID else {
            return [
                "Refusing to remove \(bundleURL.path) — bundle id is \(id), expected \(expectedBundleID)."
            ]
        }

        for url in dataURLs(home: fileManager.homeDirectoryForCurrentUser) {
            errors.append(contentsOf: removeData(at: url, fileManager: fileManager))
        }

        do {
            var resulting: NSURL?
            try fileManager.trashItem(at: bundleURL, resultingItemURL: &resulting)
        } catch {
            do {
                try fileManager.removeItem(at: bundleURL)
            } catch {
                errors.append("Could not remove app: \(error.localizedDescription)")
            }
        }

        return errors
    }

    /// Deletes `url`, but if it is Application Support/Roocast, keeps a `notary/` subfolder.
    nonisolated static func removeData(at url: URL, fileManager: FileManager) -> [String] {
        var errors: [String] = []
        guard fileManager.fileExists(atPath: url.path) else { return errors }

        let isAppSupport = url.lastPathComponent == "Roocast"
            && url.deletingLastPathComponent().lastPathComponent == "Application Support"
        let notary = url.appendingPathComponent("notary", isDirectory: true)

        if isAppSupport, fileManager.fileExists(atPath: notary.path) {
            do {
                let contents = try fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                for child in contents where child.lastPathComponent != "notary" {
                    do {
                        try fileManager.removeItem(at: child)
                    } catch {
                        errors.append("Could not remove \(child.path): \(error.localizedDescription)")
                    }
                }
            } catch {
                errors.append("Could not read \(url.path): \(error.localizedDescription)")
            }
            return errors
        }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            errors.append("Could not remove \(url.path): \(error.localizedDescription)")
        }
        return errors
    }
}
