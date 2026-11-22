import SwiftUI

/// Layout constants for the launcher ⌘K actions menu.
enum LauncherMenuLayout {
    static let menuWidth: CGFloat = 260
    static let headerHeight: CGFloat = 48
}

/// One entry in the launcher row's actions menu (⌘K).
enum LauncherMenuAction: Equatable {
    case open
    case decreaseRanking
    case resetRanking

    var title: String {
        switch self {
        case .open: return "Open"
        case .decreaseRanking: return "Decrease Ranking"
        case .resetRanking: return "Reset Ranking"
        }
    }

    var systemImage: String {
        switch self {
        case .open: return "arrow.up.forward.app"
        case .decreaseRanking: return "arrow.down"
        case .resetRanking: return "arrow.counterclockwise"
        }
    }
}

/// State for the row actions menu (⌘K) on the launcher panel.
///
/// Lives outside the SwiftUI view so the panel's `sendEvent` can route keys
/// while the search field stays first responder.
@MainActor
final class LauncherActionsModel: ObservableObject {
    @Published var isOpen = false
    @Published var selection = 0

    /// The row the menu is anchored to (nil when closed).
    @Published private(set) var anchoredItem: AppItem?
    /// Whether the anchored item currently has a demote level (drives Reset vs Decrease).
    @Published private(set) var anchoredIsDemoted = false

    var anchorFrame: CGRect = .zero
    var rowFrames: [UUID: CGRect] = [:]

    var onPerform: ((LauncherMenuAction) -> Void)?
    var onToggle: (() -> Void)?

    /// Actions shown for the current anchor — Open always; Decrease or Reset.
    var actions: [LauncherMenuAction] {
        var list: [LauncherMenuAction] = [.open]
        if anchoredIsDemoted {
            list.append(.resetRanking)
        } else {
            list.append(.decreaseRanking)
        }
        return list
    }

    func open(for item: AppItem, anchorFrame: CGRect, isDemoted: Bool) {
        self.anchorFrame = anchorFrame
        anchoredItem = item
        anchoredIsDemoted = isDemoted
        selection = 0
        isOpen = true
    }

    func close() {
        isOpen = false
        anchoredItem = nil
        anchoredIsDemoted = false
        selection = 0
    }

    func toggle() {
        if isOpen { close() } else { onToggle?() }
    }

    func moveSelection(_ delta: Int) {
        let count = actions.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    func perform(_ action: LauncherMenuAction) {
        onPerform?(action)
    }

    /// Routes key codes while the menu is up. Returns false for keys the menu
    /// doesn't consume, so the panel falls back to the list.
    func handleKey(_ keyCode: UInt16) -> Bool {
        guard isOpen else { return false }
        switch keyCode {
        case KeyCode.upArrow:
            moveSelection(-1)
        case KeyCode.downArrow:
            moveSelection(1)
        case KeyCode.returnKey, KeyCode.keypadEnter:
            let list = actions
            if list.indices.contains(selection) {
                perform(list[selection])
            }
        case KeyCode.escape:
            close()
        default:
            return false
        }
        return true
    }
}

/// The ⌘K menu itself: header (row name) + action rows.
struct LauncherActionsMenuView: View {
    @ObservedObject var model: LauncherActionsModel

    var body: some View {
        let actions = model.actions
        VStack(spacing: 0) {
            Text(model.anchoredItem?.name ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(height: 24, alignment: .leading)
            Divider()
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                menuRow(action: action, index: index)
            }
        }
        .frame(width: LauncherMenuLayout.menuWidth)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }

    @ViewBuilder
    private func menuRow(action: LauncherMenuAction, index: Int) -> some View {
        let isSelected = model.selection == index
        HStack(spacing: 8) {
            Image(systemName: action.systemImage)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(width: 18, height: 18)
            Text(action.title)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background {
            if isSelected {
                Rectangle().fill(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.perform(action)
        }
    }
}
