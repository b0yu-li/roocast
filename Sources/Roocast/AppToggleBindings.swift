import Foundation
import CoreGraphics
import Carbon.HIToolbox

/// One app-toggle chord from `~/.config/roocast/bindings.toml`.
struct AppToggleBinding: Equatable, Sendable {
    let key: String
    let keyCode: UInt16
    let modifiers: Set<AppToggleModifier>
    /// Display / `.app` name (e.g. `Ghostty`) when `bundleID` is absent.
    let appName: String?
    let bundleID: String?

    var label: String {
        if let bundleID, !bundleID.isEmpty { return bundleID }
        return appName ?? "?"
    }
}

enum AppToggleModifier: String, Equatable, Sendable, Hashable {
    case leftControl
}

enum AppToggleBindingsError: Error, Equatable, CustomStringConvertible {
    case fileUnreadable(String)
    case emptyKey
    case unknownKey(String)
    case unknownModifier(String)
    case missingTarget
    case noModifiers

    var description: String {
        switch self {
        case .fileUnreadable(let path): return "cannot read \(path)"
        case .emptyKey: return "toggle is missing key"
        case .unknownKey(let key): return "unknown key \"\(key)\""
        case .unknownModifier(let name): return "unknown modifier \"\(name)\""
        case .missingTarget: return "toggle needs app or bundle_id"
        case .noModifiers: return "toggle needs at least one modifier"
        }
    }
}

/// Load / parse Left-Control app-toggle bindings (minimal TOML subset — no SPM TOML dep).
enum AppToggleBindings {
    static let relativeConfigPath = ".config/roocast/bindings.toml"

