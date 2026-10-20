import Carbon
import AppKit

/// Carbon hotkey IDs registered by `HotKeyManager`.
enum HotKeyID: UInt32 {
    case launcher = 1
    case clipboard = 2
}

// Global event handler for hotkeys (cannot be a closure due to C function pointer requirement)
private func hotKeyEventHandler(_: EventHandlerCallRef?, _ event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event = event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    GetEventParameter(
        event,
        EventParamType(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    switch HotKeyID(rawValue: hotKeyID.id) {
    case .launcher:
        HotKeyManager.activeManager?.onLauncherToggle()
    case .clipboard:
        HotKeyManager.activeManager?.onClipboardToggle()
    case .none:
        break
    }

    return noErr
}

/// Registers global Carbon hotkeys: ⌘Space (launcher) and ⌘Esc (clipboard).
final class HotKeyManager {
    private var launcherHotKeyRef: EventHotKeyRef?
    private var clipboardHotKeyRef: EventHotKeyRef?
    let onLauncherToggle: () -> Void
    let onClipboardToggle: () -> Void
    static var activeManager: HotKeyManager?

    init(onLauncherToggle: @escaping () -> Void, onClipboardToggle: @escaping () -> Void) {
        self.onLauncherToggle = onLauncherToggle
        self.onClipboardToggle = onClipboardToggle
        HotKeyManager.activeManager = self
        installHandlerIfNeeded()
        registerHotKeys()
    }

    deinit {
        unregisterHotKeys()
        HotKeyManager.activeManager = nil
    }

    private static var didInstallHandler = false

    private func installHandlerIfNeeded() {
        guard !Self.didInstallHandler else { return }
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            [eventType],
            nil,
            nil
        )
        Self.didInstallHandler = true
    }

    private func registerHotKeys() {
        // Signature "ROOT"
        let signature = OSType(0x524F4F54)

        var launcherID = EventHotKeyID()
        launcherID.signature = signature
        launcherID.id = HotKeyID.launcher.rawValue

        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey),
            launcherID,
            GetApplicationEventTarget(),
            0,
            &launcherHotKeyRef
        )

        var clipboardID = EventHotKeyID()
        clipboardID.signature = signature
        clipboardID.id = HotKeyID.clipboard.rawValue

        // ⌘Esc — same pattern Raycast uses; Carbon claims the combo while Roocast runs.
        RegisterEventHotKey(
            UInt32(kVK_Escape),
            UInt32(cmdKey),
            clipboardID,
            GetApplicationEventTarget(),
            0,
            &clipboardHotKeyRef
        )
    }

    private func unregisterHotKeys() {
        if let ref = launcherHotKeyRef {
            UnregisterEventHotKey(ref)
            launcherHotKeyRef = nil
        }
        if let ref = clipboardHotKeyRef {
            UnregisterEventHotKey(ref)
            clipboardHotKeyRef = nil
        }
    }
}
