import SwiftUI
import AppKit

final class LauncherPanel: FloatingPanel {
    let navigationState: NavigationState
    let menuModel = LauncherActionsModel()
    let rankPreferences = SearchRankPreferences()
    let searchSession = SearchSession()
    /// AppDelegate owns the island so it survives launcher hide.
    var onCountdown: ((Int) -> Void)?

    init(navigationState: NavigationState) {
        self.navigationState = navigationState
        super.init(
            size: NSSize(width: LauncherLayout.width, height: LauncherLayout.height),
            willShowNotification: .launcherWillShow,
            logPrefix: ""
        )

        installHostingController(
            ContentView(
                searchSession: searchSession,
                navigationState: navigationState,
                menuModel: menuModel,
                rankPreferences: rankPreferences,
                onDismiss: { [weak self] in
                    // Launch path: target app activates itself.
                    self?.hide(restoreFocus: false)
                },
                onWindowSnap: { [weak self] command in
                    self?.performWindowSnap(command)
                },
                onCountdown: { [weak self] seconds in
                    self?.onCountdown?(seconds)
                }
            )
        )
        // ⌘K toggles the actions menu (Open / Decrease Ranking).
        onCommandK = { [weak self] in
            self?.menuModel.toggle()
        }
        // While the menu is up, keys route to the menu.
        onMenuKey = { [weak self] keyCode in
            guard let self else { return false }
            return self.menuModel.handleKey(keyCode)
        }
        // Esc: close ⌘K menu → unlock command chip → then hide panel.
        onEscape = { [weak self] in
            guard let self else { return false }
            if self.menuModel.isOpen {
                self.menuModel.close()
                return true
            }
            return self.searchSession.unlockCommand()
        }
    }

    func show() {
        super.show(afterBecomeKey: nil)
    }

    override func hide(restoreFocus: Bool) {
        menuModel.close()
        super.hide(restoreFocus: restoreFocus)
    }

    /// Tinycast hand-off: remember the prior app, hide (restore focus if we stole it),
    /// then resolve + place that app's focused window via Accessibility.
    private func performWindowSnap(_ command: WindowSnap.Command) {
        let app = previouslyActiveApp
        hide(restoreFocus: true)
        WindowSnap.apply(command: command, activating: app)
    }
}
