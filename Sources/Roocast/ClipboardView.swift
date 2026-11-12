import SwiftUI
import AppKit

enum ClipboardLayout {
    static let width: CGFloat = 560
    static let height: CGFloat = 360
    static let cornerRadius: CGFloat = 10
}

enum ClipboardMenuLayout {
    static let menuWidth: CGFloat = 260
    static let listWidth: CGFloat = ClipboardLayout.width
    static let headerHeight: CGFloat = 54
}

struct ClipboardView: View {
    @State private var query = ""
    @ObservedObject var store: ClipboardStore
    @ObservedObject var menuModel: ClipboardActionsModel
    @ObservedObject var navigationState: NavigationState
    @FocusState private var isSearchFocused: Bool
    let onPaste: (ClipboardItem) -> Void
    let onDismiss: () -> Void

    /// Rows grouped under tinycast-style date-bucket headers; the per-row
    /// `index` is the flat filteredItems index, still the selection space.
    private enum ListRow: Identifiable {
        case header(String)
        case item(ClipboardItem, index: Int)
        var id: String {
            switch self {
            case .header(let title): return "header-\(title)"
            case .item(let item, _): return item.id.uuidString
            }
        }
    }

    var filteredItems: [ClipboardItem] {
        store.items(matching: query)
    }