    static func defaultConfigURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appendingPathComponent(relativeConfigPath)
    }

    /// Returns bindings, or empty if the file is missing. Throws on unreadable / invalid entries.
    static func load(from url: URL = defaultConfigURL()) throws -> [AppToggleBinding] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else {
            throw AppToggleBindingsError.fileUnreadable(url.path)
        }
        return try parse(text)
    }

    /// Parse `[[toggle]]` tables. Unknown top-level keys are ignored; bad toggles throw.
    static func parse(_ text: String) throws -> [AppToggleBinding] {
        var bindings: [AppToggleBinding] = []
        var current: ToggleDraft?
        var errors: [AppToggleBindingsError] = []

        func flush() {
            guard let draft = current else { return }
            current = nil
            switch draft.build() {
            case .success(let binding):
                bindings.append(binding)
            case .failure(let error):
                errors.append(error)
            }
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line == "[[toggle]]" {
                flush()
                current = ToggleDraft()
                continue
            }

            guard current != nil else { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)

            switch key {
            case "key":
                current?.key = unquote(value)
            case "app":
                current?.appName = unquote(value)
            case "bundle_id":
                current?.bundleID = unquote(value)
            case "modifiers":
                current?.modifierNames = parseStringArray(value)
            default:
                break
            }
        }
        flush()

        if let first = errors.first {
            throw first
        }
        return bindings
    }

    // MARK: - Key codes (ANSI US)

    static func keyCode(forKey key: String) -> UInt16? {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.count == 1, let ch = normalized.first else {
            // Named keys
            switch normalized {
            case "space": return UInt16(kVK_Space)
            case "tab": return UInt16(kVK_Tab)
            case "return", "enter": return UInt16(kVK_Return)
            case "escape", "esc": return UInt16(kVK_Escape)
            default: return nil
            }
        }
        switch ch {
        case "a": return UInt16(kVK_ANSI_A)
        case "b": return UInt16(kVK_ANSI_B)
        case "c": return UInt16(kVK_ANSI_C)
        case "d": return UInt16(kVK_ANSI_D)
        case "e": return UInt16(kVK_ANSI_E)
        case "f": return UInt16(kVK_ANSI_F)
        case "g": return UInt16(kVK_ANSI_G)
        case "h": return UInt16(kVK_ANSI_H)
        case "i": return UInt16(kVK_ANSI_I)
        case "j": return UInt16(kVK_ANSI_J)
        case "k": return UInt16(kVK_ANSI_K)
        case "l": return UInt16(kVK_ANSI_L)
        case "m": return UInt16(kVK_ANSI_M)
        case "n": return UInt16(kVK_ANSI_N)
        case "o": return UInt16(kVK_ANSI_O)
        case "p": return UInt16(kVK_ANSI_P)
        case "q": return UInt16(kVK_ANSI_Q)
        case "r": return UInt16(kVK_ANSI_R)
        case "s": return UInt16(kVK_ANSI_S)
        case "t": return UInt16(kVK_ANSI_T)
        case "u": return UInt16(kVK_ANSI_U)
        case "v": return UInt16(kVK_ANSI_V)
        case "w": return UInt16(kVK_ANSI_W)
        case "x": return UInt16(kVK_ANSI_X)
        case "y": return UInt16(kVK_ANSI_Y)
        case "z": return UInt16(kVK_ANSI_Z)
        case "0": return UInt16(kVK_ANSI_0)
        case "1": return UInt16(kVK_ANSI_1)
        case "2": return UInt16(kVK_ANSI_2)
        case "3": return UInt16(kVK_ANSI_3)
        case "4": return UInt16(kVK_ANSI_4)
        case "5": return UInt16(kVK_ANSI_5)
        case "6": return UInt16(kVK_ANSI_6)
        case "7": return UInt16(kVK_ANSI_7)
        case "8": return UInt16(kVK_ANSI_8)
        case "9": return UInt16(kVK_ANSI_9)
        default: return nil
        }
    }

    // MARK: - Match (pure)

    /// IOKit device-dependent flag: left Control is down.
    static let leftControlDeviceMask: UInt64 = 0x0000_0001
    /// IOKit device-dependent flag: right Control is down.
    static let rightControlDeviceMask: UInt64 = 0x0000_2000

    /// Whether this key event should fire (and be swallowed for) `binding`.
    static func matches(
        _ binding: AppToggleBinding,
        keyCode: UInt16,
        flagsRaw: UInt64,
        isKeyEvent: Bool,
        isAutorepeat: Bool,
        leftControlDown: Bool?
    ) -> Bool {
        guard isKeyEvent, !isAutorepeat else { return false }
        guard keyCode == binding.keyCode else { return false }

        let flags = CGEventFlags(rawValue: flagsRaw)
        // Exact chord for v1: leftControl only — no ⌘⌥⇧.
        guard !flags.contains(.maskCommand),
              !flags.contains(.maskAlternate),
              !flags.contains(.maskShift)
        else { return false }

        guard binding.modifiers == [.leftControl] else { return false }
        guard flags.contains(.maskControl) else { return false }

        let leftDevice = (flagsRaw & leftControlDeviceMask) != 0
        let rightDevice = (flagsRaw & rightControlDeviceMask) != 0
        if leftDevice { return true }
        if rightDevice { return false }
        // Device bits missing on some events — fall back to tracked Left Control state.
        if let leftControlDown {
            return leftControlDown
        }
        // No device bits and no tracker: reject (never treat Right Control as Left).
        return false
    }

    static func binding(
        matchingKeyCode keyCode: UInt16,
        flagsRaw: UInt64,
        isKeyEvent: Bool,
        isAutorepeat: Bool,
        leftControlDown: Bool?,
        in bindings: [AppToggleBinding]
    ) -> AppToggleBinding? {
        bindings.first {
            matches(
                $0,
                keyCode: keyCode,
                flagsRaw: flagsRaw,
                isKeyEvent: isKeyEvent,
                isAutorepeat: isAutorepeat,
                leftControlDown: leftControlDown
            )
        }
    }

    // MARK: - TOML helpers

    private struct ToggleDraft {
        var key: String?
        var appName: String?
        var bundleID: String?
        var modifierNames: [String] = []

        func build() -> Result<AppToggleBinding, AppToggleBindingsError> {
            guard let key, !key.isEmpty else { return .failure(.emptyKey) }
            guard let keyCode = AppToggleBindings.keyCode(forKey: key) else {
                return .failure(.unknownKey(key))
            }
            let app = appName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let bundle = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasApp = !(app ?? "").isEmpty
            let hasBundle = !(bundle ?? "").isEmpty
            guard hasApp || hasBundle else { return .failure(.missingTarget) }

            var modifiers: Set<AppToggleModifier> = []
            for name in modifierNames {
                guard let mod = AppToggleModifier(rawValue: name) else {
                    return .failure(.unknownModifier(name))
                }
                modifiers.insert(mod)
            }
            if modifiers.isEmpty { return .failure(.noModifiers) }

            return .success(
                AppToggleBinding(
                    key: key.lowercased(),
                    keyCode: keyCode,
                    modifiers: modifiers,
                    appName: hasApp ? app : nil,
                    bundleID: hasBundle ? bundle : nil
                )
            )
        }
    }

    private static func stripComment(_ line: String) -> String {
        var inQuote = false
        for (idx, ch) in line.enumerated() {
            if ch == "\"" { inQuote.toggle() }
            if ch == "#", !inQuote {
                return String(line.prefix(idx))
            }
        }
        return line
    }

    private static func unquote(_ value: String) -> String {
        var s = value.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("\""), s.hasSuffix("\""), s.count >= 2 {
            s.removeFirst()
            s.removeLast()
        }
        return s
    }

    private static func parseStringArray(_ value: String) -> [String] {
        var s = value.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("["), s.hasSuffix("]") else { return [] }
        s.removeFirst()
        s.removeLast()
        return s.split(separator: ",").map { unquote(String($0)) }.filter { !$0.isEmpty }
    }
}
