import Foundation
import AppKit

/// Handles app launching logic with profile support
struct AppLauncher {
    
    /// Launch Firefox with a specific profile
    /// - If profile is already running, brings it to front
    /// - If not running, launches new instance with that profile
    static func launchFirefoxProfile(profile: String, appPath: String) {
        // Check if this profile is already running
        let runningProfiles = ProfileManager.detectRunningProfiles()
        
        if runningProfiles[profile] != nil {
            // Profile is running - bring Firefox to front
            activateFirefox(appPath: appPath)
        } else {
            // Profile not running - launch with -P argument
            launchFirefoxWithProfile(profile: profile, appPath: appPath)
        }
    }
    
    /// Bring existing Firefox instance to front
    private static func activateFirefox(appPath: String) {
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            if app.bundleIdentifier == "org.mozilla.firefox" {
                // Activate the first Firefox instance found
                app.activate()
                return
            }
        }
        
        // Fallback: if no running instance found, launch normally
        if let url = URL(string: "file://\(appPath)") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Launch Firefox with specific profile argument
    private static func launchFirefoxWithProfile(profile: String, appPath: String) {
        let firefoxBinary = appPath + "/Contents/MacOS/firefox"
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: firefoxBinary)
        task.arguments = ["-P", profile, "-foreground"]
        
        do {
            try task.run()
        } catch {
            // Fallback to standard launch if profile launch fails
            if let url = URL(string: "file://\(appPath)") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
