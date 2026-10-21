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
                onWindowSnap: { [weak self] side in
                    self?.performWindowSnap(side)
                }
            )
        )
    }

    func show() {
        super.show(afterBecomeKey: nil)
    }

    /// Tinycast hand-off: remember the prior app, hide (restore focus if we stole it),
    /// then resolve + snap that app's focused window via Accessibility.
    private func performWindowSnap(_ side: WindowSnap.Side) {
        let app = previouslyActiveApp
        hide(restoreFocus: true)
        WindowSnap.apply(side: side, activating: app)
    }
}
