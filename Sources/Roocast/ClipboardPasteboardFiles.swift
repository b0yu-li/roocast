import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Durable file URLs on the pasteboard (Tinycast-style).
///
/// Finder puts a *file-type icon* as `.png`/`.tiff` beside `public.file-url`.
/// Reading those bytes stores a 1024² placeholder, not the real image — so
/// capture must prefer the file URL and load pixels from disk.
enum ClipboardPasteboardFiles {
    private static let legacyFilenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    /// Roots that stage temp exports — reject so inline content can win instead.
    static var volatileRoots: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/tmp",
            "/var/tmp",
            "/var/folders",
            "\(home)/Library/Caches",
        ]
    }

    /// First durable image file URL, if any.
    static func firstDurableImageFileURL(on pasteboard: NSPasteboard) -> URL? {
        durableFileURLs(on: pasteboard).first { isImageFile($0) }
    }

    /// True when the board names any durable file (image or not).
    static func hasDurableFileURL(on pasteboard: NSPasteboard) -> Bool {
        !durableFileURLs(on: pasteboard).isEmpty
    }

    static func durableFileURLs(on pasteboard: NSPasteboard, limit: Int = 32) -> [URL] {
        var matches: [URL] = []
        var sawFileURL = false
        for item in pasteboard.pasteboardItems ?? [] {
            guard let url = url(from: item) else { continue }
            sawFileURL = true
            guard isDurable(url) else { continue }
            matches.append(url)
            if matches.count >= limit { return matches }
        }
        guard !sawFileURL,
              let paths = pasteboard.propertyList(forType: legacyFilenames) as? [String]
        else { return matches }
        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard isDurable(url) else { continue }
            matches.append(url)
            if matches.count >= limit { return matches }
        }
        return matches
    }

    static func isImageFile(_ url: URL) -> Bool {
        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
            return true
        }
        // Extension-less / odd names: sniff via ImageIO.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let uti = CGImageSourceGetType(source) as String?,
              let type = UTType(uti)
        else { return false }
        return type.conforms(to: .image)
    }

    /// PNG bytes for an on-disk image (pass-through for `.png`, re-encode otherwise).
    static func pngData(fromFile url: URL) -> Data? {
        if url.pathExtension.lowercased() == "png",
           let data = try? Data(contentsOf: url, options: .mappedIfSafe),
           !data.isEmpty
        {
            return data
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let destData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                destData, UTType.png.identifier as CFString, 1, nil
              )
        else { return nil }
        CGImageDestinationAddImageFromSource(destination, source, 0, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return destData as Data
    }

    private static func isDurable(_ url: URL) -> Bool {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { return false }
        var path = url.resolvingSymlinksInPath().path
        if path.hasPrefix("/private/") {
            path.removeFirst("/private".count)
        }
        return !volatileRoots.contains { path.hasPrefix($0) }
    }

    private static func url(from item: NSPasteboardItem) -> URL? {
        if let data = item.data(forType: .fileURL),
           let url = URL(dataRepresentation: data, relativeTo: nil),
           url.isFileURL
        {
            return url
        }
        guard let string = item.string(forType: .fileURL),
              let url = URL(string: string),
              url.isFileURL
        else { return nil }
        return url
    }
}
