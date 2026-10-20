import SwiftUI
import AppKit

/// Shared panel geometry — keep `LauncherPanel` and SwiftUI content in sync.
enum LauncherLayout {
    static let width: CGFloat = 640
    static let height: CGFloat = 400
    static let cornerRadius: CGFloat = 10
}

struct ContentView: View {
    @State private var query = ""
    @ObservedObject var navigationState: NavigationState
    @StateObject private var appIndex = AppIndex()
    @FocusState private var isSearchFocused: Bool
    let onDismiss: () -> Void

    var filteredApps: [AppItem] {
        guard !query.isEmpty else { return [] }
        return appIndex.search(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field area
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSearchFocused ? Color.accentColor : .secondary)

                SearchField(text: $query, onSubmit: {
                    launchSelectedApp()
                })
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

            // Results area
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        if query.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "keyboard")
                                    .font(.system(size: 22, weight: .light))
                                    .foregroundStyle(.tertiary)
                                Text("Start typing to search…")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.top, 36)
                        } else if filteredApps.isEmpty {
                            Text("No results")
                                .font(.system(size: 13))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 28)
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
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Version badge
                Text("v\(AppVersion.string)")
                    .font(.system(size: 9, weight: .light))
                    .foregroundStyle(.quaternary)
                    .padding(.trailing, 10)
                    .padding(.bottom, 6)
            }
        }
        .frame(width: LauncherLayout.width, height: LauncherLayout.height)
        .background(
            RoundedRectangle(cornerRadius: LauncherLayout.cornerRadius, style: .continuous)
                .fill(.thickMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: LauncherLayout.cornerRadius, style: .continuous))
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
        .onReceive(NotificationCenter.default.publisher(for: .launcherWillShow)) { _ in
            Task { await appIndex.indexApps() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
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

        if app.kind == .quit {
            query = ""
            NSApplication.shared.terminate(nil)
            return
        }
        
        // If this is a Firefox profile, handle profile-specific launch
        if let profile = app.profile {
            AppLauncher.launchFirefoxProfile(profile: profile, appPath: app.path)
        } else {
            // Standard launch
            if let url = URL(string: "file://\(app.path)") {
                NSWorkspace.shared.open(url)
            }
        }

        // Clear so the next open starts with an empty search field
        query = ""
        onDismiss()
    }
}

struct AppRow: View {
    let app: AppItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let icon = app.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                }

                // Running indicator — white on selected row (accent bg), accent otherwise
                if app.isRunning {
                    Circle()
                        .fill(isSelected ? Color.white : Color.accentColor)
                        .frame(width: 6, height: 6)
                        .overlay(
                            Circle()
                                .stroke(isSelected ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.15), lineWidth: 1)
                        )
                        .offset(x: 2, y: 2)
                }
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                
                // Show profile name if available, otherwise show path
                if let profile = app.profile {
                    Text(profile)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.accentColor)
                } else {
                    Text(app.path)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.04))
        )
    }
}
