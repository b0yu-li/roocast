import SwiftUI
import AppKit

enum ClipboardLayout {
    static let width: CGFloat = 560
    static let height: CGFloat = 360
    static let cornerRadius: CGFloat = 10
}

struct ClipboardView: View {
    @State private var query = ""
    @ObservedObject var store: ClipboardStore
    @ObservedObject var navigationState: NavigationState
    @FocusState private var isSearchFocused: Bool
    let onPaste: (ClipboardItem) -> Void
    let onDismiss: () -> Void

    var filteredItems: [ClipboardItem] {
        store.items(matching: query)
    }

    var body: some View {
        VStack(spacing: 0) {
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

            Divider()

            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        if filteredItems.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: emptyIconName)
                                    .font(.system(size: 22, weight: .light))
                                    .foregroundStyle(.tertiary)
                                Text(emptyMessage)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.top, 36)
                        } else {
                            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                                ClipboardRow(item: item, isSelected: index == navigationState.selectedIndex)
                                    .onTapGesture {
                                        navigationState.selectedIndex = index
                                        pasteSelected()
                                    }
                            }
                        }
                    }
                    .transaction { $0.animation = nil }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text("v\(AppVersion.string)")
                    .font(.system(size: 9, weight: .light))
                    .foregroundStyle(.quaternary)
                    .padding(.trailing, 10)
                    .padding(.bottom, 6)
            }
        }
        .frame(width: ClipboardLayout.width, height: ClipboardLayout.height)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: ClipboardLayout.cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.94))
                RoundedRectangle(cornerRadius: ClipboardLayout.cornerRadius, style: .continuous)
                    .fill(.thickMaterial)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: ClipboardLayout.cornerRadius, style: .continuous))
        .onAppear {
            syncNavigation()
            NotificationCenter.default.addObserver(
                forName: .pasteSelectedClipboardItem,
                object: nil,
                queue: .main
            ) { _ in
                self.pasteSelected()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardWillShow)) { _ in
            query = ""
            syncNavigation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
        .onChange(of: query) { _, _ in
            syncNavigation()
        }
        .onChange(of: store.items) { _, _ in
            updateNavigationBounds()
        }
    }

    private var emptyIconName: String {
        if store.items.isEmpty { return "doc.on.clipboard" }
        return "magnifyingglass"
    }

    private var emptyMessage: String {
        if store.items.isEmpty { return "Copy something — it will show up here" }
        return "No results"
    }

    private func syncNavigation() {
        navigationState.reset()
        updateNavigationBounds()
    }

    private func updateNavigationBounds() {
        navigationState.maxIndex = max(0, filteredItems.count - 1)
        if navigationState.selectedIndex > navigationState.maxIndex {
            navigationState.selectedIndex = navigationState.maxIndex
        }
    }

    private func pasteSelected() {
        guard !filteredItems.isEmpty else { return }
        guard navigationState.selectedIndex < filteredItems.count else { return }
        let item = filteredItems[navigationState.selectedIndex]
        query = ""
        onPaste(item)
    }
}

struct ClipboardRow: View {
    let item: ClipboardItem
    let isSelected: Bool

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
