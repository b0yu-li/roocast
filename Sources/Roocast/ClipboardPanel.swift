import SwiftUI
import AppKit

final class ClipboardPanel: FloatingPanel {
    init(store: ClipboardStore, navigationState: NavigationState, onPaste: @escaping (ClipboardItem) -> Void) {
        super.init(
            size: NSSize(width: ClipboardLayout.width, height: ClipboardLayout.height),
            willShowNotification: .clipboardWillShow,
            logPrefix: "clipboard "
        )

        installHostingController(
            ClipboardView(
                store: store,
                navigationState: navigationState,
                onPaste: onPaste,
                onDismiss: { [weak self] in
                    self?.hide(restoreFocus: false)
                }
            )
        )
    }

    func show() {
        super.show(afterBecomeKey: { [weak self] in
            self?.focusSearchField()
        })
    }

    private func focusSearchField() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let field = Self.findCustomTextField(in: self.contentView) {
                self.makeFirstResponder(field)
            }
        }
    }

    private static func findCustomTextField(in view: NSView?) -> CustomTextField? {
        guard let view else { return nil }
        if let field = view as? CustomTextField { return field }
        for sub in view.subviews {
            if let found = findCustomTextField(in: sub) { return found }
        }
        return nil
    }
}
