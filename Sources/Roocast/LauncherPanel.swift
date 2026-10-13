import SwiftUI
import AppKit

final class LauncherPanel: NSPanel {
    private let panelWidth: CGFloat = 860
    private let panelHeight: CGFloat = 560

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
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
        let contentView = ContentView(onDismiss: { [weak self] in
            self?.orderOut(nil)
        })
        contentViewController = NSHostingController(rootView: contentView)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func show() {
        // Ensure panel is the correct size
        setContentSize(NSSize(width: panelWidth, height: panelHeight))
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            orderOut(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}
