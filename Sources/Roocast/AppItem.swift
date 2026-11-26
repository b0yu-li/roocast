import AppKit

struct AppItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case app
        case quit
        case checkForUpdates
        case uninstall
        case folder
        case leftHalf
        case rightHalf
        case topHalf
        case bottomHalf
        case firstThird
        case lastTwoThirds
        case moveToTop
        case moveToBottom
        case moveToLeft
        case moveToRight
        case maximize
        case reasonableSize
        /// Lead calculator row — Enter copies `copyText`.
        case calculator(copyText: String)
        /// Lead countdown row — Enter starts the island for `seconds`.
        case countdown(seconds: Int)
        /// Timer/countdown recognized but duration still needed — Enter is a no-op.
        case countdownHint
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

    /// Built-in command: fetch the product-site latest feed and open the DMG if newer.
    static let checkForUpdates: AppItem = {
        let icon = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: "Check for Updates"
        )
        icon?.size = NSSize(width: 32, height: 32)
        return AppItem(
            id: UUID(uuidString: "C3D4E5F6-A7B8-9012-CDEF-123456789012")!,
            name: "Check for Updates",
            path: "Command",
            icon: icon,
            isRunning: false,
            profile: nil,
            aliases: [],
            kind: .checkForUpdates
        )
    }()

    /// Built-in command: remove the app + local data (matches Homebrew zap paths).
    static let uninstallRoocast: AppItem = {
        let icon = NSImage(
            systemSymbolName: "trash.fill",
            accessibilityDescription: "Uninstall Roocast"
        )
        icon?.size = NSSize(width: 32, height: 32)
        return AppItem(
            id: UUID(uuidString: "D4E5F6A7-B8C9-0123-DEF0-234567890123")!,
            name: "Uninstall Roocast",
            path: "Command",
            icon: icon,
            isRunning: false,
            profile: nil,
            aliases: ["uninstall", "remove roocast"],
            kind: .uninstall
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
            id: UUID(uuidString: "1A2B3C4D-5E6F-7081-9A0B-1C2D3E4F5061")!,
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
            id: UUID(uuidString: "2B3C4D5E-6F70-8192-A0B1-C2D3E4F50617")!,
            name: "Maximize",
            path: "Command",
            icon: icon,
            isRunning: false,
            profile: nil,
            aliases: ["max"],
            kind: .maximize
        )
    }()

    /// Built-in command: ~60% of visible frame, capped, centered (Tinycast Reasonable Size).
    static let reasonableSize: AppItem = {
        let icon = NSImage(
            systemSymbolName: "macwindow",
            accessibilityDescription: "Reasonable Size"
        )
        icon?.size = NSSize(width: 32, height: 32)
        return AppItem(
            id: UUID(uuidString: "E5F6A7B8-C9D0-1234-EF01-345678901234")!,
            name: "Reasonable Size",
            path: "Command",
            icon: icon,
            isRunning: false,
            profile: nil,
            aliases: ["rs", "reasonable", "reasonable size"],
            kind: .reasonableSize
        )
    }()

    /// Built-in command: snap the prior focused window to the top half of its display.
    static let topHalf: AppItem = {
        let icon = NSImage(
            systemSymbolName: "rectangle.tophalf.filled",
            accessibilityDescription: "Top Half"
        )
        icon?.size = NSSize(width: 32, height: 32)
        return AppItem(
            id: UUID(uuidString: "F6A7B8C9-D0E1-2345-F012-456789012345")!,
            name: "Top Half",
            path: "Command",
            icon: icon,
            isRunning: false,
            profile: nil,
            aliases: ["th", "top"],
            kind: .topHalf
        )
    }()

    /// Built-in command: snap the prior focused window to the bottom half of its display.
    static let bottomHalf: AppItem = {
        let icon = NSImage(
            systemSymbolName: "rectangle.bottomhalf.filled",
            accessibilityDescription: "Bottom Half"
        )
        icon?.size = NSSize(width: 32, height: 32)
        return AppItem(
            id: UUID(uuidString: "A7B8C9D0-E1F2-3456-0123-567890123456")!,
            name: "Bottom Half",
            path: "Command",
            icon: icon,
            isRunning: false,
            profile: nil,
            aliases: ["bh", "bottom"],
            kind: .bottomHalf
        )
    }()

    /// Built-in command: snap to the leading third of the display (Tinycast First Third).
    static let firstThird: AppItem = {
        let icon = NSImage(
            systemSymbolName: "rectangle.leadingthird.inset.filled",
            accessibilityDescription: "First Third"
        )
        icon?.size = NSSize(width: 32, height: 32)
        return AppItem(
            id: UUID(uuidString: "B8C9D0E1-F2A3-4567-1234-678901234567")!,
            name: "First Third",
            path: "Command",
            icon: icon,
            isRunning: false,
            profile: nil,
            aliases: ["ft"],
            kind: .firstThird
        )
    }()

    /// Built-in command: snap to the trailing two-thirds of the display (Tinycast Last Two Thirds).
    static let lastTwoThirds: AppItem = {
        let icon = NSImage(
            systemSymbolName: "rectangle.trailingthird.inset.filled",
            accessibilityDescription: "Last Two Thirds"
        )
        icon?.size = NSSize(width: 32, height: 32)
        return AppItem(
            id: UUID(uuidString: "C9D0E1F2-A3B4-5678-2345-789012345678")!,
            name: "Last Two Thirds",
            path: "Command",
            icon: icon,
            isRunning: false,
            profile: nil,
            aliases: ["ltt"],
            kind: .lastTwoThirds
        )
    }()

    /// Built-in command: keep size, flush the prior focused window to the top edge.
    static let moveToTop: AppItem = {
        let icon = NSImage(
            systemSymbolName: "arrow.up.to.line",
            accessibilityDescription: "Move to Top"
        )
        icon?.size = NSSize(width: 32, height: 32)
        return AppItem(
            id: UUID(uuidString: "D0E1F2A3-B4C5-6789-3456-890123456789")!,
            name: "Move to Top",
            path: "Command",
            icon: icon,
            isRunning: false,
            profile: nil,
            aliases: ["mtt"],
            kind: .moveToTop
        )
    }()

    /// Built-in command: keep size, flush the prior focused window to the bottom edge.
    static let moveToBottom: AppItem = {
        let icon = NSImage(
            systemSymbolName: "arrow.down.to.line",
            accessibilityDescription: "Move to Bottom"
        )
        icon?.size = NSSize(width: 32, height: 32)
        return AppItem(
            id: UUID(uuidString: "E1F2A3B4-C5D6-7890-4567-901234567890")!,
            name: "Move to Bottom",
            path: "Command",
            icon: icon,
            isRunning: false,
            profile: nil,
            aliases: ["mtb"],
            kind: .moveToBottom
        )
    }()

    /// Built-in command: keep size, flush the prior focused window to the left edge.
    static let moveToLeft: AppItem = {
        let icon = NSImage(
            systemSymbolName: "arrow.left.to.line",
            accessibilityDescription: "Move to Left"
        )
        icon?.size = NSSize(width: 32, height: 32)
        return AppItem(
            id: UUID(uuidString: "F2A3B4C5-D6E7-8901-5678-012345678901")!,
            name: "Move to Left",
            path: "Command",
            icon: icon,
            isRunning: false,
            profile: nil,
            aliases: ["mtl"],
            kind: .moveToLeft
        )
    }()

    /// Built-in command: keep size, flush the prior focused window to the right edge.
    static let moveToRight: AppItem = {
        let icon = NSImage(
            systemSymbolName: "arrow.right.to.line",
            accessibilityDescription: "Move to Right"
        )
        icon?.size = NSSize(width: 32, height: 32)
        return AppItem(
            id: UUID(uuidString: "A3B4C5D6-E7F8-9012-6789-123456789012")!,
            name: "Move to Right",
            path: "Command",
            icon: icon,
            isRunning: false,
            profile: nil,
            aliases: ["mtr"],
            kind: .moveToRight
        )
    }()

    /// Lead calculator row — `name` is the answer, `profile` echoes the expression.
    static func calculator(_ result: Calculator.Result) -> AppItem {
        let icon = NSImage(
            systemSymbolName: "plus.forwardslash.minus",
            accessibilityDescription: "Calculator"
        )
        icon?.size = NSSize(width: 32, height: 32)
        return AppItem(
            id: nameBasedUUID("roocast.calc:\(result.expression)=\(result.copyText)"),
            name: result.display,
            path: "Calculator",
            icon: icon,
            isRunning: false,
            profile: result.expression,
            aliases: [],
            kind: .calculator(copyText: result.copyText)
        )
    }

    /// Lead countdown row — `name` is formatted remaining (`5:00`); Enter starts the island.
    static func countdown(_ spec: Countdown.Spec) -> AppItem {
        let icon = NSImage(
            systemSymbolName: "timer",
            accessibilityDescription: "Countdown"
        )
        icon?.size = NSSize(width: 32, height: 32)
        return AppItem(
            id: nameBasedUUID("roocast.countdown:\(spec.seconds)"),
            name: spec.display,
            path: "Countdown",
            icon: icon,
            isRunning: false,
            profile: "Hover × to cancel",
            aliases: [],
            kind: .countdown(seconds: spec.seconds)
        )
    }

    /// Hint row when the user typed `timer` / `countdown` without a valid duration.
    static func countdownHint(verb: String) -> AppItem {
        let icon = NSImage(
            systemSymbolName: "timer",
            accessibilityDescription: "Countdown"
        )
        icon?.size = NSSize(width: 32, height: 32)
        let title = verb.lowercased() == "countdown" ? "Countdown" : "Timer"
        return AppItem(
            id: nameBasedUUID("roocast.countdown.hint:\(verb.lowercased())"),
            name: title,
            path: "Countdown",
            icon: icon,
            isRunning: false,
            profile: "Type a duration — 5m · 1h30m · 90s",
            aliases: [],
            kind: .countdownHint
        )
    }

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

    /// Zoxide frecent match — folder name with abbreviated path as quiet label.
    /// Enter opens `path` in Finder (same as built-in folder shortcuts).
    /// Call from the async zoxide completion path only — not during SwiftUI body.
    static func zoxide(path: String) -> AppItem {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        // Copy before resizing — `icon(forFile:)` may return a shared instance.
        let workspaceIcon = NSWorkspace.shared.icon(forFile: path)
        let icon = (workspaceIcon.copy() as? NSImage) ?? NSImage(size: NSSize(width: 32, height: 32))
        icon.size = NSSize(width: 32, height: 32)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // `z ~` → show "~" rather than the username component of $HOME.
        let name: String
        if path == home {
            name = "~"
        } else if url.lastPathComponent.isEmpty {
            name = path
        } else {
            name = url.lastPathComponent
        }
        return AppItem(
            id: nameBasedUUID("roocast.zoxide:\(path)"),
            name: name,
            path: path,
            icon: icon,
            isRunning: false,
            profile: path == home ? nil : Zoxide.abbreviate(path),
            aliases: [],
            kind: .folder
        )
    }

    /// Lightweight item for unit tests / ranking — no disk icon lookup.
    ///
    /// The default path includes `name`, so two stubs are different rows.
    /// A shared path would share `stableID` and a demote on one would hit both.
    static func stub(
        name: String,
        profile: String? = nil,
        path: String? = nil,
        isRunning: Bool = false
    ) -> AppItem {
        let resolvedPath = path ?? "/Applications/\(name).app"
        return AppItem(
            id: stableID(path: resolvedPath, profile: profile),
            name: name,
            path: resolvedPath,
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
