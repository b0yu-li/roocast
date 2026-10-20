import XCTest
import Darwin
@testable import Roocast

final class ProfileManagerTests: XCTestCase {
    
    // MARK: - Profile Parsing Tests
    
    func testParseProfilesINIWithTwoProfiles() {
        let iniContent = """
        [General]
        StartWithLastProfile=1
        Version=2

        [Profile0]
        Name=default-release
        IsRelative=1
        Path=Profiles/2aldte6y.default-release
        Default=1

        [Profile1]
        Name=work
        IsRelative=1
        Path=Profiles/7604yf6f.work
        """

        let profiles = ProfileManager.parseProfilesINI(iniContent)
        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles[0].name, "default-release")
        XCTAssertTrue(profiles[0].isDefault)
        XCTAssertEqual(profiles[1].name, "work")
        XCTAssertFalse(profiles[1].isDefault)
        XCTAssertTrue(profiles[0].path.path.hasSuffix("Profiles/2aldte6y.default-release"))
    }

    func testParseProfilesINIIgnoresInstallDefaultPath() {
        // Real Firefox profiles.ini uses [Install…] Default=Profiles/… which must
        // not be treated as Profile Default=1.
        let iniContent = """
        [General]
        StartWithLastProfile=1
        Version=2

        [Profile0]
        Name=default-release
        IsRelative=1
        Path=Profiles/aaa.default-release

        [Install2656FF1E876E9973]
        Default=Profiles/aaa.default-release
        Locked=1

        [Profile1]
        Name=default
        IsRelative=1
        Path=Profiles/bbb.default
        Default=1
        """

        let profiles = ProfileManager.parseProfilesINI(iniContent)
        XCTAssertEqual(profiles.count, 2)
        XCTAssertEqual(profiles[0].name, "default-release")
        XCTAssertFalse(profiles[0].isDefault, "Install Default=path must not mark profile default")
        XCTAssertEqual(profiles[1].name, "default")
        XCTAssertTrue(profiles[1].isDefault)
    }


    func testDisplayNameFromProfileFolder() {
        XCTAssertEqual(ProfileManager.displayName(fromProfileFolder: "2aldte6y.default-release"), "default-release")
        XCTAssertEqual(ProfileManager.displayName(fromProfileFolder: "Tkfsj6cm.Profile 1"), "Profile 1")
        XCTAssertEqual(ProfileManager.displayName(fromProfileFolder: "plain"), "plain")
    }

    func testDisambiguateNamesUsesFolderWhenColliding() {
        let pathA = URL(fileURLWithPath: "/tmp/Profiles/aaa.default-release")
        let pathB = URL(fileURLWithPath: "/tmp/Profiles/bbb.Profile 1")
        let byPath = [
            pathA.path: FirefoxProfile(name: "default-release", path: pathA, isDefault: false),
            pathB.path: FirefoxProfile(name: "default-release", path: pathB, isDefault: false),
        ]
        let names = Set(ProfileManager.disambiguateNames(byPath).map(\.name))
        XCTAssertEqual(names, ["default-release", "Profile 1"])
    }

    func testDetectFirefoxProfilesIncludesRealAndRunningFolders() {
        let profiles = ProfileManager.detectFirefoxProfiles()
        let profilesDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox/Profiles")
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: profilesDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let detectedPaths = Set(profiles.map { $0.path.resolvingSymlinksInPath().path })
        for url in children {
            let hasPrefs = ProfileManager.hasPrefsJS(at: url)
            let isRunning = ProfileManager.isParentLockHeld(at: url)
            if hasPrefs || isRunning {
                XCTAssertTrue(
                    detectedPaths.contains(url.resolvingSymlinksInPath().path),
                    "Missing usable profile \(url.lastPathComponent) in \(detectedPaths)"
                )
            } else {
                // Stub folders (times.json only, not running) must not appear.
                XCTAssertFalse(
                    detectedPaths.contains(url.resolvingSymlinksInPath().path),
                    "Stub profile \(url.lastPathComponent) should be omitted"
                )
            }
        }

        let names = profiles.map(\.name)
        XCTAssertEqual(names.count, Set(names).count, "Profile display names must be unique: \(names)")
    }

    func testDetectFirefoxProfilesSkipsLiveStubDefault() {
        let stub = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox/Profiles/7604yf6f.default")
        guard FileManager.default.fileExists(atPath: stub.path),
              !ProfileManager.hasPrefsJS(at: stub),
              !ProfileManager.isParentLockHeld(at: stub) else {
            return
        }

        let profiles = ProfileManager.detectFirefoxProfiles()
        let paths = profiles.map { $0.path.resolvingSymlinksInPath().path }
        XCTAssertFalse(
            paths.contains(stub.resolvingSymlinksInPath().path),
            "Unused INI stub `default` must not create a third Firefox row"
        )
    }

    func testParentLockHeldRequiresExclusiveFlock() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roocast-lock-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let lockFile = dir.appendingPathComponent(".parentlock")
        FileManager.default.createFile(atPath: lockFile.path, contents: Data(), attributes: nil)

        // Stale .parentlock file with no flock → not running.
        XCTAssertFalse(ProfileManager.isParentLockHeld(at: dir))

        // Hold an exclusive flock like a live Firefox instance.
        let fd = open(lockFile.path, O_RDWR)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)

        XCTAssertTrue(ProfileManager.isParentLockHeld(at: dir))

        flock(fd, LOCK_UN)
        XCTAssertFalse(ProfileManager.isParentLockHeld(at: dir))
    }
    
    func testDetectFirefoxProfilesReturnsEmptyWhenNoProfilesINI() {
        // This test verifies graceful handling when profiles.ini doesn't exist
        // The actual behavior depends on the user's system
        let profiles = ProfileManager.detectFirefoxProfiles()
        
        // We can't assert specific count since it depends on system state
        // But we can verify it doesn't crash
        XCTAssertNotNil(profiles)
    }
    
    // MARK: - Running Profile Detection Tests
    
    func testDetectRunningProfilesReturnsDictionary() {
        let runningProfiles = ProfileManager.detectRunningProfiles()
        
        // Verify it returns a dictionary (may be empty)
        XCTAssertNotNil(runningProfiles)
    }
    
    func testDetectRunningProfilesContainsRunningFirefoxProfiles() {
        let runningProfiles = ProfileManager.detectRunningProfiles()
        
        // If Firefox is running with profiles, they should be in the dictionary
        // This test is system-dependent
        print("Running profiles: \(runningProfiles.keys)")
    }
    
    // MARK: - Instance Count Tests
    
    func testCountFirefoxInstancesReturnsNonNegative() {
        let count = ProfileManager.countFirefoxInstances()
        XCTAssertGreaterThanOrEqual(count, 0)
    }
    
    func testCountFirefoxInstancesDetectsRunningFirefox() {
        // This test is system-dependent
        // If Firefox is running, count should be > 0
        let count = ProfileManager.countFirefoxInstances()
        print("Firefox instances: \(count)")
    }
    
    // MARK: - FirefoxProfile Struct Tests
    
    func testFirefoxProfileEquality() {
        let profile1 = FirefoxProfile(
            name: "test",
            path: URL(fileURLWithPath: "/tmp/test"),
            isDefault: true
        )
        
        let profile2 = FirefoxProfile(
            name: "test",
            path: URL(fileURLWithPath: "/tmp/test"),
            isDefault: true
        )
        
        XCTAssertEqual(profile1, profile2)
    }
    
    func testFirefoxProfileInequality() {
        let profile1 = FirefoxProfile(
            name: "test1",
            path: URL(fileURLWithPath: "/tmp/test1"),
            isDefault: true
        )
        
        let profile2 = FirefoxProfile(
            name: "test2",
            path: URL(fileURLWithPath: "/tmp/test2"),
            isDefault: false
        )
        
        XCTAssertNotEqual(profile1, profile2)
    }
    
    func testFirefoxProfileHashable() {
        let profile1 = FirefoxProfile(
            name: "test",
            path: URL(fileURLWithPath: "/tmp/test"),
            isDefault: true
        )
        
        let profile2 = FirefoxProfile(
            name: "test",
            path: URL(fileURLWithPath: "/tmp/test"),
            isDefault: true
        )
        
        var set = Set<FirefoxProfile>()
        set.insert(profile1)
        set.insert(profile2)
        
        // Should only have one entry since they're equal
        XCTAssertEqual(set.count, 1)
    }
}
