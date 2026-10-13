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

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPanel()
        setupHotKey()
        showPanel()
    }

    private func setupPanel() {
        panel = LauncherPanel()
    }

    private func setupHotKey() {
        hotKeyManager = HotKeyManager { [weak self] in
            self?.togglePanel()
        }
    }

    private func togglePanel() {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.show()
        }
    }

    private func showPanel() {
        guard let panel else { return }
        panel.show()
    }
}
