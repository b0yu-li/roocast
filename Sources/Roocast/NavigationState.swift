import Foundation

final class NavigationState: ObservableObject {
    @Published var selectedIndex = 0
    var maxIndex = 0

    func moveUp() {
        if selectedIndex > 0 {
            selectedIndex -= 1
        }
    }

    func moveDown() {
        if selectedIndex < maxIndex {
            selectedIndex += 1
        }
    }

    func reset() {
        selectedIndex = 0
    }

    /// Clamp selection to a list of `itemCount` rows (0 → maxIndex stays 0).
    func updateBounds(itemCount: Int) {
        maxIndex = max(0, itemCount - 1)
        if selectedIndex > maxIndex {
            selectedIndex = maxIndex
        }
    }

    /// Reset to row 0 and refresh bounds — used when the query / list identity changes.
    func sync(itemCount: Int) {
        reset()
        updateBounds(itemCount: itemCount)
    }
}
