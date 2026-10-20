import Foundation

// Auto-generated version file
struct AppVersion {
    static let major = 0
    static let minor = 4
    static let patch = 5
    
    static var string: String {
        "\(major).\(minor).\(patch)"
    }
    
    static var buildDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
