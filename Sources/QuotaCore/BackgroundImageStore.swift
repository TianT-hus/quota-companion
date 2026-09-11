import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum BackgroundImportError: Error, Equatable, Sendable {
    case unreadable, unsupported, animated, tooLarge, tooManyPixels, decodeFailed, invalidResourceName
    public func message(chinese: Bool) -> String {
        switch self {
        case .unreadable: return chinese ? "无法读取图片，请重新选择本地文件。" : "Could not read the image. Select a local file."
        case .unsupported: return chinese ? "请选择 PNG、JPEG、WebP 或 HEIC 图片。" : "Choose a PNG, JPEG, WebP or HEIC image."
        case .animated: return chinese ? "背景暂不支持动态图，请选择静态图片。" : "Animated backgrounds are not supported. Choose a still image."
        case .tooLarge: return chinese ? "图片超过 32MB，请选择较小的文件。" : "The image exceeds 32MB. Choose a smaller file."
        case .tooManyPixels: return chinese ? "图片超过 6400 万像素，请先缩小图片。" : "The image exceeds 64 megapixels. Resize it first."
        case .decodeFailed: return chinese ? "图片无法解码，当前背景未更改。" : "Could not decode the image. The current background is unchanged."
        case .invalidResourceName: return chinese ? "保存的背景不可用，请重新选择图片。" : "The saved background is unavailable. Select an image again."
        }
    }
}

public struct PreparedBackground: Sendable {
    public let png: Data
    public let width: Int
    public let height: Int
    public let analysis: BackgroundAnalysis
    public let appearances: BackgroundAppearances
}

public struct BackgroundImageStore: Sendable {
    public let directory: URL
    public static let maximumBytes = 32 * 1024 * 1024
    public static let maximumPixels = 64_000_000
    public static let maximumDimension = 2048

    public init(directory: URL) { self.directory = directory }

    public func resourceURL(name: String) throws -> URL {
        guard name == URL(fileURLWithPath: name).lastPathComponent, name.hasSuffix(".png"),
              !name.contains("/"), !name.contains("\\"), name.count < 100 else { throw BackgroundImportError.invalidResourceName }
        return directory.appendingPathComponent(name)
    }

    public func save(_ prepared: PreparedBackground) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".png"
        try prepared.png.write(to: resourceURL(name: name), options: .atomic)
        return name
    }

    public func load(name: String) throws -> PreparedBackground { try Self.prepare(url: resourceURL(name: name)) }

    public static func prepare(url: URL) throws -> PreparedBackground {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
              values.isRegularFile == true, let size = values.fileSize else { throw BackgroundImportError.unreadable }
        guard size <= maximumBytes else { throw BackgroundImportError.tooLarge }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { throw BackgroundImportError.unreadable }
        return try prepare(data: data)
    }

    public static func prepare(data: Data) throws -> PreparedBackground {
        guard data.count <= maximumBytes else { throw BackgroundImportError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String? else { throw BackgroundImportError.decodeFailed }
        let supported = [UTType.png.identifier, UTType.jpeg.identifier, UTType.webP.identifier, UTType.heic.identifier, UTType.heif.identifier]
        guard supported.contains(type) else { throw BackgroundImportError.unsupported }
        guard CGImageSourceGetCount(source) == 1 else { throw BackgroundImportError.animated }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width.isFinite, height.isFinite, width > 0, height > 0 else { throw BackgroundImportError.decodeFailed }
        try validateDimensions(width: width, height: height)
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
            kCGImageSourceShouldCacheImmediately: true]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: thumbnail.width, height: thumbnail.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw BackgroundImportError.decodeFailed
        }
        context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        guard let normalized = context.makeImage() else { throw BackgroundImportError.decodeFailed }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw BackgroundImportError.decodeFailed
        }
        // A new bitmap plus no source properties strips EXIF/GPS and normalizes orientation.
        CGImageDestinationAddImage(destination, normalized, nil)
        guard CGImageDestinationFinalize(destination) else { throw BackgroundImportError.decodeFailed }
        let analysis = try analyze(normalized)
        return PreparedBackground(png: output as Data, width: normalized.width, height: normalized.height,
                                  analysis: analysis, appearances: BackgroundAppearances(analysis: analysis))
    }

    static func validateDimensions(width: Double, height: Double) throws {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { throw BackgroundImportError.decodeFailed }
        guard width * height <= Double(maximumPixels) else { throw BackgroundImportError.tooManyPixels }
    }

    /// Analyze all pixels in both visible crops once on Apply. Per-channel minima form
    /// a conservative bound even for colored/high-frequency or transparent content.
    public static func analyzedComposition(png: Data, composition: BackgroundComposition) throws -> BackgroundComposition {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw BackgroundImportError.decodeFailed }
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 0, count: w*h*4)
        var minima = [255,255,255]
        try pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { throw BackgroundImportError.decodeFailed }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            for height in [56.0, 80.0] {
                let rect = composition.imageRect(image: CGSize(width: w, height: h), viewport: CGSize(width: 200, height: height))
                let left = max(0, Int(floor(-rect.minX / rect.width * Double(w))))
                let right = min(w, Int(ceil((200-rect.minX)/rect.width * Double(w))))
                let top = max(0, Int(floor(-rect.minY / rect.height * Double(h))))
                let bottom = min(h, Int(ceil((height-rect.minY)/rect.height * Double(h))))
                for y in top..<bottom {
                    for x in left..<right {
                        let offset = (y*w+x)*4
                        for channel in 0..<3 { minima[channel] = min(minima[channel], Int(bytes[offset+channel])) }
                    }
                }
            }
        }
        var result = composition
        result.darkestPixelHex = RGBColor(Double(minima[0])/255, Double(minima[1])/255, Double(minima[2])/255).hexString
        return result
    }

    private static func analyze(_ image: CGImage) throws -> BackgroundAnalysis {
        let side = 64
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let values: [Double] = try pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw BackgroundImportError.decodeFailed
            }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return stride(from: 0, to: bytes.count, by: 4).map { offset in
                let alpha = Double(bytes[offset + 3]) / 255
                return RGBColor(Double(bytes[offset])/255 + 1-alpha, Double(bytes[offset+1])/255 + 1-alpha,
                                Double(bytes[offset+2])/255 + 1-alpha).luminance
            }
        }
        var difference = 0.0
        for y in 0..<side {
            for x in 1..<side { difference += abs(values[y * side + x] - values[y * side + x - 1]) }
        }
        return BackgroundAnalysis(minimum: values.min()!, maximum: values.max()!,
                                  mean: values.reduce(0, +) / Double(values.count), detail: difference / Double(side * (side-1)))
    }
}
