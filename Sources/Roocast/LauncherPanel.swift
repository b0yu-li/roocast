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
                }
            )
        )
    }

    func show() {
        super.show(afterBecomeKey: nil)
    }
}
