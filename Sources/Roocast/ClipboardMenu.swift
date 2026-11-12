import SwiftUI

/// A date-bucket header for the clipboard history list (tinycast parity).
/// Rows are newest-first, so the bucket changes as the list descends.
enum DateBucket: String {
    case today, yesterday, thisWeek, thisMonth, earlier

    var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This Week"
        case .thisMonth: return "This Month"
        case .earlier: return "Earlier"
        }
    }

    init(for date: Date, now: Date = Date(), calendar: Calendar = .current) {
        if calendar.isDateInToday(date) {
            self = .today
        } else if calendar.isDateInYesterday(date) {
            self = .yesterday
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            self = .thisWeek
        } else if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            self = .thisMonth
        } else {
            self = .earlier
        }
    }
}

/// One entry in the clipboard row's actions menu (⌘K / right-click).
/// No delete shortcuts: both delete actions are menu-only, confirmed by Enter.
enum ClipboardMenuAction: Int, CaseIterable {
    case paste, copy, deleteEntry, deleteAll

    var title: String {
        switch self {
        case .paste: return "Paste"
        case .copy: return "Copy"
        case .deleteEntry: return "Delete Entry"
        case .deleteAll: return "Delete All Entries"
        }
    }

    var systemImage: String {
        switch self {
        case .paste: return "arrow.down.doc"
        case .copy: return "doc.on.doc"
        case .deleteEntry, .deleteAll: return "trash"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .deleteEntry, .deleteAll: return true
        case .paste, .copy: return false
        }
    }
}

/// State for the row actions menu (⌘K / right-click) on the clipboard panel.
///
/// Lives outside the SwiftUI view so the panel's `sendEvent` can route keys
/// while the search field stays first responder. Activation callbacks are
/// wired by the ClipboardView, which owns the store and the paste flow.
@MainActor
final class ClipboardActionsModel: ObservableObject {
    @Published var isOpen = false
    @Published var selection = 0
    @Published var confirmDeleteAll = false

    /// The entry the menu is anchored to (nil when closed).
    @Published private(set) var anchoredItem: ClipboardItem?
    /// The anchored row's frame in the list's named coordinate space.
    /// Updated by the row's frame reporter; non-published (only read at open).
    var anchorFrame: CGRect = .zero
    /// Every visible row's frame in the list's named coordinate space — the
    /// menu's anchor for ⌘K (selected row) and right-click (clicked row).
    var rowFrames: [UUID: CGRect] = [:]

    var onPerform: ((ClipboardMenuAction) -> Void)?

    func open(for item: ClipboardItem, anchorFrame: CGRect) {
        self.anchorFrame = anchorFrame
        anchoredItem = item
        selection = 0
        confirmDeleteAll = false
        isOpen = true
    }

    func close() {
        isOpen = false
        anchoredItem = nil
        confirmDeleteAll = false
    }

    /// ⌘K — the view resolves the toggle target (the selected row).
    var onToggle: (() -> Void)?

    func toggle() {
        if isOpen || confirmDeleteAll { close() } else { onToggle?() }
    }

    func moveSelection(_ delta: Int) {
        let count = ClipboardMenuAction.allCases.count
        selection = (selection + delta + count) % count
    }

    func perform(_ action: ClipboardMenuAction) {
        onPerform?(action)
    }

    /// Routes key codes while the menu (or its confirm) is up. Returns false
    /// for keys the menu doesn't consume, so the panel falls back to the list.
    func handleKey(_ keyCode: UInt16) -> Bool {
        if confirmDeleteAll {
            switch keyCode {
            case KeyCode.returnKey, KeyCode.keypadEnter:
                perform(.deleteAll)
            case KeyCode.escape:
                close()
            default:
                break
            }
            return true
        }
        guard isOpen else { return false }
        switch keyCode {
        case KeyCode.upArrow:
            moveSelection(-1)
        case KeyCode.downArrow:
            moveSelection(1)
        case KeyCode.returnKey, KeyCode.keypadEnter:
            if let action = ClipboardMenuAction(rawValue: selection) {
                perform(action)
            }
        case KeyCode.escape:
            close()
        default:
            return false
        }
        return true
    }
}

/// An overlay claiming only right-mouse events, so the row's tap gesture
/// passes through untouched (tinycast's RightClickCatcher pattern).
struct RightClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView { CatcherView(action: action) }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.action = action
    }

    private final class CatcherView: NSView {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Only claim the right mouse button; left clicks fall through to
            // the row's tap gesture underneath.
            if NSApp.currentEvent?.type == .rightMouseDown {
                return super.hitTest(point)
            }
            return nil
        }

        override func rightMouseDown(with event: NSEvent) {
            action()
        }
    }
}

extension View {
    func onRightClick(perform action: @escaping () -> Void) -> some View {
        overlay(RightClickCatcher(action: action))
    }
}