    private var rows: [ListRow] {
        var result: [ListRow] = []
        var lastBucket: DateBucket?
        for (index, item) in filteredItems.enumerated() {
            let bucket = DateBucket(for: item.createdAt)
            if bucket != lastBucket {
                result.append(.header(bucket.title))
                lastBucket = bucket
            }
            result.append(.item(item, index: index))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider()
            listPanel
        }
        .frame(width: ClipboardLayout.width, height: ClipboardLayout.height)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: ClipboardLayout.cornerRadius, style: .continuous))
        .onAppear {
            FocusRestorer.log("debug: ClipboardView onAppear sel=\(navigationState.selectedIndex) items=\(filteredItems.count)")
            handleAppear()
        }
        // onReceive (not addObserver) so @State/@ObservedObject stay live — stale
        // captures were silently no-op'ing Enter paste when query/filter disagreed.
        .onReceive(NotificationCenter.default.publisher(for: .pasteSelectedClipboardItem)) { _ in
            pasteSelected()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardWillShow)) { _ in
            query = ""
            menuModel.close()
            navigationState.sync(itemCount: filteredItems.count)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onChange(of: query) { _, _ in
            navigationState.sync(itemCount: filteredItems.count)
            // Typing filters the list — a menu anchored to a stale row is meaningless.
            if menuModel.isOpen { menuModel.close() }
        }
        .onChange(of: store.items) { _, _ in
            navigationState.updateBounds(itemCount: filteredItems.count)
        }
    }

    // MARK: - Sub-views (kept small so SwiftUI type-checks each in isolation)

    private var searchHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isSearchFocused ? Color.accentColor : .secondary)

            SearchField(
                text: $query,
                placeholder: "Search clipboard…",
                fontSize: 16,
                onSubmit: { pasteSelected() }
            )
            .frame(height: 28)

            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var panelBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: ClipboardLayout.cornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.94))
            RoundedRectangle(cornerRadius: ClipboardLayout.cornerRadius, style: .continuous)
                .fill(.thickMaterial)
        }
    }

    private var listPanel: some View {
        ZStack(alignment: .bottomTrailing) {
            listWithMenu
            Text("v\(AppVersion.string)")
                .font(.system(size: 9, weight: .light))
                .foregroundStyle(.quaternary)
                .padding(.trailing, 10)
                .padding(.bottom, 6)
        }
        .overlay {
            if menuModel.confirmDeleteAll {
                confirmDeleteAllOverlay
            }
        }
    }

    /// The scrollable history with the ⌘K / right-click actions menu overlay.
    private var listWithMenu: some View {
        ScrollViewReader { proxy in
            ScrollView {
                listContent
            }
            .onChange(of: navigationState.selectedIndex) { _, index in
                // Minimum scroll to reveal — `.center` hid early rows on short lists.
                guard filteredItems.indices.contains(index) else { return }
                proxy.scrollTo(filteredItems[index].id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "clipList")
        .overlay(alignment: .topLeading) {
            if menuModel.isOpen {
                actionsMenuOverlay
            }
        }
    }

    @ViewBuilder
    private var listContent: some View {
        LazyVStack(spacing: 1) {
            if filteredItems.isEmpty {
                emptyState
            } else {
                ForEach(rows) { row in
                    switch row {
                    case .header(let title):
                        dateHeader(title: title)
                    case .item(let item, let index):
                        historyRow(item: item, index: index)
                    }
                }
            }
        }
        .transaction { $0.animation = nil }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: emptyIconName)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text(emptyMessage)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 36)
    }

    private func dateHeader(title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .padding(.top, 8)
    }

    /// A single history row: tap pastes, right-click opens the actions menu,
    /// and the row reports its frame for the ⌘K menu anchor.
    private func historyRow(item: ClipboardItem, index: Int) -> some View {
        // The row observes NavigationState itself: LazyVStack can drop a row's
        // update during a scroll transaction (seen as two highlighted rows —
        // the just-deselected row never re-rendered), so selection must not
        // depend on the parent re-diffing the row.
        return ClipboardRow(item: item, index: index, navigationState: navigationState)
            .id(item.id)
            .onTapGesture {
                navigationState.selectedIndex = index
                pasteSelected()
            }
            // Raycast parity: right-click opens the same actions menu ⌘K opens —
            // anchored to the row.
            .onRightClick {
                menuModel.open(
                    for: item,
                    anchorFrame: menuModel.rowFrames[item.id] ?? .zero
                )
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            menuModel.rowFrames[item.id] = geo.frame(in: .named("clipList"))
                        }
                        .onChange(of: geo.frame(in: .named("clipList"))) { _, frame in
                            menuModel.rowFrames[item.id] = frame
                            // The list moved under the menu — dismiss it.
                            if menuModel.isOpen, menuModel.anchoredItem?.id == item.id {
                                menuModel.close()
                            }
                        }
                }
            )
    }

    // MARK: - Actions menu (⌘K / right-click) — deletes are menu-only, no chords.

    private var menuHeight: CGFloat {
        48 + CGFloat(ClipboardMenuAction.allCases.count) * 30
    }

    private var listViewportHeight: CGFloat {
        ClipboardLayout.height - ClipboardMenuLayout.headerHeight
    }

    /// The actions menu, anchored below the selected row (above if it would
    /// run past the fold), clamped inside the list's viewport.
    @ViewBuilder
    private var actionsMenuOverlay: some View {
        let anchor = menuModel.anchorFrame
        let listHeight = listViewportHeight
        let belowCenter = anchor.maxY + 6 + menuHeight / 2
        let aboveCenter = anchor.minY - 6 - menuHeight / 2
        let useBelow = belowCenter + menuHeight / 2 <= listHeight || aboveCenter - menuHeight / 2 < 0
        let centerX = min(
            max(anchor.midX, ClipboardMenuLayout.menuWidth / 2 + 8),
            ClipboardMenuLayout.listWidth - ClipboardMenuLayout.menuWidth / 2 - 8
        )
        let centerY = min(
            max(useBelow ? belowCenter : aboveCenter, menuHeight / 2 + 8),
            listHeight - menuHeight / 2 - 8
        )
        ZStack(alignment: .topLeading) {
            // Click-away backdrop — closes the menu without acting.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { menuModel.close() }
            ClipboardActionsMenuView(model: menuModel)
                .position(x: centerX, y: centerY)
        }
        .frame(width: ClipboardMenuLayout.listWidth, height: listHeight)
    }

    /// In-panel confirmation for Delete All — no system modal, the panel never
    /// activates another app and stays out of the focus chain.
    private var confirmDeleteAllOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
            VStack(spacing: 14) {
                Text("Delete All Entries")
                    .font(.system(size: 14, weight: .semibold))
                Text("Are you sure you want to delete all clipboard history entries?")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                HStack(spacing: 10) {
                    Button("Cancel") {
                        menuModel.close()
                    }
                    .keyboardShortcut(.cancelAction)
                    Button("Delete All", role: .destructive) {
                        store.removeAll()
                        navigationState.updateBounds(itemCount: 0)
                        menuModel.close()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.thickMaterial)
            )
        }
    }

    // MARK: - Behavior

    private var emptyIconName: String {
        if store.items.isEmpty { return "doc.on.clipboard" }
        return "magnifyingglass"
    }

    private var emptyMessage: String {
        if store.items.isEmpty { return "Copy something — it will show up here" }
        return "No results"
    }

    private func handleAppear() {
        navigationState.sync(itemCount: filteredItems.count)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isSearchFocused = true
        }
        // ⌘K toggle target: the highlighted row. Set here so the closure
        // always reads live state (query filters, selected row).
        menuModel.onToggle = { [self] in
            guard !filteredItems.isEmpty,
                  navigationState.selectedIndex < filteredItems.count else { return }
            let item = filteredItems[navigationState.selectedIndex]
            menuModel.open(
                for: item,
                anchorFrame: menuModel.rowFrames[item.id] ?? .zero
            )
        }
        // Menu actions dispatch through the view's own closures.
        menuModel.onPerform = { [weak store, menuModel] action in
            guard let item = menuModel.anchoredItem else { return }
            switch action {
            case .paste:
                menuModel.close()
                onPaste(item)
            case .copy:
                menuModel.close()
                store?.copyToPasteboard(item.text)
            case .deleteEntry:
                menuModel.close()
                store?.remove(item)
            case .deleteAll:
                // First Enter arms the confirm; the second (or the confirm
                // row's own click) carries it out.
                if menuModel.confirmDeleteAll {
                    store?.removeAll()
                    menuModel.close()
                } else {
                    menuModel.confirmDeleteAll = true
                }
            }
        }
    }

    private func pasteSelected() {
        guard !filteredItems.isEmpty else {
            FocusRestorer.log(
                "clipboard: pasteSelected skipped — empty filter (query=\(query.debugDescription) history=\(store.items.count))"
            )
            return
        }
        guard navigationState.selectedIndex < filteredItems.count else {
            FocusRestorer.log(
                "clipboard: pasteSelected skipped — index \(navigationState.selectedIndex) out of \(filteredItems.count)"
            )
            return
        }
        let item = filteredItems[navigationState.selectedIndex]
        query = ""
        onPaste(item)
    }
}

