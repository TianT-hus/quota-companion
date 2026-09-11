import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public struct CharacterLabelRect: Codable, Equatable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x=x; self.y=y; self.width=width; self.height=height }
}
public struct CharacterManifest: Codable, Equatable, Sendable {
    public var version: Int
    public var name: String
    public var label: CharacterLabelRect
    public var fillTop: Int
    public var fillBottom: Int
    public init(name: String, label: CharacterLabelRect, fillTop: Int, fillBottom: Int) {
        version = 1; self.name=name; self.label=label; self.fillTop=fillTop; self.fillBottom=fillBottom
    }
    public func validate() throws {
        let r = label
        guard [1, 2].contains(version), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 40,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              [r.x,r.y,r.width,r.height].allSatisfy({ $0.isFinite }), r.x >= 0, r.y >= 0,
              r.width >= 28, r.height >= 22, r.x+r.width <= 72, r.y+r.height <= 80,
              fillTop >= 0, fillBottom <= 80, fillBottom > fillTop else { throw CharacterPackageError.invalidManifest }
    }
    public var pixelsPerPoint: Int { version == 2 ? 4 : 1 }
}
public enum CharacterPackageError: Error, Sendable {
    case invalidManifest, unsafeFile, invalidImage, invalidLayers
    public func message(chinese: Bool) -> String {
        switch self {
        case .invalidManifest: chinese ? "角色说明文件无效，请检查版本、名称及数字位置。" : "Invalid character manifest, name or label position."
        case .unsafeFile: chinese ? "请选择完整本地角色包；不支持符号链接或超限文件。" : "Choose a complete local character package. Links and oversized files are not supported."
        case .invalidImage: chinese ? "角色包需要三张同尺寸透明 PNG：v1 为 72×80，v2 为 288×320。" : "Three matching transparent PNGs required: v1 72×80, v2 288×320."
        case .invalidLayers: chinese ? "角色填充或细节层越界，或缺少透明轮廓。当前形象未更改。" : "Invalid fill/detail layers or missing transparency. Current character is unchanged."
        }
    }
}
public struct PreparedCharacter: Sendable {
    public let manifest: CharacterManifest
    public let base: Data
    public let fillMask: Data
    public let details: Data
}
public struct CharacterPackageStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func load(id: String) throws -> PreparedCharacter {
        guard UUID(uuidString: id) != nil else { throw CharacterPackageError.unsafeFile }
        return try Self.prepare(folder: directory.appendingPathComponent(id))
    }
    public func identifiers() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { UUID(uuidString: $0) != nil }.sorted()
    }
    public func save(_ character: PreparedCharacter) throws -> String {
        let id = UUID().uuidString
        let folder = directory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try JSONEncoder().encode(character.manifest).write(to: folder.appendingPathComponent("character.json"), options: .atomic)
            try character.base.write(to: folder.appendingPathComponent("base.png"), options: .atomic)
            try character.fillMask.write(to: folder.appendingPathComponent("fill-mask.png"), options: .atomic)
            try character.details.write(to: folder.appendingPathComponent("details.png"), options: .atomic)
            return id
        } catch {
            // Only the just-created UUID destination is discarded; imported sources are never modified.
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
    public static func prepare(folder: URL) throws -> PreparedCharacter {
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw CharacterPackageError.unsafeFile }
        func read(_ name: String, limit: Int) throws -> Data {
            let url = folder.appendingPathComponent(name)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size <= limit else { throw CharacterPackageError.unsafeFile }
            let data = try Data(contentsOf: url)
            guard data.count <= limit else { throw CharacterPackageError.unsafeFile }
            return data
        }
        let manifest: CharacterManifest
        do { manifest = try JSONDecoder().decode(CharacterManifest.self, from: read("character.json", limit: 16_384)) }
        catch { throw CharacterPackageError.invalidManifest }
        try manifest.validate()
        let density = manifest.pixelsPerPoint, width = 72*density, height = 80*density
        let base = try decode(read("base.png", limit: 262_144), width: width, height: height)
        let mask = try decode(read("fill-mask.png", limit: 262_144), width: width, height: height)
        let details = try decode(read("details.png", limit: 262_144), width: width, height: height)
        var transparent = false, filled = false, protected = false
        for y in 0..<height { for x in 0..<width {
            let i = (y*width+x)*4, a = base.pixels[i+3], m = mask.pixels[i+3], d = details.pixels[i+3]
            transparent = transparent || a == 0; filled = filled || m > 0; protected = protected || d > 0
            guard m <= a, d <= a, m == 0 || (y >= manifest.fillTop*density && y < manifest.fillBottom*density) else { throw CharacterPackageError.invalidLayers }
        } }
        guard transparent, filled, protected else { throw CharacterPackageError.invalidLayers }
        return PreparedCharacter(manifest: manifest, base: base.png, fillMask: mask.png, details: details.png)
    }
    private static func decode(_ data: Data, width: Int, height: Int) throws -> (png: Data, pixels: [UInt8]) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              props[kCGImagePropertyPixelWidth] as? Int == width, props[kCGImagePropertyPixelHeight] as? Int == height,
              (props[kCGImagePropertyOrientation] as? Int ?? 1) == 1,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              [.premultipliedFirst, .premultipliedLast, .first, .last].contains(image.alphaInfo) else { throw CharacterPackageError.invalidImage }
        var pixels = [UInt8](repeating: 0, count: width*height*4)
        let normalized: CGImage = try pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width*4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CharacterPackageError.invalidImage }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let result = context.makeImage() else { throw CharacterPackageError.invalidImage }; return result
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw CharacterPackageError.invalidImage }
        CGImageDestinationAddImage(destination, normalized, nil)
        guard CGImageDestinationFinalize(destination) else { throw CharacterPackageError.invalidImage }
        return (output as Data, pixels)
    }
}
