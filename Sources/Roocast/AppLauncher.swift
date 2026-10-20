import Foundation
import AppKit

/// Handles app launching logic with profile support
struct AppLauncher {

    /// Launch Firefox with a specific profile.
    /// - If that profile is already running, activates *that* process (by lock PID).
    /// - If not, opens a new instance with `-no-remote` so a second profile can run.
    static func launchFirefoxProfile(profile: String, appPath: String) {
        let profiles = ProfileManager.detectFirefoxProfiles()
        guard let matched = profiles.first(where: { $0.name == profile }) else {
            openFirefoxApp(appPath: appPath)
            return
        }

        if ProfileManager.isProfileRunning(matched) {
            activateFirefoxProfile(matched, appPath: appPath)
        } else {
            launchFirefoxWithProfile(profilePath: matched.path, appPath: appPath)
        }
    }

    /// Bring the Firefox process that owns this profile to the front.
    /// Must not use `.first` Firefox — multiple instances share one bundle ID.
    private static func activateFirefoxProfile(_ profile: FirefoxProfile, appPath: String) {
        if let pid = ProfileManager.pidHoldingParentLock(at: profile.path),
           let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateAllWindows])
            return
        }

        // Fallback: any live Firefox, then open the bundle.
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == "org.mozilla.firefox" && !$0.isTerminated }
        if let app = running.first {
            app.activate(options: [.activateAllWindows])
            return
        }

        openFirefoxApp(appPath: appPath)
    }

    /// Launch a new Firefox instance for a profile that is not already running.
    /// `-no-remote` is required; without it, Firefox forwards to the existing process
    /// and ignores the requested profile.
    private static func launchFirefoxWithProfile(profilePath: URL, appPath: String) {
        let appURL = URL(fileURLWithPath: appPath)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.arguments = [
            "-no-remote",
            "--profile", profilePath.path,
            "-foreground",
        ]

        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            if error != nil {
                openFirefoxApp(appPath: appPath)
            }
        }
    }

    private static func openFirefoxApp(appPath: String) {
        let appURL = URL(fileURLWithPath: appPath)
        NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
