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
}
