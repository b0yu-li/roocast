import AppKit
import Combine
import CryptoKit // Legacy .enc migration only — drop with migrateLegacyEncrypted
import Foundation
import Security // Legacy .enc migration only

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

/// Watches the general pasteboard and keeps a bounded, disk-backed history.
///
/// **Why polling:** AppKit has no public notification when *other apps* change
/// `NSPasteboard.general`. Clipboard managers (including Maccy) poll `changeCount`.
///
/// **Threading:** A background `DispatchSource` timer reads only `changeCount`
/// (~every 2s). Pasteboard string reads and `@Published` updates hop to the
/// main actor, so idle main-thread cost is near zero.
///
/// **At rest:** Plain JSON under Application Support. FileVault is the at-rest
/// layer — the old AES-GCM/Keychain scheme only re-implemented what the
/// platform already guarantees, and coupled history to a signing identity.
/// (The pre-v0.10 encrypted blob is migrated once, then the crypto goes away.)
@MainActor
final class ClipboardStore: ObservableObject {
    /// Marker we attach to the pasteboard when *we* write to it, so polling
    /// ignores our own pastes. A foreign copy clears the pasteboard first,
    /// which wipes the marker — so the poll only ever skips a genuine self-write.
    static let internalType = NSPasteboard.PasteboardType("com.roocast.internal")

    /// Never record secrets: skip copies tagged sensitive by any of the marker owners
    /// (password managers, 1Password, Keychain, etc. use the nspasteboard conventions).
    static let sensitiveTypes: Set<NSPasteboard.PasteboardType> = [
        .init("org.nspasteboard.ConcealedType"),
        .init("org.nspasteboard.TransientType"),
        .init("com.apple.is-sensitive"),
    ]

    @Published private(set) var items: [ClipboardItem] = []

    private let maxItems: Int
    private let maxTextLength: Int
    private let pollInterval: TimeInterval
    private let persistDebounce: TimeInterval
    /// `nil` disables disk I/O (useful in unit tests that only exercise filtering).
    private let storageURL: URL?

    private var pollSource: DispatchSourceTimer?
    private let pollQueue = DispatchQueue(label: "com.roocast.clipboard.poll", qos: .utility)
    private var lastChangeCount: Int = -1
    private var persistWorkItem: DispatchWorkItem?
    private var didLoadFromDisk = false

