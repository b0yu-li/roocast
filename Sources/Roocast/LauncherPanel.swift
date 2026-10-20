import SwiftUI
import AppKit

final class LauncherPanel: NSPanel {
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onEnter: (() -> Void)?
    let navigationState: NavigationState

    init(navigationState: NavigationState) {
        self.navigationState = navigationState
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: LauncherLayout.width, height: LauncherLayout.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        // Spotlight-style: click another app / lose focus hides the panel.
        hidesOnDeactivate = true

        // Center at top of main screen (Spotlight-style)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - LauncherLayout.width / 2
            let y = screenFrame.maxY - LauncherLayout.height - 80
            setFrameOrigin(NSPoint(x: x, y: y))
        }

        // SwiftUI content
        let contentView = ContentView(
            navigationState: navigationState,
            onDismiss: { [weak self] in
                self?.orderOut(nil)
            }
        )
        contentViewController = NSHostingController(rootView: contentView)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func resignKey() {
        super.resignKey()
        // Click-away / focus loss: hide even if the app stays accessory-active.
        if isVisible {
            orderOut(nil)
        }
    }

    func show() {
        setContentSize(NSSize(width: LauncherLayout.width, height: LauncherLayout.height))
        // Refresh running-app / Firefox-profile state each open.
        NotificationCenter.default.post(name: .launcherWillShow, object: nil)
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Intercept events BEFORE they reach any view (including TextField)
    override func sendEvent(_ event: NSEvent) {
        // Only handle keyDown (not keyUp) to avoid double-firing
        if event.type == .keyDown {
            switch event.keyCode {
            case 126:
                onArrowUp?()
                return
            case 125:
                onArrowDown?()
                return
            case 36:
                onEnter?()
                return
            case 53:
                orderOut(nil)
                return
            default:
                break
            }
        }
        super.sendEvent(event)
    }
}
