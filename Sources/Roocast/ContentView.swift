import SwiftUI
import AppKit

struct ContentView: View {
    @State private var query = ""
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
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isSearchFocused ? Color.accentColor : .secondary)

                TextField("Search apps, files, commands…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .regular))
                    .focused($isSearchFocused)

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
                        ForEach(filteredApps) { app in
                            AppRow(app: app)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 860, height: 560) // Fill the full panel
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thickMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct AppRow: View {
    let app: AppItem

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
                    .foregroundStyle(.primary)
                Text(app.path)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
