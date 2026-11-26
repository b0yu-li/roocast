import Foundation

/// Pure rules for clipboard image capture + paste (Tinycast file-pointer style).
///
/// Durable Finder image files are referenced where they lie — never copied into
/// Application Support. Paste publishes a file-URL pointer, not PNG bytes.
enum ClipboardImagePolicy {
    /// Bare inline PNG/TIFF (no durable file URL) must own a blob under `images/`.
    /// Finder / path-based images stay as pointers.
    nonisolated static func storesOwnedBlob(hasDurableImageFileURL: Bool) -> Bool {
        !hasDurableImageFileURL
    }

    /// Pasteboard write for image rows: never publish `.png` / `.tiff` bytes.
    nonisolated static let pastesImageBytes = false
    nonisolated static let pastesFileURL = true
    /// Terminals ignore `public.file-url` and paste the path as text.
    nonisolated static let pastesPathAsString = true

    /// Soft-cap / delete only Roocast-owned blobs — never a user's original file.
    nonisolated static func countsTowardImageCap(isOwnedBlob: Bool) -> Bool {
        isOwnedBlob
    }

    /// List label: filename for a path pointer; generic "Image" for owned blobs
    /// (UUID.png under `images/` is not a useful label).
    nonisolated static func previewLabel(displayName: String?, isOwnedBlob: Bool) -> String {
        if isOwnedBlob { return "Image" }
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Image" : name
    }
}