    /// Default on-disk path: plain JSON under Application Support.
    nonisolated static var defaultStorageURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Roocast/clipboard-history.json",
                isDirectory: false
            )
    }

    /// Legacy AES-GCM blob (pre-v0.10) — decrypted once and removed on load.
    nonisolated static var legacyEncryptedStorageURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Roocast/clipboard-history.enc",
                isDirectory: false
            )
    }

    /// Keychain slot the legacy encrypted format kept its AES key in.
    nonisolated static let legacyKeychainService = "com.roocast.app.clipboard"
    nonisolated static let legacyKeychainAccount = "history-aes-key"
    /// File magic the legacy encrypted format started with.
    nonisolated static let legacyMagic = Data("ROOCST01".utf8)

    /// - Parameters:
    ///   - storageURL: Explicit file URL. Ignored when `persistToDisk` is false.
    ///   - persistToDisk: When true (default), writes JSON history to disk.
    ///   - pollInterval: Background changeCount check interval (default 2s — latency is fine).
    ///   - maxItems: History bound. 200 keeps several days of typical copying —
    ///     50 (the old cap) evicted anything older within a day (per focus.log).
    init(
        maxItems: Int = 200,
        maxTextLength: Int = 100_000,
        pollInterval: TimeInterval = 2.0,
        persistDebounce: TimeInterval = 0.5,
        storageURL: URL? = nil,
        persistToDisk: Bool = true
    ) {
        self.maxItems = max(1, maxItems)
        self.maxTextLength = max(1, maxTextLength)
        self.pollInterval = max(0.5, pollInterval)
        self.persistDebounce = persistDebounce
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

    /// Writes text to the general pasteboard without re-recording it in history.
    /// Self-writes are stamped with `internalType` so the poll can identify them
    /// by content, not by a changeCount flag (which races with foreign copies).
    func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string, Self.internalType], owner: nil)
        pb.setString(text, forType: .string)
        pb.setData(Data(), forType: Self.internalType)
        // Load-bearing: a mismatched count means a foreign write the next poll
        // must still see — only sync when the pasteboard is still ours.
        let count = pb.changeCount
        if NSPasteboard.general.changeCount == count {
            lastChangeCount = count
        }
        // Re-recency: pasting from history moves the row back to the top.
        promote(text: text)
        FocusRestorer.log("clipboard: wrote \(text.count) chars to pasteboard (changeCount=\(count))")
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

    /// Delete one entry (tinycast's "Delete Entry") and persist immediately —
    /// a deliberate action must not ride the insert debounce.
    func remove(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items.remove(at: index)
        persistNow()
        FocusRestorer.log("clipboard: removed item (history=\(items.count))")
    }

    /// Move an existing item (matched by text) back to the top of the history.
    private func promote(text: String) {
        guard let index = items.firstIndex(where: { $0.text == text }) else { return }
        guard index != 0 else { return }
        let item = items.remove(at: index)
        items.insert(item, at: 0)
    }

    // MARK: - Pasteboard watch

    private func handlePoll(changeCount count: Int) {
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        ingestCurrentPasteboardIfNeeded()
    }

    private func ingestCurrentPasteboardIfNeeded() {
        let pb = NSPasteboard.general
        // Our own write — the marker only exists while our content is current.
        if pb.types?.contains(Self.internalType) == true { return }
        // Never record secrets (password managers, etc.).
        if let types = pb.types, !Set(types).isDisjoint(with: Self.sensitiveTypes) { return }

        // TODO(image support, intake tinycast): capture .png/.tiff copies here.
        // Tinycast re-encodes TIFF→PNG off the poll thread (Task.detached — a
        // big image takes 100ms+) and stores the PNG blob in an images dir,
        // with the row holding a path; paste writes the PNG back to the board.
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

        // Deduplicate: a re-copy of anything already in history promotes it to
        // the top instead of being dropped for being non-consecutive.
        if let index = items.firstIndex(where: { $0.text == text }) {
            let existing = items.remove(at: index)
            items.insert(existing, at: 0)
            if persist { schedulePersist() }
            return true
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

    // MARK: - Disk persistence

    private func loadJSON(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([ClipboardItem].self, from: data)
            items = Array(decoded.prefix(maxItems))
            FocusRestorer.log("clipboard: loaded \(items.count) items from disk")
        } catch {
            FocusRestorer.log("clipboard: failed to load history — \(error.localizedDescription)")
        }
    }

    private func loadFromDiskIfNeeded() {
        guard !didLoadFromDisk else { return }
        didLoadFromDisk = true
        guard let url = storageURL else { return }

        if FileManager.default.fileExists(atPath: url.path) {
            loadJSON(from: url)
            return
        }

        // One-shot: decrypt the pre-v0.10 encrypted blob into plain JSON.
        let legacy = Self.legacyEncryptedStorageURL
        if storageURL == Self.defaultStorageURL,
           FileManager.default.fileExists(atPath: legacy.path)
        {
            migrateLegacyEncrypted(from: legacy, to: url)
            return
        }

        FocusRestorer.log("clipboard: no history file yet at \(url.path)")
    }

    /// Decrypts the pre-v0.10 AES-GCM blob into plain JSON at `to`, then removes
    /// the blob and its Keychain key. On failure the blob is left untouched
    /// (next launch retries) — history must never be lost to a cleanup.
    private func migrateLegacyEncrypted(from url: URL, to: URL) {
        do {
            let blob = try Data(contentsOf: url)
            guard let key = Self.legacyKeychainKey() else {
                FocusRestorer.log("clipboard: legacy key missing from Keychain — cannot migrate")
                return
            }
            let plaintext = try Self.decryptLegacyBlob(blob, using: key)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            items = Array(try decoder.decode([ClipboardItem].self, from: plaintext).prefix(maxItems))
            persistNow()
            try? FileManager.default.removeItem(at: url)
            Self.deleteLegacyKeychainKey()
            FocusRestorer.log("clipboard: migrated legacy encrypted history (\(items.count) items)")
        } catch {
            FocusRestorer.log("clipboard: legacy migration failed — \(error.localizedDescription)")
        }
    }

    /// Decrypts a legacy "ROOCST01"-prefixed AES-GCM blob. Test seam for the
    /// format itself; production feeds it the Keychain key.
    nonisolated static func decryptLegacyBlob(_ blob: Data, using key: SymmetricKey) throws -> Data {
        guard blob.count > legacyMagic.count, blob.prefix(legacyMagic.count) == legacyMagic else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let box = try AES.GCM.SealedBox(combined: blob.dropFirst(legacyMagic.count))
        return try AES.GCM.open(box, using: key)
    }

    /// The AES key the legacy format kept in the Keychain (read-only).
    nonisolated private static func legacyKeychainKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyKeychainService,
            kSecAttrAccount as String: legacyKeychainAccount,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    nonisolated private static func deleteLegacyKeychainKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyKeychainService,
            kSecAttrAccount as String: legacyKeychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
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

    /// Atomic write of the current history snapshot.
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

            let tmp = url.appendingPathExtension("tmp")
            try json.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: tmp, to: url)
            FocusRestorer.log(
                "clipboard: persisted \(snapshot.count) items (\(json.count) bytes)"
            )
        } catch {
            FocusRestorer.log("clipboard: persist failed — \(error.localizedDescription)")
        }
    }
}

/// Posts ⌘V after focus has returned to the previous app.
///
/// Prefer Accessibility trust so macOS delivers the synthetic keys. We still post
/// even when `isTrusted` is false (TCC can lag after the user enables the toggle);
/// text is always on the pasteboard so ⌘V manually still works.
enum ClipboardPaster {
    static func pasteCommandV(after delay: TimeInterval = 0.15) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // Never prompt here — `pasteClipboardItem` already asked once.
            let trusted = FocusRestorer.isTrusted()
            if !trusted {
                FocusRestorer.log(
                    "clipboard: posting ⌘V without AX trust (may be dropped; text is on pasteboard)"
                )
            }

            guard let source = CGEventSource(stateID: .hidSystemState) else {
                FocusRestorer.log("clipboard: paste failed — no CGEventSource")
                return
            }
            source.setLocalEventsFilterDuringSuppressionState(
                [.permitLocalMouseEvents, .permitLocalKeyboardEvents],
                state: .eventSuppressionStateSuppressionInterval
            )

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
            FocusRestorer.log("clipboard: posted ⌘V (frontmost=\(front), ax=\(trusted ? 1 : 0))")
        }
    }
}
