import SwiftUI
import AppKit

final class LauncherPanel: NSPanel {
    private let panelWidth: CGFloat = 860
    private let panelHeight: CGFloat = 560
    
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onEnter: (() -> Void)?
    let navigationState: NavigationState

    init(navigationState: NavigationState) {
        self.navigationState = navigationState
        
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false

        // Center at top of main screen (Spotlight-style)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panelWidth / 2
            let y = screenFrame.maxY - panelHeight - 80
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

    func show() {
        setContentSize(NSSize(width: panelWidth, height: panelHeight))
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Intercept events BEFORE they reach any view (including TextField)
    override func sendEvent(_ event: NSEvent) {
        // Handle both keyDown (10) and keyUp (11) to catch arrow keys
        if event.type == .keyDown || event.type == .keyUp {
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
