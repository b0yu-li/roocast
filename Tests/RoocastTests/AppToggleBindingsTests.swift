import XCTest
import Carbon.HIToolbox
@testable import Roocast

final class AppToggleBindingsTests: XCTestCase {
    func testParseGhosttyToggle() throws {
        let toml = """
        # App toggles
        [[toggle]]
        key = "t"
        modifiers = ["leftControl"]
        app = "Ghostty"
        bundle_id = "com.mitchellh.ghostty"
        """
        let bindings = try AppToggleBindings.parse(toml)
        XCTAssertEqual(bindings.count, 1)
        let b = bindings[0]
        XCTAssertEqual(b.key, "t")
        XCTAssertEqual(b.keyCode, UInt16(kVK_ANSI_T))
        XCTAssertEqual(b.modifiers, [.leftControl])
        XCTAssertEqual(b.appName, "Ghostty")
        XCTAssertEqual(b.bundleID, "com.mitchellh.ghostty")
    }

    func testParseMultipleAndIgnoresComments() throws {
        let toml = """
        [[toggle]]
        key = "t"
        modifiers = ["leftControl"]
        app = "Ghostty"

        # chrome
        [[toggle]]
        key = "c"
        modifiers = ["leftControl"]
        bundle_id = "com.google.Chrome"
        """
        let bindings = try AppToggleBindings.parse(toml)
        XCTAssertEqual(bindings.count, 2)
        XCTAssertEqual(bindings[0].appName, "Ghostty")
        XCTAssertEqual(bindings[1].bundleID, "com.google.Chrome")
        XCTAssertNil(bindings[1].appName)
    }

    func testParseRejectsMissingTarget() {
        let toml = """
        [[toggle]]
        key = "t"
        modifiers = ["leftControl"]
        """
        XCTAssertThrowsError(try AppToggleBindings.parse(toml)) { error in
            XCTAssertEqual(error as? AppToggleBindingsError, .missingTarget)
        }
    }

    func testParseRejectsUnknownModifier() {
        let toml = """
        [[toggle]]
        key = "t"
        modifiers = ["hyper"]
        app = "Ghostty"
        """
        XCTAssertThrowsError(try AppToggleBindings.parse(toml)) { error in
            XCTAssertEqual(error as? AppToggleBindingsError, .unknownModifier("hyper"))
        }
    }

    func testMatchLeftControlWithDeviceFlag() throws {
        let bindings = try AppToggleBindings.parse(
            """
            [[toggle]]
            key = "t"
            modifiers = ["leftControl"]
            app = "Ghostty"
            """
        )
        let binding = bindings[0]
        let leftFlag =
            CGEventFlags.maskControl.rawValue | AppToggleBindings.leftControlDeviceMask

        XCTAssertTrue(
            AppToggleBindings.matches(
                binding,
                keyCode: UInt16(kVK_ANSI_T),
                flagsRaw: leftFlag,
                isKeyEvent: true,
                isAutorepeat: false,
                leftControlDown: nil
            )
        )
        // Right Control device bit alone — no match
        let rightFlag =
            CGEventFlags.maskControl.rawValue | AppToggleBindings.rightControlDeviceMask
        XCTAssertFalse(
            AppToggleBindings.matches(
                binding,
                keyCode: UInt16(kVK_ANSI_T),
                flagsRaw: rightFlag,
                isKeyEvent: true,
                isAutorepeat: false,
                leftControlDown: nil
            )
        )
        // Tracker fallback when device bits absent
        XCTAssertTrue(
            AppToggleBindings.matches(
                binding,
                keyCode: UInt16(kVK_ANSI_T),
                flagsRaw: CGEventFlags.maskControl.rawValue,
                isKeyEvent: true,
                isAutorepeat: false,
                leftControlDown: true
            )
        )
        XCTAssertFalse(
            AppToggleBindings.matches(
                binding,
                keyCode: UInt16(kVK_ANSI_T),
                flagsRaw: CGEventFlags.maskControl.rawValue,
                isKeyEvent: true,
                isAutorepeat: false,
                leftControlDown: false
            )
        )
        // ⌘ rejects
        XCTAssertFalse(
            AppToggleBindings.matches(
                binding,
                keyCode: UInt16(kVK_ANSI_T),
                flagsRaw: leftFlag | CGEventFlags.maskCommand.rawValue,
                isKeyEvent: true,
                isAutorepeat: false,
                leftControlDown: true
            )
        )
        // Autorepeat ignored
        XCTAssertFalse(
            AppToggleBindings.matches(
                binding,
                keyCode: UInt16(kVK_ANSI_T),
                flagsRaw: leftFlag,
                isKeyEvent: true,
                isAutorepeat: true,
                leftControlDown: true
            )
        )
    }

    func testResolveURLFindsGhosttyByBundleID() {
        let url = AppToggleAction.resolveURL(
            bundleID: "com.mitchellh.ghostty",
            appName: nil
        )
        XCTAssertEqual(url?.path, "/Applications/Ghostty.app")
    }

    func testResolveURLFindsGhosttyByName() {
        let url = AppToggleAction.resolveURL(bundleID: nil, appName: "Ghostty")
        XCTAssertEqual(url?.path, "/Applications/Ghostty.app")
    }

    func testLoadMissingFileReturnsEmpty() throws {
        let url = URL(fileURLWithPath: "/tmp/roocast-missing-bindings-\(UUID().uuidString).toml")
        let bindings = try AppToggleBindings.load(from: url)
        XCTAssertTrue(bindings.isEmpty)
    }
}
