import SwiftUI
import AppKit

struct ContentView: View {
    @State private var query = ""
    @ObservedObject var navigationState: NavigationState
    @StateObject private var appIndex = AppIndex()
    @FocusState private var isSearchFocused: Bool
    let onDismiss: () -> Void

    private enum Layout {
        static let width: CGFloat = 860
        static let height: CGFloat = 560
        static let cornerRadius: CGFloat = 12
    }

    var filteredApps: [AppItem] {
        guard !query.isEmpty else { return [] }
        return appIndex.search(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field area
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isSearchFocused ? Color.accentColor : .secondary)

                SearchField(text: $query, onSubmit: {
                    launchSelectedApp()
                })
                .frame(height: 40)

                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            // Results area
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if query.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 28, weight: .light))
                                    .foregroundStyle(.tertiary)
                                Text("Start typing to search…")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.top, 60)
                        } else if filteredApps.isEmpty {
                            Text("No results")
                                .font(.system(size: 15))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 40)
                        } else {
                            ForEach(Array(filteredApps.enumerated()), id: \.element.id) { index, app in
                                AppRow(app: app, isSelected: index == navigationState.selectedIndex)
                                    .onTapGesture {
                                        navigationState.selectedIndex = index
                                        launchSelectedApp()
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Version badge
                Text("v\(AppVersion.string)")
                    .font(.system(size: 10, weight: .light))
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
            }
        }
        .frame(width: Layout.width, height: Layout.height)
        .background(
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .fill(.thickMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
            
            // Listen for launch notification
            NotificationCenter.default.addObserver(
                forName: .launchSelectedApp,
                object: nil,
                queue: .main
            ) { _ in
                self.launchSelectedApp()
            }
        }
        .onChange(of: query) { _, _ in
            navigationState.reset()
            navigationState.maxIndex = max(0, filteredApps.count - 1)
        }
        .environmentObject(navigationState)
    }

    private func launchSelectedApp() {
        guard !filteredApps.isEmpty else { return }
        guard navigationState.selectedIndex < filteredApps.count else { return }
        
        let app = filteredApps[navigationState.selectedIndex]
        if let url = URL(string: "file://\(app.path)") {
            NSWorkspace.shared.open(url)
            onDismiss()
        }
    }
}

struct AppRow: View {
    let app: AppItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Text(app.path)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.04))
        )
    }
}
