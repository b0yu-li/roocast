import Carbon
import AppKit

// Global event handler for hotkey (cannot be a closure due to C function pointer requirement)
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
    
    if hotKeyID.id == 1 {
        HotKeyManager.activeManager?.onToggle()
    }
    
    return noErr
}

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    let onToggle: () -> Void
    static var activeManager: HotKeyManager?
    
    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        HotKeyManager.activeManager = self
        registerHotKey()
    }
    
    deinit {
        unregisterHotKey()
        HotKeyManager.activeManager = nil
    }
    
    private func registerHotKey() {
        // Register CMD+Space
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x524F4F54) // "ROOT"
        hotKeyID.id = 1
        
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)
        
        // Install event handler
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            [eventType],
            nil,
            nil
        )
        
        // Register the hotkey (CMD+Space)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
    
    private func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
