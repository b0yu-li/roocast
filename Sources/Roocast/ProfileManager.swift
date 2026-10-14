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
        
        guard let data = try? Data(contentsOf: profilesPath),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        
        return parseProfilesINI(content)
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
    
    static func detectRunningProfiles() -> [String: FirefoxProfile] {
        let profiles = detectFirefoxProfiles()
        let runningProfiles = detectRunningProfilePaths()
        
        var result: [String: FirefoxProfile] = [:]
        
        for profile in profiles {
            if runningProfiles.contains(profile.path.path) {
                result[profile.name] = profile
            }
        }
        
        return result
    }
    
    private static func detectRunningProfilePaths() -> Set<String> {
        var profilePaths = Set<String>()
        
        // Method 1: Check lock files (fast path)
        let profiles = detectFirefoxProfiles()
        for profile in profiles {
            let lockFile = profile.path.appendingPathComponent("lock")
            if FileManager.default.fileExists(atPath: lockFile.path) {
                profilePaths.insert(profile.path.path)
            }
        }
        
        // Method 2: Scan processes (fallback)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["aux"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Look for -profile arguments in process list
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    if let range = line.range(of: "-profile ") {
                        let afterProfile = line[range.upperBound...]
                        if let spaceRange = afterProfile.range(of: " ") {
                            let profilePath = String(afterProfile[afterProfile.startIndex..<spaceRange.lowerBound])
                            profilePaths.insert(profilePath)
                        } else {
                            profilePaths.insert(String(afterProfile))
                        }
                    }
                }
            }
        } catch {
            // Process scanning failed, rely on lock files only
        }
        
        return profilePaths
    }
    
    // MARK: - Instance Count
    
    static func countFirefoxInstances() -> Int {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "firefox -foreground"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
                return lines.count
            }
        } catch {
            // Failed to count
        }
        
        return 0
    }
}
