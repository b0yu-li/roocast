import SwiftUI
import AppKit

final class LauncherPanel: FloatingPanel {
    let navigationState: NavigationState

    init(navigationState: NavigationState) {
        self.navigationState = navigationState
        super.init(
            size: NSSize(width: LauncherLayout.width, height: LauncherLayout.height),
            willShowNotification: .launcherWillShow,
            logPrefix: ""
        )

        installHostingController(
            ContentView(
                navigationState: navigationState,
                onDismiss: { [weak self] in
                    // Launch path: target app activates itself.
                    self?.hide(restoreFocus: false)
                },
                onWindowSnap: { [weak self] command in
                    self?.performWindowSnap(command)
                }
            )
        )
    }

    func show() {
        super.show(afterBecomeKey: nil)
    }

    /// Tinycast hand-off: remember the prior app, hide (restore focus if we stole it),
    /// then resolve + place that app's focused window via Accessibility.
    private func performWindowSnap(_ command: WindowSnap.Command) {
        let app = previouslyActiveApp
        hide(restoreFocus: true)
        WindowSnap.apply(command: command, activating: app)
    }
}
