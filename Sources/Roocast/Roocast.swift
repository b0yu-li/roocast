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
    private var textExpander: TextExpander?
    private var appToggleMonitor: AppToggleMonitor?
    private var navigationState = NavigationState()
    private var clipboardNavigationState = NavigationState()
    private let clipboardStore = ClipboardStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupPanel()
        setupClipboardPanel()
        setupHotKey()
        clipboardStore.startMonitoring()
        let expander = TextExpander()
        expander.start()
        textExpander = expander
        let toggles = AppToggleMonitor()
        toggles.start()
        appToggleMonitor = toggles
        panel?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appToggleMonitor?.stop()
        appToggleMonitor = nil
        textExpander?.stop()
        textExpander = nil
        clipboardStore.stopMonitoring()
    }

    private func setupPanel() {
        let panel = LauncherPanel(navigationState: navigationState)
        wireNavigation(panel, state: navigationState, enterNotification: .launchSelectedApp)
        self.panel = panel
    }

    private func setupClipboardPanel() {
        let clipboardPanel = ClipboardPanel(
            store: clipboardStore,
            navigationState: clipboardNavigationState,
            onPaste: { [weak self] item in
                self?.pasteClipboardItem(item)
            }
        )
        wireNavigation(
            clipboardPanel,
            state: clipboardNavigationState,
            enterNotification: .pasteSelectedClipboardItem
        )
        self.clipboardPanel = clipboardPanel
    }

    private func wireNavigation(
        _ panel: FloatingPanel,
        state: NavigationState,
        enterNotification: Notification.Name
    ) {
        panel.onArrowUp = { [weak state] in
            state?.moveUp()
        }
        panel.onArrowDown = { [weak state] in
            state?.moveDown()
        }
        panel.onEnter = {
            NotificationCenter.default.post(name: enterNotification, object: nil)
        }
    }

    private func setupHotKey() {
        // Carbon hotkey callbacks may arrive off the main actor — hop explicitly.
        hotKeyManager = HotKeyManager(
            onLauncherToggle: { [weak self] in
                Task { @MainActor in
                    self?.togglePanel()
                }
            },
            onClipboardToggle: { [weak self] in
                Task { @MainActor in
                    self?.toggleClipboardPanel()
                }
            }
        )
    }

    private func togglePanel() {
        guard let panel else { return }
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
        // At most one Accessibility sheet per process — never on every Enter.
        _ = FocusRestorer.ensureTrusted(prompt: true)
        clipboardStore.copyToPasteboard(item.text)
        let target = clipboardPanel?.hideForPaste()
        // Target needs a moment to become key before synthetic ⌘V lands.
        let delay: TimeInterval = target == nil ? 0.2 : 0.15
        ClipboardPaster.pasteCommandV(after: delay)
    }
}

extension Notification.Name {
    static let launchSelectedApp = Notification.Name("launchSelectedApp")
    static let launcherWillShow = Notification.Name("launcherWillShow")
    static let pasteSelectedClipboardItem = Notification.Name("pasteSelectedClipboardItem")
    static let clipboardWillShow = Notification.Name("clipboardWillShow")
}
