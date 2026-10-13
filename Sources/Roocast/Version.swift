import Foundation

// Auto-generated version file
struct AppVersion {
    static let major = 0
    static let minor = 2
    static let patch = 1
    
    static var string: String {
        "\(major).\(minor).\(patch)"
    }
    
    static var buildDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
