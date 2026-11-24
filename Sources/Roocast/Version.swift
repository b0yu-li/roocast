import Foundation

// Auto-generated version file
struct AppVersion {
    static let major = 0
    static let minor = 13
    static let patch = 0
    /// Monotonic build stamped into CFBundleVersion (was hard-coded 1).
    static let build = 2

    static var string: String {
        "\(major).\(minor).\(patch)"
    }

    static var buildDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
