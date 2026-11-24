import SwiftUI
import AppKit

struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = "Search apps, files, commands…"
    var fontSize: CGFloat = 18
    var onSubmit: () -> Void
    /// Tab / → at end of text — return true if the parent consumed the key (command lock).
    var onComplete: (() -> Bool)? = nil
    /// Backspace/delete when the field is empty — return true if consumed (unlock chip).
    var onBackspaceWhenEmpty: (() -> Bool)? = nil

    func makeNSView(context: Context) -> CustomTextField {
        let textField = CustomTextField()
        textField.placeholderString = placeholder
        textField.font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.delegate = context.coordinator
        wireCallbacks(textField, coordinator: context.coordinator)
        return textField
    }

    func updateNSView(_ nsView: CustomTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        wireCallbacks(nsView, coordinator: context.coordinator)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func wireCallbacks(_ textField: CustomTextField, coordinator: Coordinator) {
        textField.onArrowUp = {
            NotificationCenter.default.post(name: .arrowUpPressed, object: nil)
        }
        textField.onArrowDown = {
            NotificationCenter.default.post(name: .arrowDownPressed, object: nil)
        }
        textField.onEnterKey = {
            coordinator.parent.onSubmit()
        }
        textField.onComplete = {
            coordinator.parent.onComplete?() ?? false
        }
        textField.onBackspaceWhenEmpty = {
            coordinator.parent.onBackspaceWhenEmpty?() ?? false
        }
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField

        init(_ parent: SearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        /// Field editor path — Return / Tab / arrows often never hit `CustomTextField.keyDown`.
        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                NotificationCenter.default.post(name: .arrowUpPressed, object: nil)
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                NotificationCenter.default.post(name: .arrowDownPressed, object: nil)
                return true
            }
            if commandSelector == #selector(NSResponder.insertTab(_:))
                || commandSelector == #selector(NSResponder.insertTabIgnoringFieldEditor(_:))
            {
                return parent.onComplete?() ?? false
            }
            if commandSelector == #selector(NSResponder.moveRight(_:)) {
                // Only complete when the caret is at the end (otherwise move normally).
                let selected = textView.selectedRange()
                if selected.length == 0, selected.location == textView.string.utf16.count {
                    if parent.onComplete?() == true { return true }
                }
                return false
            }
            if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
                if textView.string.isEmpty {
                    return parent.onBackspaceWhenEmpty?() ?? false
                }
                return false
            }
            return false
        }
    }
}

class CustomTextField: NSTextField {
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onEnterKey: (() -> Void)?
    var onComplete: (() -> Bool)?
    var onBackspaceWhenEmpty: (() -> Bool)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case KeyCode.upArrow:
            onArrowUp?()
        case KeyCode.downArrow:
            onArrowDown?()
        case KeyCode.returnKey, KeyCode.keypadEnter:
            onEnterKey?()
        case KeyCode.tab:
            if onComplete?() == true { return }
            super.keyDown(with: event)
        case KeyCode.rightArrow:
            if let editor = currentEditor() as? NSTextView {
                let selected = editor.selectedRange()
                if selected.length == 0, selected.location == editor.string.utf16.count,
                   onComplete?() == true
                {
                    return
                }
            }
            super.keyDown(with: event)
        case KeyCode.delete:
            if stringValue.isEmpty, onBackspaceWhenEmpty?() == true { return }
            super.keyDown(with: event)
        default:
            super.keyDown(with: event)
        }
    }

    /// Accessory apps have no Edit menu, so ⌘C / ⌘X / ⌘V / ⌘A never reach the
    /// field editor unless we handle them here. Needed so users can copy/cut
    /// selected search text (e.g. spaces) to flush the system pasteboard.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.option),
              !event.modifierFlags.contains(.control)
        else {
            return super.performKeyEquivalent(with: event)
        }

        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let action: Selector?
        switch key {
        case "c":
            action = #selector(NSText.copy(_:))
        case "x":
            action = #selector(NSText.cut(_:))
        case "v":
            action = #selector(NSText.paste(_:))
        case "a":
            action = #selector(NSText.selectAll(_:))
        default:
            action = nil
        }

        if let action, NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

extension Notification.Name {
    static let arrowUpPressed = Notification.Name("arrowUpPressed")
    static let arrowDownPressed = Notification.Name("arrowDownPressed")
}

extension KeyCode {
    static let tab: UInt16 = 48
    static let rightArrow: UInt16 = 124
    static let delete: UInt16 = 51
}
