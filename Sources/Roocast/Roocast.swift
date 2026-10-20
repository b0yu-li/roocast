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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: LauncherPanel?
    private var clipboardPanel: ClipboardPanel?
    private var hotKeyManager: HotKeyManager?
    private var navigationState = NavigationState()
    private var clipboardNavigationState = NavigationState()
    private let clipboardStore = ClipboardStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPanel()
        setupClipboardPanel()
        setupHotKey()
        clipboardStore.startMonitoring()
        showPanel()
    }

    private func setupPanel() {
        panel = LauncherPanel(navigationState: navigationState)

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

    private func setupClipboardPanel() {
        clipboardPanel = ClipboardPanel(
            store: clipboardStore,
            navigationState: clipboardNavigationState,
            onPaste: { [weak self] item in
                self?.pasteClipboardItem(item)
            }
        )

        clipboardPanel?.onArrowUp = { [weak self] in
            Task { @MainActor in
                self?.clipboardNavigationState.moveUp()
            }
        }
        clipboardPanel?.onArrowDown = { [weak self] in
            Task { @MainActor in
                self?.clipboardNavigationState.moveDown()
            }
        }
        clipboardPanel?.onEnter = {
            Task { @MainActor in
                NotificationCenter.default.post(name: .pasteSelectedClipboardItem, object: nil)
            }
        }
    }

    private func setupHotKey() {
        hotKeyManager = HotKeyManager(
            onLauncherToggle: { [weak self] in
                self?.togglePanel()
            },
            onClipboardToggle: { [weak self] in
                self?.toggleClipboardPanel()
            }
        )
    }

    private func togglePanel() {
        guard let panel else { return }
        // Mutually exclusive with clipboard panel.
        if clipboardPanel?.isVisible == true {
            clipboardPanel?.hide(restoreFocus: false)
        }
        if panel.isVisible {
            panel.hide(restoreFocus: true)
        } else {
            panel.show()
        }
    }

    private func toggleClipboardPanel() {
        guard let clipboardPanel else { return }
        if panel?.isVisible == true {
            panel?.hide(restoreFocus: false)
        }
        if clipboardPanel.isVisible {
            clipboardPanel.hide(restoreFocus: true)
        } else {
            FocusRestorer.log("clipboard: ⌘Esc toggle → show")
            clipboardPanel.show()
        }
    }

    private func pasteClipboardItem(_ item: ClipboardItem) {
        FocusRestorer.log("clipboard: paste selected len=\(item.text.count)")
        clipboardStore.copyToPasteboard(item.text)
        let target = clipboardPanel?.hideForPaste()
        // Give the target app a beat to become frontmost before synthesizing ⌘V.
        let delay: TimeInterval = target == nil ? 0.12 : 0.08
        ClipboardPaster.pasteCommandV(after: delay)
    }

    private func showPanel() {
        guard let panel else { return }
        panel.show()
    }
}

extension Notification.Name {
    static let launchSelectedApp = Notification.Name("launchSelectedApp")
    static let launcherWillShow = Notification.Name("launcherWillShow")
    static let pasteSelectedClipboardItem = Notification.Name("pasteSelectedClipboardItem")
    static let clipboardWillShow = Notification.Name("clipboardWillShow")
}
