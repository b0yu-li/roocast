import AppKit
import ApplicationServices

/// Activates an already-running app and restores its minimized/hidden windows.
///
/// `NSWorkspace.open` (and a bare `activate()`) will make a background app
/// "active", but on Sonoma+ it does **not** unminimize Dock-minimized windows —
/// the app takes focus while every window stays in the Dock, which reads as
/// "it won't open". We restore windows explicitly via Accessibility so behavior
/// is uniform across apps (Firefox included).
///
/// Every step is logged to `~/Library/Logs/Roocast/focus.log` so failures are
/// observable, not guessed at.
@MainActor
enum AppActivator {

    /// If the app at `appPath` is already running, activate + restore its
    /// windows. Otherwise launch it normally.
    static func activateOrLaunch(appPath: String) {
        let bundleID = Bundle(url: URL(fileURLWithPath: appPath))?.bundleIdentifier
        log("activateOrLaunch path=\(appPath) bundleID=\(bundleID ?? "nil")")

        if let app = runningApp(bundleID: bundleID) {
            restore(app)
            return
        }

        log("no running instance — falling back to NSWorkspace.open")
        let url = URL(fileURLWithPath: appPath)
        NSWorkspace.shared.open(url)
    }

    /// Activate a running app and bring its windows out of the Dock / off-screen.
    static func restore(_ app: NSRunningApplication) {
        let name = app.localizedName ?? "?"
        let pid = app.processIdentifier
        log("restore \(name) pid=\(pid) hidden=\(app.isHidden) active=\(app.isActive)")

        if app.isHidden {
            app.unhide()
            log("\(name): was hidden — unhide()")
        }

        app.activate(options: [.activateAllWindows])
        unminimizeDockWindows(pid: pid, name: name)
    }

    private static func runningApp(bundleID: String?) -> NSRunningApplication? {
        guard let bundleID else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == bundleID && !$0.isTerminated
        }
    }

    /// AXRaise on a Dock-minimized window unminimizes and focuses it.
    private static func unminimizeDockWindows(pid: pid_t, name: String) {
        guard FocusRestorer.isTrusted() else {
            log("\(name): accessibility untrusted — cannot unminimize windows")
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
                == .success,
              let windows = value as? [AXUIElement]
        else {
            log("\(name): could not read AX windows")
            return
        }

        var restored = 0
        var visible = 0
        for window in windows {
            var minimizedRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                window, kAXMinimizedAttribute as CFString, &minimizedRef
            ) == .success else { continue }

            if (minimizedRef as? Bool) == true {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                restored += 1
            } else {
                visible += 1
            }
        }
        log("\(name): windows total=\(windows.count) visible=\(visible) unminimized=\(restored)")
    }

    private static func log(_ message: String) {
        FocusRestorer.log(message)
    }
}
