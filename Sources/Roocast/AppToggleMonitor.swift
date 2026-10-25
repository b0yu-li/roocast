import AppKit
import Carbon.HIToolbox

/// CGEvent tap callback — must be a free function (C convention).
private func appToggleCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<AppToggleMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        DispatchQueue.main.async { monitor.tapWasDisabled() }
        return Unmanaged.passUnretained(event)
    }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let flagsRaw = event.flags.rawValue
    let isAutorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

    // Track Left Control via keycode so we can distinguish it when device bits are absent.
    if type == .flagsChanged {
        if keyCode == UInt16(kVK_Control) {
            let left = (flagsRaw & AppToggleBindings.leftControlDeviceMask) != 0
                || (event.flags.contains(.maskControl)
                    && (flagsRaw & AppToggleBindings.rightControlDeviceMask) == 0)
            monitor.setLeftControlDown(left)
        } else if keyCode == UInt16(kVK_RightControl) {
            let leftStill = (flagsRaw & AppToggleBindings.leftControlDeviceMask) != 0
            monitor.setLeftControlDown(leftStill)
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown || type == .keyUp else {
        return Unmanaged.passUnretained(event)
    }

    let leftDown = monitor.leftControlDownSnapshot()
    let binding = AppToggleBindings.binding(
        matchingKeyCode: keyCode,
        flagsRaw: flagsRaw,
        isKeyEvent: true,
        isAutorepeat: isAutorepeat,
        leftControlDown: leftDown,
        in: monitor.bindingsSnapshot()
    )

    guard let binding else {
        return Unmanaged.passUnretained(event)
    }

    // Swallow both down and up so the focused app never sees the chord.
    if type == .keyDown, !isAutorepeat {
        DispatchQueue.main.async {
            monitor.handleToggle(binding)
        }
    }
    return nil
}

/// Global Left-Control app toggles from `~/.config/roocast/bindings.toml`.
///
/// Frontmost matching app → hide; running → activate; else → launch.
/// Needs Accessibility (default tap so chords can be swallowed).
final class AppToggleMonitor: @unchecked Sendable {
    private var bindings: [AppToggleBinding] = []
    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var loggedTapFailure = false
    /// Tap callback reads these under `stateLock` (may run off the main thread).
    private let stateLock = NSLock()
    private var bindingsForTap: [AppToggleBinding] = []
    private var leftControlForTap = false

    @MainActor
    func start() {
        reloadBindings()
        guard !bindings.isEmpty else {
            FocusRestorer.log(
                "apptoggle: no bindings (create \(AppToggleBindings.defaultConfigURL().path))"
            )
            return
        }
        _ = FocusRestorer.ensureTrusted(prompt: true)
        installTapIfPossible()
        FocusRestorer.log(
            "apptoggle: start bindings=\(bindings.count) ax=\(FocusRestorer.isTrusted() ? 1 : 0) tap=\(tapPort != nil ? 1 : 0)"
        )
    }

    @MainActor
    func stop() {
        tearDownTap()
        FocusRestorer.log("apptoggle: stop")
    }

    @MainActor
    func reloadBindings() {
        do {
            let loaded = try AppToggleBindings.load()
            bindings = loaded
            stateLock.lock()
            bindingsForTap = loaded
            stateLock.unlock()
            for b in loaded {
                FocusRestorer.log(
                    "apptoggle: binding leftControl+\(b.key) → \(b.label)"
                )
            }
        } catch {
            bindings = []
            stateLock.lock()
            bindingsForTap = []
            stateLock.unlock()
            FocusRestorer.log("apptoggle: load failed — \(error)")
        }
    }

    fileprivate func bindingsSnapshot() -> [AppToggleBinding] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return bindingsForTap
    }

    fileprivate func leftControlDownSnapshot() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return leftControlForTap
    }

    fileprivate func setLeftControlDown(_ down: Bool) {
        stateLock.lock()
        leftControlForTap = down
        stateLock.unlock()
    }

    @MainActor
    fileprivate func tapWasDisabled() {
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: true)
            FocusRestorer.log("apptoggle: re-enabled tap after disable")
        } else {
            installTapIfPossible()
        }
    }

    @MainActor
    fileprivate func handleToggle(_ binding: AppToggleBinding) {
        let action = AppToggleAction.resolve(
            bundleID: binding.bundleID,
            appName: binding.appName,
            frontmost: NSWorkspace.shared.frontmostApplication,
            running: NSWorkspace.shared.runningApplications
        )
        switch action {
        case .hide(let app):
            let ok = app.hide()
            FocusRestorer.log(
                "apptoggle: hide \(binding.label) pid=\(app.processIdentifier) ok=\(ok)"
            )
        case .activate(let app):
            let ok = app.activate(options: [.activateAllWindows])
            FocusRestorer.log(
                "apptoggle: activate \(binding.label) pid=\(app.processIdentifier) ok=\(ok)"
            )
        case .launch(let url):
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error {
                    FocusRestorer.log("apptoggle: launch failed \(binding.label) — \(error)")
                } else {
                    FocusRestorer.log("apptoggle: launch \(binding.label) path=\(url.path)")
                }
            }
        case .notFound:
            FocusRestorer.log("apptoggle: app not found \(binding.label)")
        }
    }

    @MainActor
    private func installTapIfPossible() {
        guard tapPort == nil else { return }
        guard FocusRestorer.isTrusted() else {
            FocusRestorer.log("apptoggle: tap deferred — Accessibility not trusted")
            return
        }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: appToggleCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            if !loggedTapFailure {
                FocusRestorer.log("apptoggle: failed to create event tap")
                loggedTapFailure = true
            }
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            FocusRestorer.log("apptoggle: failed to create run-loop source")
            return
        }

        tapPort = port
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        loggedTapFailure = false
        FocusRestorer.log("apptoggle: event tap active")
    }

    @MainActor
    private func tearDownTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
            CFMachPortInvalidate(tapPort)
            self.tapPort = nil
        }
    }
}

/// Pure toggle decision for show / hide / launch.
enum AppToggleAction {
    case hide(NSRunningApplication)
    case activate(NSRunningApplication)
    case launch(URL)
    case notFound

    static func resolve(
        bundleID: String?,
        appName: String?,
        frontmost: NSRunningApplication?,
        running: [NSRunningApplication]
    ) -> AppToggleAction {
        let matches: (NSRunningApplication) -> Bool = { app in
            guard app.activationPolicy == .regular, !app.isTerminated else { return false }
            if let bundleID, !bundleID.isEmpty {
                return app.bundleIdentifier == bundleID
            }
            if let appName, !appName.isEmpty {
                return app.localizedName?.caseInsensitiveCompare(appName) == .orderedSame
            }
            return false
        }

        if let frontmost, matches(frontmost) {
            return .hide(frontmost)
        }

        if let runningMatch = running.first(where: matches) {
            return .activate(runningMatch)
        }

        if let url = resolveURL(bundleID: bundleID, appName: appName) {
            return .launch(url)
        }
        return .notFound
    }

    static func resolveURL(bundleID: String?, appName: String?) -> URL? {
        if let bundleID, !bundleID.isEmpty,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }
        if let appName, !appName.isEmpty {
            let fileName = appName.hasSuffix(".app") ? appName : "\(appName).app"
            let roots = [
                URL(fileURLWithPath: "/Applications"),
                URL(fileURLWithPath: "/System/Applications"),
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Applications"),
            ]
            for root in roots {
                let url = root.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                }
            }
        }
        return nil
    }
}
