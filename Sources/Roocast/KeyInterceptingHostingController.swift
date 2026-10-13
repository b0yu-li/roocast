import SwiftUI
import AppKit

final class KeyInterceptingHostingController<Content: View>: NSHostingController<Content> {
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onEnter: (() -> Void)?
    var onEscape: (() -> Void)?
    
    override func keyDown(with event: NSEvent) {
        print("[DEBUG] KeyInterceptingHostingController.keyDown received keyCode: \(event.keyCode)")
        
        switch event.keyCode {
        case 126: // Up arrow
            print("[DEBUG] Up arrow intercepted in hosting controller")
            onArrowUp?()
        case 125: // Down arrow
            print("[DEBUG] Down arrow intercepted in hosting controller")
            onArrowDown?()
        case 36: // Return/Enter
            print("[DEBUG] Enter intercepted in hosting controller")
            onEnter?()
        case 53: // Escape
            print("[DEBUG] Escape intercepted in hosting controller")
            onEscape?()
        default:
            super.keyDown(with: event)
        }
    }
    
    override func interpretKeyEvents(_ events: [NSEvent]) {
        print("[DEBUG] interpretKeyEvents called with \(events.count) events")
        for event in events {
            print("[DEBUG]   Event keyCode: \(event.keyCode), type: \(event.type.rawValue)")
        }
        super.interpretKeyEvents(events)
    }
}
