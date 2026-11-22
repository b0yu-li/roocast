import SwiftUI

/// Small keyboard keycap used in Raycast-style footer hints (⌘ K, ↵).
struct KeyboardKeycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .frame(minWidth: 16, minHeight: 16)
            .padding(.horizontal, label.count > 1 ? 3 : 0)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
    }
}
