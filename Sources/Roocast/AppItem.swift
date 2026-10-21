import AppKit

struct AppItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case app
        case quit
        case folder
        case leftHalf
        case rightHalf
        case maximize
    }

    let id: UUID
    let name: String
    let path: String
    let icon: NSImage?
    let isRunning: Bool
    let profile: String?  // Profile name for multi-instance apps (e.g., Firefox)
    let aliases: [String]
    let kind: Kind

    init(url: URL, isRunning: Bool = false, profile: String? = nil) {
        // Stable across reindex — random UUIDs made ForEach tear down every row on summon.
        self.id = Self.stableID(path: url.path, profile: profile)
        self.name = url.deletingPathExtension().lastPathComponent
        self.path = url.path
        self.icon = NSWorkspace.shared.icon(forFile: url.path)
        self.icon?.size = NSSize(width: 32, height: 32)
        self.isRunning = isRunning
        self.profile = profile
        self.aliases = []
        self.kind = .app
    }

    /// Name-based id so the same bundle (+ profile) keeps SwiftUI identity after rescans.
    nonisolated static func stableID(path: String, profile: String? = nil) -> UUID {
        let name = profile.map { "roocast.app:\(path)#\($0)" } ?? "roocast.app:\(path)"
        return nameBasedUUID(name)
    }

    /// Deterministic UUID from a string (v5-shaped bits). Not cryptographic — UI identity only.
    nonisolated private static func nameBasedUUID(_ name: String) -> UUID {
        var hash: [UInt8] = [
            0x6c, 0x25, 0x19, 0x7b, 0x52, 0x1e, 0x43, 0x0a,
            0x9c, 0xd4, 0x2f, 0x81, 0xb6, 0x03, 0xe7, 0x55,
        ]
        for byte in name.utf8 {
            hash[0] ^= byte
            var carry: UInt16 = 0
            for i in 0..<16 {
                let mixed = UInt16(hash[i]) &* 167 &+ carry &+ UInt16(byte)
                hash[i] = UInt8(truncatingIfNeeded: mixed)
                carry = mixed >> 8
            }
        }
        hash[6] = (hash[6] & 0x0f) | 0x50 // version 5
        hash[8] = (hash[8] & 0x3f) | 0x80 // RFC 4122 variant
        return UUID(uuid: (
            hash[0], hash[1], hash[2], hash[3],
            hash[4], hash[5], hash[6], hash[7],
            hash[8], hash[9], hash[10], hash[11],
            hash[12], hash[13], hash[14], hash[15]
        ))
    }

    private init(
        id: UUID,
        name: String,
        path: String,
        icon: NSImage?,
        isRunning: Bool,
        profile: String?,
        aliases: [String],
        kind: Kind
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.icon = icon
        self.isRunning = isRunning
        self.profile = profile
        self.aliases = aliases
        self.kind = kind
    }

    /// Built-in command: quit the Roocast process. Stable id so list selection stays stable.
    static let quitRoocast: AppItem = {
        let icon = NSImage(
            systemSymbolName: "power.circle.fill",
            accessibilityDescription: "Quit Roocast"
        )
        icon?.size = NSSize(width: 32, height: 32)
        return AppItem(
            id: UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!,
            name: "Quit Roocast",
            path: "Command",
            icon: icon,
            isRunning: false,
            profile: nil,
            aliases: [],
            kind: .quit
        )
    }()

    /// Built-in command: snap the prior focused window to the left half of its display.
    static let leftHalf: AppItem = {
        let icon = NSImage(
            systemSymbolName: "rectangle.lefthalf.filled",
            accessibilityDescription: "Left Half"
        )
        icon?.size = NSSize(width: 32, height: 32)
        return AppItem(
            id: UUID(uuidString: "B2C3D4E5-F6A7-8901-BCDE-F12345678901")!,
            name: "Left Half",
            path: "Command",
            icon: icon,
            isRunning: false,
            profile: nil,
            aliases: ["lh", "left"],
            kind: .leftHalf
        )
    }()

    /// Built-in command: snap the prior focused window to the right half of its display.
    static let rightHalf: AppItem = {
        let icon = NSImage(
            systemSymbolName: "rectangle.righthalf.filled",
            accessibilityDescription: "Right Half"
        )
        icon?.size = NSSize(width: 32, height: 32)
        return AppItem(
            id: UUID(uuidString: "C3D4E5F6-A7B8-9012-CDEF-123456789012")!,
            name: "Right Half",
            path: "Command",
            icon: icon,
            isRunning: false,
            profile: nil,
            aliases: ["rh", "right"],
            kind: .rightHalf
        )
    }()

    /// Built-in command: fill the display's visible frame (current Space — not macOS fullscreen).
    static let maximize: AppItem = {
        let icon = NSImage(
            systemSymbolName: "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: "Maximize"
        )
        icon?.size = NSSize(width: 32, height: 32)
        return AppItem(
            id: UUID(uuidString: "D4E5F6A7-B8C9-0123-DEF0-234567890123")!,
            name: "Maximize",
            path: "Command",
            icon: icon,
            isRunning: false,
            profile: nil,
            aliases: ["max"],
            kind: .maximize
        )
    }()

    /// Folder shortcut row — opens `shortcut.path` in Finder on activate.
    static func folder(_ shortcut: FolderShortcut) -> AppItem {
        let icon = NSWorkspace.shared.icon(forFile: shortcut.path.path)
        icon.size = NSSize(width: 32, height: 32)
        return AppItem(
            id: shortcut.id,
            name: shortcut.name,
            path: shortcut.path.path,
            icon: icon,
            isRunning: false,
            profile: nil,
            aliases: shortcut.aliases,
            kind: .folder
        )
    }

    /// Lightweight item for unit tests / ranking — no disk icon lookup.
    static func stub(
        name: String,
        profile: String? = nil,
        path: String = "/Applications/Stub.app",
        isRunning: Bool = false
    ) -> AppItem {
        AppItem(
            id: stableID(path: path, profile: profile),
            name: name,
            path: path,
            icon: nil,
            isRunning: isRunning,
            profile: profile,
            aliases: [],
            kind: .app
        )
    }

    /// Folder stub for unit tests — no disk icon lookup.
    static func folderStub(
        name: String,
        path: String = "/Users/test/Downloads",
        aliases: [String] = [],
        id: UUID = UUID()
    ) -> AppItem {
        AppItem(
            id: id,
            name: name,
            path: path,
            icon: nil,
            isRunning: false,
            profile: nil,
            aliases: aliases,
            kind: .folder
        )
    }

    /// Searchable text includes profile name and folder aliases.
    var searchText: String {
        var parts = [name]
        if let profile {
            parts.append(profile)
        }
        parts.append(contentsOf: aliases)
        return parts.joined(separator: " ")
    }
}
