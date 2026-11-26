import AppKit
import Combine
import CryptoKit // Legacy .enc migration only — drop with migrateLegacyEncrypted
import Foundation
import Security // Legacy .enc migration only

struct ClipboardItem: Identifiable, Equatable, Codable {
    enum Kind: String, Codable {
        case text
        case image
    }

    let id: UUID
    let kind: Kind
    /// Plain text for `.text` rows; empty for `.image`.
    let text: String
    /// Absolute path: owned PNG under `images/`, or an unowned Finder file pointer.
    let imagePath: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        kind: Kind = .text,
        text: String,
        imagePath: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imagePath = imagePath
        self.createdAt = createdAt
    }

    /// Filename for an unowned path pointer (empty for owned blobs / text).
    var imageDisplayName: String? {
        guard kind == .image, let imagePath, !imagePath.isEmpty else { return nil }
        let name = URL(fileURLWithPath: imagePath).lastPathComponent
        return name.isEmpty ? nil : name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        // pre-v0.11 JSON had only id/text/createdAt — treat as text.
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .text
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
    }

    /// Single-line preview suitable for list rows.
    var preview: String {
        switch kind {
        case .image:
            // Ownership is decided at capture; owned blobs leave `text` empty and
            // use UUID filenames — show "Image". Pointers stash the filename in `text`.
            return ClipboardImagePolicy.previewLabel(
                displayName: text.isEmpty ? imageDisplayName : text,
                isOwnedBlob: text.isEmpty
            )
        case .text:
            let collapsed = text
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if collapsed.count <= 120 { return collapsed }
            let end = collapsed.index(collapsed.startIndex, offsetBy: 120)
            return String(collapsed[..<end]) + "…"
        }
    }

    /// When the entry was copied — today shows a clock time, older shows the
    /// relative date ("Yesterday", "Nov 8, 2026").
    var timeLabel: String {
        if Calendar.current.isDateInToday(createdAt) {
            return Self.timeOnlyFormatter.string(from: createdAt)
        }
        return Self.relativeDateFormatter.string(from: createdAt)
    }

    private static let timeOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let relativeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
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
/// **Images:** Durable image *file URLs* (Finder) are stored as path pointers —
/// never copied into Application Support (Tinycast `.file` style). Bare inline
/// `.png`/`.tiff` (Copy Image / screenshot) still become owned PNG blobs under
/// `images/`. Paste publishes `fileURL` (+ path string), not PNG bytes.
/// Soft-cap applies only to owned blobs.
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
    private let maxImages: Int
    private let maxTextLength: Int
    private let pollInterval: TimeInterval
    private let persistDebounce: TimeInterval
    /// `nil` disables disk I/O (useful in unit tests that only exercise filtering).
    private let storageURL: URL?
    private let imagesDirectoryURL: URL?

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

    nonisolated static var defaultImagesDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Roocast/images",
                isDirectory: true
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
    ///   - imagesDirectoryURL: Owned PNG blob directory. Defaults beside JSON.
    ///   - persistToDisk: When true (default), writes JSON history to disk.
    ///   - pollInterval: Background changeCount check interval (default 2s — latency is fine).
    ///   - maxItems: History bound. 200 keeps several days of typical copying —
    ///     50 (the old cap) evicted anything older within a day (per focus.log).
    ///   - maxImages: Soft cap on owned image rows (default 30) for the memory budget.
    init(
        maxItems: Int = 200,
        maxImages: Int = 30,
        maxTextLength: Int = 100_000,
        pollInterval: TimeInterval = 2.0,
        persistDebounce: TimeInterval = 0.5,
        storageURL: URL? = nil,
        imagesDirectoryURL: URL? = nil,
        persistToDisk: Bool = true
    ) {
        self.maxItems = max(1, maxItems)
        self.maxImages = max(1, maxImages)
        self.maxTextLength = max(1, maxTextLength)
        self.pollInterval = max(0.5, pollInterval)
        self.persistDebounce = persistDebounce
        if persistToDisk {
            let jsonURL = storageURL ?? Self.defaultStorageURL
            self.storageURL = jsonURL
            self.imagesDirectoryURL = imagesDirectoryURL
                ?? jsonURL.deletingLastPathComponent().appendingPathComponent("images", isDirectory: true)
        } else {
            self.storageURL = nil
            // Tests may still pass an images dir to exercise blob ownership.
            self.imagesDirectoryURL = imagesDirectoryURL
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
            "clipboard: monitoring started (interval=\(pollInterval)s bg, max=\(maxItems), images≤\(maxImages), store=\(path))"
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

    /// Absolute URL for an image row (owned blob or unowned Finder pointer), if on disk.
    func imageURL(for item: ClipboardItem) -> URL? {
        guard item.kind == .image, let path = item.imagePath, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// Whether `item`'s image lives under our `images/` directory (safe to delete).
    func ownsImage(_ item: ClipboardItem) -> Bool {
        guard item.kind == .image, let path = item.imagePath else { return false }
        return ownsImage(at: path)
    }

    /// Writes an item back to the general pasteboard without re-recording it.
    /// Images: fileURL pointer (+ path string) — never PNG bytes (`ClipboardImagePolicy`).
    func copyToPasteboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        switch item.kind {
        case .text:
            pb.clearContents()
            pb.declareTypes([.string, Self.internalType], owner: nil)
            pb.setString(item.text, forType: .string)
            pb.setData(Data(), forType: Self.internalType)
            FocusRestorer.log("clipboard: wrote \(item.text.count) chars to pasteboard")
        case .image:
            guard let url = imageURL(for: item) else {
                FocusRestorer.log("clipboard: image paste failed — missing file")
                return
            }
            assert(!ClipboardImagePolicy.pastesImageBytes)
            pb.clearContents()
            var types: [NSPasteboard.PasteboardType] = [Self.internalType]
            if ClipboardImagePolicy.pastesFileURL { types.insert(.fileURL, at: 0) }
            if ClipboardImagePolicy.pastesPathAsString {
                types.insert(.string, at: types.count - 1)
            }
            pb.declareTypes(types, owner: nil)
            if ClipboardImagePolicy.pastesFileURL {
                pb.setData(url.dataRepresentation, forType: .fileURL)
            }
            if ClipboardImagePolicy.pastesPathAsString {
                pb.setString(url.path, forType: .string)
            }
            pb.setData(Data(), forType: Self.internalType)
            FocusRestorer.log("clipboard: wrote image file pointer \(url.lastPathComponent)")
        }
        let count = pb.changeCount
        if NSPasteboard.general.changeCount == count {
            lastChangeCount = count
        }
        promote(item)
    }

    /// Convenience for text-only callers / tests.
    func copyToPasteboard(_ text: String) {
        copyToPasteboard(ClipboardItem(kind: .text, text: text))
    }

    /// Case-insensitive substring filter; empty query returns full history (newest first).
    /// Images match the label "Image" only (no OCR).
    func items(matching query: String) -> [ClipboardItem] {
        let lowered = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.isEmpty else { return items }
        return items.filter { item in
            switch item.kind {
            case .image:
                return item.preview.lowercased().contains(lowered)
                    || (item.imagePath?.lowercased().contains(lowered) ?? false)
            case .text:
                return item.text.lowercased().contains(lowered)
            }
        }
    }

    /// Test / PoC helper — insert without touching the system pasteboard.
    func prependForTesting(_ text: String) {
        insertText(text, persist: true)
    }

    /// Test helper — write a PNG into the images dir and insert an image row.
    @discardableResult
    func prependImageForTesting(_ pngData: Data) -> ClipboardItem? {
        insertImage(pngData: pngData, persist: true)
    }

    /// Test helper — insert an unowned Finder-style image pointer (no copy into `images/`).
    @discardableResult
    func prependImagePointerForTesting(_ path: String) -> ClipboardItem? {
        insertImagePointer(path: path, persist: true)
    }

    /// Delete one entry (tinycast's "Delete Entry") and persist immediately —
    /// a deliberate action must not ride the insert debounce.
    func remove(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let removed = items.remove(at: index)
        deleteOwnedImage(removed)
        persistNow()
        FocusRestorer.log("clipboard: removed item (history=\(items.count))")
    }

    /// Delete every entry (tinycast's "Delete All Entries") and persist immediately —
    /// a deliberate action must not ride the insert debounce.
    func removeAll() {
        let snapshot = items
        items.removeAll()
        for item in snapshot {
            deleteOwnedImage(item)
        }
        persistNow()
        FocusRestorer.log("clipboard: removed all items")
    }

    /// Move an existing item back to the top of the history.
    private func promote(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            // Text paste from a synthetic item: match by text content.
            if item.kind == .text,
               let textIndex = items.firstIndex(where: { $0.kind == .text && $0.text == item.text }),
               textIndex != 0
            {
                let existing = items.remove(at: textIndex)
                items.insert(existing, at: 0)
            }
            return
        }
        guard index != 0 else { return }
        let existing = items.remove(at: index)
        items.insert(existing, at: 0)
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

        // Finder puts a file-type *icon* as .png/.tiff beside public.file-url.
        // Prefer the durable file as an unowned pointer — never copy into `images/`.
        if let fileURL = ClipboardPasteboardFiles.firstDurableImageFileURL(on: pb) {
            assert(!ClipboardImagePolicy.storesOwnedBlob(hasDurableImageFileURL: true))
            insertImagePointer(path: fileURL.path, persist: true)
            return
        }

        // Any other durable file URL: never ingest the icon PNG/TIFF. Record the path.
        if let fileURL = ClipboardPasteboardFiles.durableFileURLs(on: pb).first {
            insertText(fileURL.path, persist: true)
            return
        }

        // Bare inline image (browser Copy Image / screenshot-to-clipboard) — no file URL.
        if let type = pb.availableType(from: [.png, .tiff]),
           let data = pb.data(forType: type)
        {
            assert(ClipboardImagePolicy.storesOwnedBlob(hasDurableImageFileURL: false))
            let isPNG = type == .png
            Task.detached(priority: .utility) { [weak self] in
                let png: Data?
                if isPNG {
                    png = data
                } else {
                    png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:])
                }
                guard let png else {
                    await MainActor.run {
                        FocusRestorer.log("clipboard: TIFF→PNG failed — skipped image")
                    }
                    return
                }
                await self?.insertImage(pngData: png, persist: true)
            }
            return
        }

        guard let text = pb.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            return
        }

        insertText(text, persist: true)
    }

    @discardableResult
    private func insertText(_ text: String, persist: Bool) -> Bool {
        if text.count > maxTextLength {
            FocusRestorer.log(
                "clipboard: skipped oversized item len=\(text.count) (max=\(maxTextLength))"
            )
            return false
        }

        // Deduplicate: a re-copy of anything already in history promotes it to
        // the top instead of being dropped for being non-consecutive.
        if let index = items.firstIndex(where: { $0.kind == .text && $0.text == text }) {
            let existing = items.remove(at: index)
            items.insert(existing, at: 0)
            if persist { schedulePersist() }
            return true
        }

        let item = ClipboardItem(kind: .text, text: text, createdAt: Date())
        items.insert(item, at: 0)
        trimToMaxItems()
        FocusRestorer.log("clipboard: captured text len=\(text.count) history=\(items.count)")
        if persist {
            schedulePersist()
        }
        return true
    }

    /// Unowned Finder-style pointer — references the file where it lies.
    @discardableResult
    private func insertImagePointer(path: String, persist: Bool) -> ClipboardItem? {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !standardized.isEmpty else { return nil }

        if let index = items.firstIndex(where: {
            $0.kind == .image && $0.imagePath.map {
                URL(fileURLWithPath: $0).standardizedFileURL.path
            } == standardized
        }) {
            let existing = items.remove(at: index)
            items.insert(existing, at: 0)
            if persist { schedulePersist() }
            return existing
        }

        let name = URL(fileURLWithPath: standardized).lastPathComponent
        let item = ClipboardItem(
            kind: .image,
            text: name,
            imagePath: standardized,
            createdAt: Date()
        )
        items.insert(item, at: 0)
        trimToMaxItems()
        FocusRestorer.log(
            "clipboard: captured image pointer \(name) history=\(items.count) owned=\(ownedImageCount)"
        )
        if persist {
            schedulePersist()
        }
        return item
    }

    @discardableResult
    private func insertImage(pngData: Data, persist: Bool) -> ClipboardItem? {
        guard let imagesDirectoryURL else {
            FocusRestorer.log("clipboard: no images dir — skipped image capture")
            return nil
        }

        let filename = UUID().uuidString + ".png"
        let fileURL = imagesDirectoryURL.appendingPathComponent(filename, isDirectory: false)

        do {
            try FileManager.default.createDirectory(
                at: imagesDirectoryURL,
                withIntermediateDirectories: true
            )
            try pngData.write(to: fileURL, options: .atomic)
        } catch {
            FocusRestorer.log("clipboard: image write failed — \(error.localizedDescription)")
            return nil
        }

        // Owned blob: empty `text` so preview stays "Image" (UUID.png is noise).
        let item = ClipboardItem(
            kind: .image,
            text: "",
            imagePath: fileURL.path,
            createdAt: Date()
        )
        items.insert(item, at: 0)
        enforceImageCap()
        trimToMaxItems()
        FocusRestorer.log(
            "clipboard: captured owned image (\(pngData.count) bytes) history=\(items.count) owned=\(ownedImageCount)"
        )
        if persist {
            schedulePersist()
        }
        return item
    }

    private var ownedImageCount: Int {
        items.reduce(0) { count, item in
            let owned = ownsImage(item)
            guard ClipboardImagePolicy.countsTowardImageCap(isOwnedBlob: owned) else { return count }
            return count + 1
        }
    }

    /// Drop oldest *owned* image rows when over the soft cap; never delete user files.
    private func enforceImageCap() {
        while ownedImageCount > maxImages {
            guard let index = items.lastIndex(where: { ownsImage($0) }) else { break }
            let removed = items.remove(at: index)
            deleteOwnedImage(removed)
        }
    }

    private func trimToMaxItems() {
        guard items.count > maxItems else { return }
        let dropped = Array(items.suffix(items.count - maxItems))
        items = Array(items.prefix(maxItems))
        for item in dropped {
            deleteOwnedImage(item)
        }
    }

    private func deleteOwnedImage(_ item: ClipboardItem) {
        guard item.kind == .image, let path = item.imagePath, ownsImage(at: path) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    private func ownsImage(at path: String) -> Bool {
        guard let imagesDirectoryURL else { return false }
        let dir = imagesDirectoryURL.standardizedFileURL.path
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        return standardized.hasPrefix(dir + "/")
    }

    // MARK: - Disk persistence

    private func loadJSON(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([ClipboardItem].self, from: data)
            items = Array(decoded.prefix(maxItems))
            enforceImageCap()
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
/// content is always on the pasteboard so ⌘V manually still works.
enum ClipboardPaster {
    static func pasteCommandV(after delay: TimeInterval = 0.15) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // Never prompt here — `pasteClipboardItem` already asked once.
            let trusted = FocusRestorer.isTrusted()
            if !trusted {
                FocusRestorer.log(
                    "clipboard: posting ⌘V without AX trust (may be dropped; content is on pasteboard)"
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
