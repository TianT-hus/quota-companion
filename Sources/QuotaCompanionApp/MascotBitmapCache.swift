import CoreGraphics
import Foundation
import ImageIO

/// Keep decoding off the main thread and reuse the decoded bitmap across panel
/// presentations. File metadata invalidates a custom pet replaced at the same path.
actor MascotBitmapCache {
    static let shared = MascotBitmapCache()
    private struct Entry {
        let modified: Date?
        let size: Int?
        let bitmap: CGImage
    }
    private var entries: [URL: Entry] = [:]

    func bitmap(at url: URL) -> CGImage? {
        // URL.resourceValues can cache attributes on the URL itself. Read fresh
        // filesystem attributes so same-path pet replacement really invalidates.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let modified = attributes[.modificationDate] as? Date
        let size = (attributes[.size] as? NSNumber)?.intValue
        if let entry = entries[url], entry.modified == modified, entry.size == size {
            return entry.bitmap
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let bitmap = context.makeImage() else { return nil }
        if entries.count >= 3 { entries.removeAll(keepingCapacity: true) }
        entries[url] = Entry(modified: modified, size: size, bitmap: bitmap)
        return bitmap
    }
}
