import SwiftUI
import AppKit

final class NavigationState: ObservableObject {
    @Published var selectedIndex = 0
    var maxIndex = 0
    
    func moveUp() {
        let logFile = "/tmp/roocast-events.log"
        try? "NavigationState.moveUp() called: \(selectedIndex) -> \(selectedIndex - 1)\n".write(toFile: logFile, atomically: true, encoding: .utf8)
        if selectedIndex > 0 {
            selectedIndex -= 1
            try? "NavigationState.moveUp() completed: \(selectedIndex)\n".write(toFile: logFile, atomically: true, encoding: .utf8)
        } else {
            try? "NavigationState.moveUp() skipped: already at 0\n".write(toFile: logFile, atomically: true, encoding: .utf8)
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
