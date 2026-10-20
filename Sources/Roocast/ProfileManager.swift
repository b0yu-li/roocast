import Foundation
import AppKit

struct FirefoxProfile: Hashable {
    let name: String
    let path: URL
    let isDefault: Bool
}

struct ProfileManager {
    // MARK: - Profile Detection
    
    static func detectFirefoxProfiles() -> [FirefoxProfile] {
        let profilesPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox/profiles.ini")
        
        do {
            let data = try Data(contentsOf: profilesPath)
            guard let content = String(data: data, encoding: .utf8) else {
                return []
            }
            return parseProfilesINI(content)
        } catch {
            // File doesn't exist or can't be read - return empty array
            return []
        }
    }
    
    private static func parseProfilesINI(_ content: String) -> [FirefoxProfile] {
        var profiles: [FirefoxProfile] = []
        let lines = content.components(separatedBy: .newlines)
        
        var currentProfile: [String: String] = [:]
        var isDefault = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("[Profile") {
                // Save previous profile if exists
                if let name = currentProfile["Name"], let path = currentProfile["Path"] {
                    let isRelative = currentProfile["IsRelative"] == "1"
                    let profilePath: URL
                    
                    if isRelative {
                        profilePath = FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent("Library/Application Support/Firefox")
                            .appendingPathComponent(path)
                    } else {
                        profilePath = URL(fileURLWithPath: path)
                    }
                    
                    profiles.append(FirefoxProfile(
                        name: name,
                        path: profilePath,
                        isDefault: isDefault
                    ))
                }
                currentProfile = [:]
                isDefault = false
            } else if trimmed.hasPrefix("Default=") {
                isDefault = true
            } else if let range = trimmed.range(of: "=") {
                let key = String(trimmed[trimmed.startIndex..<range.lowerBound])
                let value = String(trimmed[range.upperBound...])
                currentProfile[key] = value
            }
        }
        
        // Don't forget the last profile
        if let name = currentProfile["Name"], let path = currentProfile["Path"] {
            let isRelative = currentProfile["IsRelative"] == "1"
            let profilePath: URL
            
            if isRelative {
                profilePath = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/Firefox")
                    .appendingPathComponent(path)
            } else {
                profilePath = URL(fileURLWithPath: path)
            }
            
            profiles.append(FirefoxProfile(
                name: name,
                path: profilePath,
                isDefault: isDefault
            ))
        }
        
        return profiles
    }
    
    // MARK: - Running Instance Detection
    
    /// Detect which Firefox profiles are currently running.
    /// Uses profile lock files only — never shells out to `ps`/`pgrep`.
    /// Spawning Process + Pipe on the main thread previously deadlocked startup
    /// when `ps aux` filled the pipe buffer before `waitUntilExit` could return.
    static func detectRunningProfiles() -> [String: FirefoxProfile] {
        let profiles = detectFirefoxProfiles()
        var result: [String: FirefoxProfile] = [:]
        
        for profile in profiles {
            if isProfileRunning(profile) {
                result[profile.name] = profile
            }
        }
        
        return result
    }
    
    /// Firefox writes `lock` / `.parentlock` while a profile is in use.
    private static func isProfileRunning(_ profile: FirefoxProfile) -> Bool {
        let candidates = ["lock", ".parentlock"]
        for name in candidates {
            let lockFile = profile.path.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: lockFile.path) {
                return true
            }
        }
        return false
    }
    
    // MARK: - Instance Count
    
    static func countFirefoxInstances() -> Int {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == "org.mozilla.firefox" }
            .count
    }
}
