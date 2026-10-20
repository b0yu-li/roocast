import Foundation
import AppKit
import Darwin

struct FirefoxProfile: Hashable {
    let name: String
    let path: URL
    let isDefault: Bool
}

// MARK: - libproc (lock file → PID, no shell)

@_silgen_name("proc_pidinfo")
private func proc_pidinfo(_ pid: Int32, _ flavor: Int32, _ arg: UInt64, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32
@_silgen_name("proc_pidfdinfo")
private func proc_pidfdinfo(_ pid: Int32, _ fd: Int32, _ flavor: Int32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

private let PROC_PIDLISTFDS: Int32 = 1
private let PROC_PIDFDVNODEPATHINFO: Int32 = 2
private let PROX_FDTYPE_VNODE: UInt32 = 1

private struct proc_fdinfo {
    var proc_fd: Int32
    var proc_fdtype: UInt32
}

struct ProfileManager {
    // MARK: - Profile Detection

    /// Usable on-disk profiles, with names from `profiles.ini` when that path is listed.
    ///
    /// Stub folders (e.g. INI `default` with only `times.json`, no `prefs.js`) are omitted
    /// unless Firefox is currently holding their `.parentlock` — otherwise they inflate the
    /// launcher with ghost rows (3 Firefox entries for 2 real instances).
    static func detectFirefoxProfiles() -> [FirefoxProfile] {
        var byPath: [String: FirefoxProfile] = [:]

        // 1. Real profiles on disk (require prefs.js).
        for profile in discoverProfilesOnDisk() {
            byPath[standardizedPath(profile.path)] = profile
        }

        // 2. Running orphans without prefs.js still need a selectable row.
        // Use libproc PID ownership — NOT flock. Concurrent index scans briefly take
        // LOCK_EX on stub `.parentlock` files; a second scan then false-positives
        // "held" and invents a ghost row (e.g. INI stub `default` with no green dot).
        for url in profileDirectoriesOnDisk() {
            let key = standardizedPath(url)
            guard byPath[key] == nil, pidHoldingParentLock(at: url) != nil else { continue }
            byPath[key] = FirefoxProfile(
                name: displayName(fromProfileFolder: url.lastPathComponent),
                path: url,
                isDefault: false
            )
        }

        // 3. INI overlays friendly Name + Default onto matching paths.
        let profilesPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox/profiles.ini")
        if let data = try? Data(contentsOf: profilesPath),
           let content = String(data: data, encoding: .utf8) {
            for profile in parseProfilesINI(content) {
                let key = standardizedPath(profile.path)
                if byPath[key] != nil {
                    byPath[key] = FirefoxProfile(
                        name: profile.name,
                        path: profile.path,
                        isDefault: profile.isDefault
                    )
                } else if hasPrefsJS(at: profile.path) {
                    // INI path with prefs but missed by disk scan — still list.
                    byPath[key] = profile
                }
                // else: stub INI entry (times.json / empty) — skip
            }
        }

        return disambiguateNames(byPath).sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault && !rhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// True when the folder looks like a real Firefox profile (has `prefs.js`).
    static func hasPrefsJS(at profileDirectory: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: profileDirectory.appendingPathComponent("prefs.js").path
        )
    }

    /// When two paths share a display name (common after Firefox rewrites `profiles.ini`),
    /// fall back to folder-derived names so each instance stays selectable.
    static func disambiguateNames(_ byPath: [String: FirefoxProfile]) -> [FirefoxProfile] {
        var groups: [String: [(key: String, profile: FirefoxProfile)]] = [:]
        for (key, profile) in byPath {
            groups[profile.name, default: []].append((key, profile))
        }

        var result: [FirefoxProfile] = []
        for (_, entries) in groups {
            if entries.count == 1 {
                result.append(entries[0].profile)
                continue
            }
            var usedNames = Set<String>()
            for entry in entries {
                let folderName = URL(fileURLWithPath: entry.key).lastPathComponent
                var candidate = displayName(fromProfileFolder: folderName)
                if usedNames.contains(candidate) {
                    candidate = folderName
                }
                usedNames.insert(candidate)
                result.append(FirefoxProfile(
                    name: candidate,
                    path: entry.profile.path,
                    isDefault: entry.profile.isDefault
                ))
            }
        }
        return result
    }

    /// Parses Firefox `profiles.ini`. Internal for unit tests.
    static func parseProfilesINI(_ content: String) -> [FirefoxProfile] {
        var profiles: [FirefoxProfile] = []
        let lines = content.components(separatedBy: .newlines)

        var currentProfile: [String: String] = [:]
        var isDefault = false
        var inProfileSection = false

        func flushCurrentProfile() {
            guard inProfileSection,
                  let name = currentProfile["Name"],
                  let path = currentProfile["Path"] else {
                currentProfile = [:]
                isDefault = false
                return
            }

            let isRelative = currentProfile["IsRelative"] == "1"
            let profilePath: URL
            if isRelative {
                profilePath = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Application Support/Firefox")
                    .appending(path: path)
            } else {
                profilePath = URL(fileURLWithPath: path)
            }

            profiles.append(FirefoxProfile(
                name: name,
                path: profilePath,
                isDefault: isDefault
            ))
            currentProfile = [:]
            isDefault = false
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("[") {
                flushCurrentProfile()
                inProfileSection = trimmed.hasPrefix("[Profile")
                continue
            }

            // Ignore [General] / [Install…] keys (e.g. Install Default=Profiles/…).
            guard inProfileSection else { continue }

            if trimmed == "Default=1" {
                isDefault = true
            } else if let range = trimmed.range(of: "=") {
                let key = String(trimmed[trimmed.startIndex..<range.lowerBound])
                let value = String(trimmed[range.upperBound...])
                currentProfile[key] = value
            }
        }

        flushCurrentProfile()
        return profiles
    }

    /// `Tkfsj6cm.Profile 1` → `Profile 1`; `2aldte6y.default-release` → `default-release`.
    static func displayName(fromProfileFolder folderName: String) -> String {
        if let dot = folderName.firstIndex(of: "."),
           folderName.index(after: dot) < folderName.endIndex {
            return String(folderName[folderName.index(after: dot)...])
        }
        return folderName
    }

    private static func profileDirectoriesOnDisk() -> [URL] {
        let profilesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox/Profiles")
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: profilesDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return children.filter { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                && isDir.boolValue
        }
    }

    private static func discoverProfilesOnDisk() -> [FirefoxProfile] {
        profileDirectoriesOnDisk().compactMap { url in
            // `times.json` alone is not enough — Firefox leaves stub folders (e.g. unused
            // `*.default`) that only have times.json + a stale .parentlock.
            guard hasPrefsJS(at: url) else { return nil }
            return FirefoxProfile(
                name: displayName(fromProfileFolder: url.lastPathComponent),
                path: url,
                isDefault: false
            )
        }
    }

    private static func standardizedPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }

    // MARK: - Running Instance Detection

    /// Detect which Firefox profiles are currently running.
    /// Never shells out to `ps`/`pgrep`.
    static func detectRunningProfiles() -> [String: FirefoxProfile] {
        detectRunningProfiles(among: detectFirefoxProfiles())
    }

    /// Same as `detectRunningProfiles()` but reuses an already-fetched profile list.
    static func detectRunningProfiles(among profiles: [FirefoxProfile]) -> [String: FirefoxProfile] {
        var result: [String: FirefoxProfile] = [:]
        for profile in profiles {
            if isProfileRunning(profile) {
                result[profile.name] = profile
            }
        }
        return result
    }

    /// True when a live Firefox process owns this profile.
    ///
    /// Prefers libproc (PID has `.parentlock` open) so concurrent Roocast index
    /// scans cannot false-positive via briefly holding flock themselves.
    static func isProfileRunning(_ profile: FirefoxProfile) -> Bool {
        if pidHoldingParentLock(at: profile.path) != nil {
            return true
        }
        // Fallback: exclusive flock (ignore non-EWOULDBLOCK errors).
        if isParentLockHeld(at: profile.path) {
            return true
        }
        // Older Firefox: `lock` symlink → "host:pid"
        return isLegacyLockSymlinkAlive(at: profile.path)
    }

    /// Probe whether `.parentlock` is exclusively flocked by another process.
    static func isParentLockHeld(at profileDirectory: URL) -> Bool {
        let lockPath = profileDirectory.appendingPathComponent(".parentlock").path
        let fd = open(lockPath, O_RDWR)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            // Acquired → nobody else holds it → not running.
            flock(fd, LOCK_UN)
            return false
        }
        // Only EWOULDBLOCK/EAGAIN mean another process holds the lock.
        // Other errno values (and races with our own probes) must not count as "running".
        return errno == EWOULDBLOCK || errno == EAGAIN
    }

    /// PID of the Firefox process that has this profile's `.parentlock` open.
    /// Used to activate the correct instance when several Firefoxes share one bundle ID.
    static func pidHoldingParentLock(at profileDirectory: URL) -> pid_t? {
        let lockPath = standardizedPath(profileDirectory.appendingPathComponent(".parentlock"))
        let firefoxPIDs = NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == "org.mozilla.firefox" && !$0.isTerminated }
            .map(\.processIdentifier)

        for pid in firefoxPIDs {
            if process(pid, hasOpenPath: lockPath) {
                return pid
            }
        }
        return nil
    }

    private static func process(_ pid: pid_t, hasOpenPath targetPath: String) -> Bool {
        let fdSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard fdSize > 0 else { return false }

        let fdCount = Int(fdSize) / MemoryLayout<proc_fdinfo>.size
        var fds = [proc_fdinfo](repeating: proc_fdinfo(proc_fd: 0, proc_fdtype: 0), count: fdCount)
        let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, fdSize)
        guard got > 0 else { return false }

        let actual = Int(got) / MemoryLayout<proc_fdinfo>.size
        for i in 0..<actual {
            guard fds[i].proc_fdtype == PROX_FDTYPE_VNODE else { continue }
            var buf = [UInt8](repeating: 0, count: 4096)
            let r = buf.withUnsafeMutableBytes { raw -> Int32 in
                proc_pidfdinfo(pid, fds[i].proc_fd, PROC_PIDFDVNODEPATHINFO, raw.baseAddress, Int32(raw.count))
            }
            guard r > 0 else { continue }
            if bufferContainsPath(buf, targetPath) {
                return true
            }
        }
        return false
    }

    private static func bufferContainsPath(_ buf: [UInt8], _ targetPath: String) -> Bool {
        buf.withUnsafeBufferPointer { bp in
            var idx = 0
            while idx < bp.count {
                if bp[idx] == 0 {
                    idx += 1
                    continue
                }
                var end = idx
                while end < bp.count && bp[end] != 0 { end += 1 }
                if end > idx,
                   let str = String(bytes: bp[idx..<end], encoding: .utf8),
                   str == targetPath {
                    return true
                }
                idx = end + 1
            }
            return false
        }
    }

    private static func isLegacyLockSymlinkAlive(at profileDirectory: URL) -> Bool {
        let lockURL = profileDirectory.appendingPathComponent("lock")
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: lockURL.path) else {
            return false
        }
        // Destination looks like "127.0.0.1:12345" or "+12345"
        guard let colon = destination.lastIndex(of: ":") else { return false }
        let pidString = String(destination[destination.index(after: colon)...])
        guard let pid = pid_t(pidString), pid > 0 else { return false }
        return kill(pid, 0) == 0
    }

    // MARK: - Instance Count

    static func countFirefoxInstances() -> Int {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == "org.mozilla.firefox" }
            .count
    }
}
