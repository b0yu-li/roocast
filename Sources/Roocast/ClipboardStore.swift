import AppKit
import Combine
import CryptoKit
import Foundation

struct ClipboardItem: Identifiable, Equatable, Codable {
    let id: UUID
    let text: String
    let createdAt: Date

    /// Single-line preview suitable for list rows.
    var preview: String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= 120 { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: 120)
        return String(collapsed[..<end]) + "…"
    }
}

/// Watches the general pasteboard and keeps a bounded, encrypted disk-backed history.
///
/// **Why polling:** AppKit has no public notification when *other apps* change
/// `NSPasteboard.general`. Clipboard managers (including Maccy) poll `changeCount`.
///
/// **Threading:** A background `DispatchSource` timer reads only `changeCount`
/// (~every 2s). Pasteboard string reads and `@Published` updates hop to the
/// main actor, so idle main-thread cost is near zero.
///
/// **Encryption:** History is AES-GCM sealed with a Keychain key
/// (`ThisDeviceOnly`). The file alone is useless on another Mac.
@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private let maxItems: Int
    private let maxTextLength: Int
    private let pollInterval: TimeInterval
    private let persistDebounce: TimeInterval
    /// `nil` disables disk I/O (useful in unit tests that only exercise filtering).
    private let storageURL: URL?
    /// Injected for tests; production uses Keychain via `ClipboardCrypto.loadOrCreateKey()`.
    private let injectedEncryptionKey: SymmetricKey?

    private var pollSource: DispatchSourceTimer?
    private let pollQueue = DispatchQueue(label: "com.roocast.clipboard.poll", qos: .utility)
    private var lastChangeCount: Int = -1
    /// Skip the next change when we write the pasteboard ourselves (paste path).
    private var ignoreNextChange = false
    private var persistWorkItem: DispatchWorkItem?
    private var didLoadFromDisk = false
    private var cachedEncryptionKey: SymmetricKey?

    /// Default on-disk path: encrypted blob under Application Support.
    nonisolated static var defaultStorageURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Roocast/clipboard-history.enc",
                isDirectory: false
            )
    }

    /// Legacy plaintext path from the first persistence PoC — migrated on load.
    nonisolated static var legacyPlaintextStorageURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Roocast/clipboard-history.json",
                isDirectory: false
            )
    }

    /// - Parameters:
    ///   - storageURL: Explicit file URL. Ignored when `persistToDisk` is false.
    ///   - persistToDisk: When true (default), writes encrypted history to disk.
    ///   - encryptionKey: Optional fixed key (tests). Production omits this and uses Keychain.
    ///   - pollInterval: Background changeCount check interval (default 2s — latency is fine).
    init(
        maxItems: Int = 50,
        maxTextLength: Int = 100_000,
        pollInterval: TimeInterval = 2.0,
        persistDebounce: TimeInterval = 0.5,
        storageURL: URL? = nil,
        persistToDisk: Bool = true,
        encryptionKey: SymmetricKey? = nil
    ) {
        self.maxItems = max(1, maxItems)
        self.maxTextLength = max(1, maxTextLength)
        self.pollInterval = max(0.5, pollInterval)
        self.persistDebounce = persistDebounce
        self.injectedEncryptionKey = encryptionKey
        if persistToDisk {
            self.storageURL = storageURL ?? Self.defaultStorageURL
        } else {
            self.storageURL = nil
        }
    }

    /// Loads persisted history from disk (idempotent). Called automatically by `startMonitoring()`.
    func loadPersistedHistory() {
        loadFromDiskIfNeeded()
    }

    func startMonitoring() {
        guard pollSource == nil else { return }
        loadFromDiskIfNeeded()
        lastChangeCount = NSPasteboard.general.changeCount
        // Capture current pasteboard so a fresh install / empty history still has one item.
        ingestCurrentPasteboardIfNeeded()

        let source = DispatchSource.makeTimerSource(queue: pollQueue)
        // Slight leeway: we don't need sub-second precision.
        source.schedule(deadline: .now() + pollInterval, repeating: pollInterval, leeway: .milliseconds(250))
        source.setEventHandler { [weak self] in
            // Cheap Int read off the main thread; hop only when the count moves.
            let count = NSPasteboard.general.changeCount
            Task { @MainActor in
                self?.handlePoll(changeCount: count)
            }
        }
        source.resume()
        pollSource = source

        let path = storageURL?.path ?? "(memory-only)"
        FocusRestorer.log(
            "clipboard: monitoring started (interval=\(pollInterval)s bg, max=\(maxItems), store=\(path))"
        )
    }

    func stopMonitoring() {
        pollSource?.setEventHandler {}
        pollSource?.cancel()
        pollSource = nil
        persistWorkItem?.cancel()
        persistWorkItem = nil
        persistNow()
    }

    /// Writes text to the general pasteboard without recording a duplicate history entry.
    func copyToPasteboard(_ text: String) {
        ignoreNextChange = true
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastChangeCount = pb.changeCount
        FocusRestorer.log("clipboard: wrote \(text.count) chars to pasteboard (changeCount=\(lastChangeCount))")
    }

    /// Case-insensitive substring filter; empty query returns full history (newest first).
    func items(matching query: String) -> [ClipboardItem] {
        let lowered = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else { return items }
        return items.filter { $0.text.lowercased().contains(lowered) }
    }

    /// Test / PoC helper — insert without touching the system pasteboard.
    func prependForTesting(_ text: String) {
        insertItem(text: text, persist: true)
    }

    // MARK: - Pasteboard watch

    private func handlePoll(changeCount count: Int) {
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        if ignoreNextChange {
            ignoreNextChange = false
            FocusRestorer.log("clipboard: skipped self-write changeCount=\(count)")
            return
        }

        ingestCurrentPasteboardIfNeeded()
    }

    private func ingestCurrentPasteboardIfNeeded() {
        let pb = NSPasteboard.general
        guard let text = pb.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            return
        }

        insertItem(text: text, persist: true)
    }

    @discardableResult
    private func insertItem(text: String, persist: Bool) -> Bool {
        if text.count > maxTextLength {
            FocusRestorer.log(
                "clipboard: skipped oversized item len=\(text.count) (max=\(maxTextLength))"
            )
            return false
        }

        // Deduplicate consecutive identical copies.
        if items.first?.text == text {
            return false
        }

        let item = ClipboardItem(id: UUID(), text: text, createdAt: Date())
        items.insert(item, at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        FocusRestorer.log("clipboard: captured item len=\(text.count) history=\(items.count)")
        if persist {
            schedulePersist()
        }
        return true
    }

    // MARK: - Disk persistence (encrypted)

    private func encryptionKey() throws -> SymmetricKey {
        if let injectedEncryptionKey {
            return injectedEncryptionKey
        }
        if let cachedEncryptionKey {
            return cachedEncryptionKey
        }
        let key = try ClipboardCrypto.loadOrCreateKey()
        cachedEncryptionKey = key
        return key
    }

    private func loadFromDiskIfNeeded() {
        guard !didLoadFromDisk else { return }
        didLoadFromDisk = true
        guard let url = storageURL else { return }

        if FileManager.default.fileExists(atPath: url.path) {
            loadEncryptedOrLegacy(from: url, removeLegacyPlaintext: false)
            return
        }

        // Migrate first-PoC plaintext JSON if present.
        let legacy = Self.legacyPlaintextStorageURL
        if storageURL == Self.defaultStorageURL,
           FileManager.default.fileExists(atPath: legacy.path)
        {
            FocusRestorer.log("clipboard: migrating legacy plaintext history")
            loadEncryptedOrLegacy(from: legacy, removeLegacyPlaintext: true)
            // Rewrite encrypted at the new path.
            persistNow()
            return
        }

        FocusRestorer.log("clipboard: no history file yet at \(url.path)")
    }

    private func loadEncryptedOrLegacy(from url: URL, removeLegacyPlaintext: Bool) {
        do {
            let data = try Data(contentsOf: url)
            let plaintext: Data
            if ClipboardCrypto.isEncryptedBlob(data) {
                let key = try encryptionKey()
                plaintext = try ClipboardCrypto.open(data, using: key)
            } else {
                // Legacy unencrypted JSON from the first persistence PoC.
                plaintext = data
                FocusRestorer.log("clipboard: loaded legacy plaintext (will re-encrypt on save)")
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([ClipboardItem].self, from: plaintext)
            items = Array(decoded.prefix(maxItems))
            FocusRestorer.log("clipboard: loaded \(items.count) items from disk")

            if removeLegacyPlaintext {
                try? FileManager.default.removeItem(at: url)
            }
        } catch {
            FocusRestorer.log("clipboard: failed to load history — \(error.localizedDescription)")
        }
    }

    private func schedulePersist() {
        guard storageURL != nil else { return }
        persistWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistNow()
        }
        persistWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + persistDebounce, execute: work)
    }

    /// Atomic encrypted write of the current history snapshot.
    func persistNow() {
        guard let url = storageURL else { return }
        let snapshot = items
        let directory = url.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let json = try encoder.encode(snapshot)
            let key = try encryptionKey()
            let sealed = try ClipboardCrypto.seal(json, using: key)

            let tmp = url.appendingPathExtension("tmp")
            try sealed.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: tmp, to: url)
            FocusRestorer.log(
                "clipboard: persisted \(snapshot.count) items encrypted (\(sealed.count) bytes)"
            )
        } catch {
            FocusRestorer.log("clipboard: persist failed — \(error.localizedDescription)")
        }
    }
}

/// Posts ⌘V after focus has returned to the previous app.
enum ClipboardPaster {
    static func pasteCommandV(after delay: TimeInterval = 0.08) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let source = CGEventSource(stateID: .hidSystemState) else {
                FocusRestorer.log("clipboard: paste failed — no CGEventSource")
                return
            }
            let keyV: CGKeyCode = 9
            guard
                let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
            else {
                FocusRestorer.log("clipboard: paste failed — could not create key events")
                return
            }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
            FocusRestorer.log("clipboard: posted ⌘V (frontmost=\(front))")
        }
    }
}
