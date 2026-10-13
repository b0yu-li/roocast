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

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPanel()
        showPanel()
    }

    private func setupPanel() {
        panel = LauncherPanel()
    }

    func showPanel() {
        guard let panel else { return }
        panel.show()
    }
}
