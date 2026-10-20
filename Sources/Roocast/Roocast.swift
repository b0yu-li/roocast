import SwiftUI
import AppKit

@main
struct Roocast {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // No Dock icon
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: LauncherPanel?
    private var hotKeyManager: HotKeyManager?
    private var navigationState = NavigationState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPanel()
        setupHotKey()
        showPanel()
    }

    private func setupPanel() {
        panel = LauncherPanel(navigationState: navigationState)
        
        // Wire up arrow key handlers from panel's sendEvent
        panel?.onArrowUp = { [weak self] in
            Task { @MainActor in
                self?.navigationState.moveUp()
            }
        }
        panel?.onArrowDown = { [weak self] in
            Task { @MainActor in
                self?.navigationState.moveDown()
            }
        }
        panel?.onEnter = {
            Task { @MainActor in
                NotificationCenter.default.post(name: .launchSelectedApp, object: nil)
            }
        }
    }

    private func setupHotKey() {
        hotKeyManager = HotKeyManager { [weak self] in
            self?.togglePanel()
        }
    }

    private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            // Escape / hotkey dismiss: hide without stealing Ghostty tab focus when possible.
            panel.hide(restoreFocus: true)
        } else {
            panel.show()
        }
    }

    private func showPanel() {
        guard let panel else { return }
        panel.show()
    }
}

extension Notification.Name {
    static let launchSelectedApp = Notification.Name("launchSelectedApp")
    static let launcherWillShow = Notification.Name("launcherWillShow")
}
