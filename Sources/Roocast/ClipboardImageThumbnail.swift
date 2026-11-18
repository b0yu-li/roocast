import AppKit
import ImageIO

/// ImageIO downsampled tiles for clipboard rows / preview.
///
/// No out-of-process helper and no on-disk derivatives for v0.11 — decode a
/// bounded max-pixel thumbnail in-process and cache by path + pixel size.
enum ClipboardImageThumbnail {
    private static let cache = ClipboardThumbnailCache(
        rowBytes: 8 * 1024 * 1024,
        previewBytes: 8 * 1024 * 1024
    )

    static let rowMaxPixel: CGFloat = 64
    static let previewMaxPixel: CGFloat = 900

    /// Frees large preview bitmaps on panel dismiss; row tiles stay warm.
    static func purgePreviews() {
        cache.purgePreviews()
    }

    static func cached(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        cache.cached(url, maxPixel: maxPixel)
    }

    static func load(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        if let cached = cached(url, maxPixel: maxPixel) { return cached }
        return decode(url, cachingAs: url, maxPixel: maxPixel)
    }

    static func loadAsync(_ url: URL, maxPixel: CGFloat) async -> NSImage? {
        if let cached = cached(url, maxPixel: maxPixel) { return cached }
        guard !Task.isCancelled else { return nil }
        return await Task.detached(priority: .userInitiated) {
            decode(url, cachingAs: url, maxPixel: maxPixel)
        }.value
    }

    /// Pixel dimensions from metadata — no full decode.
    static func pixelSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }

    private static func decode(_ file: URL, cachingAs url: URL, maxPixel: CGFloat) -> NSImage? {
        guard let cgImage = downsample(file, maxPixel: maxPixel) else { return nil }
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        cache.store(
            image,
            for: url,
            maxPixel: maxPixel,
            cost: cgImage.bytesPerRow * cgImage.height
        )
        return image
    }

    private static func downsample(_ url: URL, maxPixel: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// Two `NSCache` tiers — row tiles vs preview bitmaps — costed by real bitmap bytes.
final class ClipboardThumbnailCache: @unchecked Sendable {
    private final class Cache: NSCache<NSString, NSImage> {}

    private static let rowThreshold: CGFloat = 128

    private let rows = Cache()
    private let previews = Cache()

    init(rowBytes: Int, previewBytes: Int) {
        rows.totalCostLimit = rowBytes
        previews.totalCostLimit = previewBytes
    }

    private func tier(_ maxPixel: CGFloat) -> Cache {
        maxPixel <= Self.rowThreshold ? rows : previews
    }

    private func key(_ url: URL, _ maxPixel: CGFloat) -> NSString {
        "\(url.path)#\(Int(maxPixel))" as NSString
    }

    func cached(_ url: URL, maxPixel: CGFloat) -> NSImage? {
        tier(maxPixel).object(forKey: key(url, maxPixel))
    }

    func store(_ image: NSImage, for url: URL, maxPixel: CGFloat, cost: Int) {
        tier(maxPixel).setObject(image, forKey: key(url, maxPixel), cost: cost)
    }

    func purgePreviews() {
        previews.removeAllObjects()
    }
}
