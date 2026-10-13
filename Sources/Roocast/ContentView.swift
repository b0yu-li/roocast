import SwiftUI

struct ContentView: View {
    @State private var query = ""
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search apps, files, commands…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .light))
                    .focusable()

                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

            // Results area (empty for now)
            VStack {
                Spacer()
                Text("Start typing to search…")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        )
        .padding(20) // Shadow breathing room
    }
}
