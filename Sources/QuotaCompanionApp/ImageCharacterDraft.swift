import AppKit
import ImageIO
import UniformTypeIdentifiers
import QuotaCore

struct CharacterBrushStroke: Equatable {
    var points: [CGPoint]
    var radius: CGFloat
    var erasing: Bool
}

@MainActor final class ImageCharacterDraft: ObservableObject {
    @Published var image: CGImage?
    @Published var zoom: Double = 1
    @Published var offset = CGPoint.zero
    @Published var label = CharacterLabelRect(x: 8, y: 44, width: 56, height: 24)
    @Published var tintEnabled = false
    @Published var strokes: [CharacterBrushStroke] = []
    @Published var name = ""
    private var history: [[CharacterBrushStroke]] = []
    private(set) var opaque = false
    static let size = CGSize(width: 288, height: 320)
    func load(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let attrs = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard attrs.isRegularFile == true, (attrs.fileSize ?? Int.max) <= 20_000_000,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) == 1,
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 32_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2048, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        else { throw ImageCharacterError.image }
        let pixels = try Self.raster { $0.draw(image, in: CGRect(origin: .zero, size: Self.size)) }
        self.image = image; zoom = 1; offset = .zero; strokes = []; history = []
        opaque = stride(from: 3, to: pixels.count, by: 4).allSatisfy { pixels[$0] == 255 }
    }
    func commitStroke(_ stroke: CharacterBrushStroke) {
        guard !stroke.points.isEmpty else { return }
        history.append(strokes); if history.count > 30 { history.removeFirst() }
        strokes.append(stroke)
    }
    var canUndo: Bool { !history.isEmpty }
    func undo() { if let previous = history.popLast() { strokes = previous } }
    func clearMask() { history.append(strokes); strokes = [] }
    func prepared() throws -> PreparedCharacter {
        guard let image else { throw ImageCharacterError.image }
        let scale = min(288 / Double(image.width), 320 / Double(image.height)) * zoom
        let w = Double(image.width)*scale, h = Double(image.height)*scale
        let base = try Self.raster { ctx in
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: (288-w)/2 + offset.x, y: (320-h)/2 - offset.y, width: w, height: h))
        }
        guard stride(from: 3, to: base.count, by: 4).contains(where: { base[$0] > 0 }) else { throw ImageCharacterError.empty }
        var mask = try Self.raster { ctx in
            guard tintEnabled else { return }
            ctx.setLineCap(.round); ctx.setLineJoin(.round)
            for stroke in strokes {
                ctx.setBlendMode(stroke.erasing ? .clear : .normal)
                ctx.setStrokeColor(NSColor.white.cgColor); ctx.setFillColor(NSColor.white.cgColor)
                ctx.setLineWidth(stroke.radius*2)
                guard let first = stroke.points.first else { continue }
                if stroke.points.count == 1 { ctx.fillEllipse(in: CGRect(x: first.x-stroke.radius, y: 320-first.y-stroke.radius, width: stroke.radius*2, height: stroke.radius*2)) }
                else {
                    ctx.beginPath(); ctx.move(to: CGPoint(x: first.x, y: 320-first.y))
                    for point in stroke.points.dropFirst() { ctx.addLine(to: CGPoint(x: point.x, y: 320-point.y)) }
                    ctx.strokePath()
                }
            }
        }
        for i in stride(from: 0, to: mask.count, by: 4) {
            let a = min(mask[i+3], base[i+3]); mask[i] = a; mask[i+1] = a; mask[i+2] = a; mask[i+3] = a
        }
        var manifest = CharacterManifest(name: name.isEmpty ? "New companion" : name, label: label, fillTop: 0, fillBottom: 80)
        manifest.version = 4; try manifest.validate()
        return PreparedCharacter(manifest: manifest, base: try Self.png(base), fillMask: try Self.png(mask), details: try Self.png([UInt8](repeating: 0, count: 288*320*4)))
    }
    static func raster(_ draw: (CGContext) -> Void) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 288*320*4)
        try bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 288, height: 320, bitsPerComponent: 8, bytesPerRow: 288*4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ImageCharacterError.image }
            draw(context)
        }
        return bytes
    }
    static func png(_ bytes: [UInt8]) throws -> Data {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData), let image = CGImage(width:288,height:320,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:1152,space:CGColorSpace(name: CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw ImageCharacterError.image }
        return data
    }
}
enum ImageCharacterError: LocalizedError {
    case image, empty
    var errorDescription: String? {
        switch self {
        case .empty: "画布中没有可见形象，请把图片移回画布。 / No visible image. Move it back onto the canvas."
        case .image: "请选择单张 PNG（不超过 20 MB、8192 像素边长或 3200 万像素）。不支持 GIF 或动画 PNG。 / Choose one PNG, up to 20 MB, 8192 pixels per edge and 32 megapixels."
        }
    }
}
