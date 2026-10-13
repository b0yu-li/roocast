import SwiftUI
import AppKit

struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    
    func makeNSView(context: Context) -> CustomTextField {
        let textField = CustomTextField()
        textField.placeholderString = "Search apps, files, commands…"
        textField.font = NSFont.systemFont(ofSize: 24, weight: .regular)
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.focusRingType = .none
        textField.delegate = context.coordinator
        textField.onArrowUp = {
            NotificationCenter.default.post(name: .arrowUpPressed, object: nil)
        }
        textField.onArrowDown = {
            NotificationCenter.default.post(name: .arrowDownPressed, object: nil)
        }
        textField.onEnterKey = {
            onSubmit()
        }
        return textField
    }
    
    func updateNSView(_ nsView: CustomTextField, context: Context) {
        nsView.stringValue = text
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: SearchField
        
        init(_ parent: SearchField) {
            self.parent = parent
        }
        
        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }
    }
}

class CustomTextField: NSTextField {
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onEnterKey: (() -> Void)?
    
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: // Up arrow
            onArrowUp?()
        case 125: // Down arrow
            onArrowDown?()
        case 36: // Return/Enter
            onEnterKey?()
        default:
            super.keyDown(with: event)
        }
    }
}

extension Notification.Name {
    static let arrowUpPressed = Notification.Name("arrowUpPressed")
    static let arrowDownPressed = Notification.Name("arrowDownPressed")
}