/// The ⌘K / right-click menu itself: header (entry preview) + action rows.
/// Keyboard navigation lives in the panel's `onMenuKey` — ↑/↓/↵/Esc/⌘K —
/// and every action is confirmed by Enter on the highlighted menu row.
struct ClipboardActionsMenuView: View {
    @ObservedObject var model: ClipboardActionsModel

    var body: some View {
        VStack(spacing: 0) {
            Text(model.anchoredItem?.preview ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(height: 24, alignment: .leading)
            Divider()
            ForEach(ClipboardMenuAction.allCases, id: \.rawValue) { action in
                menuRow(action: action)
            }
        }
        .frame(width: ClipboardMenuLayout.menuWidth)
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
    private func menuRow(action: ClipboardMenuAction) -> some View {
        let isSelected = model.selection == action.rawValue
        HStack(spacing: 8) {
            Image(systemName: action.systemImage)
                .font(.system(size: 12))
                .foregroundStyle(
                    action.isDestructive
                        ? Color.red
                        : (isSelected ? Color.white : Color.secondary)
                )
                .frame(width: 18, height: 18)
            Text(action.title)
                .font(.system(size: 13))
                .foregroundStyle(
                    action.isDestructive
                        ? Color.red
                        : (isSelected ? Color.white : Color.primary)
                )
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

struct ClipboardRow: View {
    let item: ClipboardItem
    let index: Int
    @ObservedObject var navigationState: NavigationState

    private var isSelected: Bool { index == navigationState.selectedIndex }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? Color.white.opacity(0.9) : .secondary)
                .frame(width: 24, height: 24)

            Text(item.preview)
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(2)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            // When it was copied — today shows a clock time, older shows the
            // relative date ("Yesterday", "Nov 8, 2026").
            Text(item.timeLabel)
                .font(.system(size: 11))
                .foregroundStyle(isSelected ? Color.white.opacity(0.75) : .secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor)
            }
        }
    }
}
