import AppKit
import ImageIO
import QuotaCore
import SwiftUI

/// One-time sprite import: chroma key -> 72×80 RGBA -> immutable shading/face layers.
/// All subsequent drawing uses nearest-neighbor sampling; no per-frame image work.
@MainActor
final class FantasyCatTexture {
    static let shared = FantasyCatTexture()
    static let width = 72, height = 80
    nonisolated static let top = 2, bottom = 76
    let body: CGImage
    let details: CGImage
    let eyeCover: CGImage
    let eyelids: CGImage
    let colors: [CGImage]
    let coloredEyeCovers: [CGImage]
    let alpha: [UInt8]
    let importedSuccessfully: Bool
    private var sourcePixels: [UInt8] = []
    private var coverPixels: [UInt8] = []
    private var customCache: [String: (CGImage, CGImage)] = [:]
    private var cacheOrder: [String] = []
    func customImages(_ color: QuotaCore.RGBColor) -> (CGImage, CGImage) {
        let key = color.hexString
        if let hit = customCache[key] { return hit }
        let tint = (color.r * 255, color.g * 255, color.b * 255)
        let result = (Self.image(Self.tinted(sourcePixels, color: tint)), Self.image(Self.tinted(coverPixels, color: tint)))
        if cacheOrder.count >= 16 { customCache.removeValue(forKey: cacheOrder.removeFirst()) }
        cacheOrder.append(key); customCache[key] = result
        return result
    }

    nonisolated static func fillRows(_ remaining: Double?) -> Int {
        guard let remaining, remaining.isFinite else { return 0 }
        return Int((Double(bottom - top) * min(100, max(0, remaining)) / 100).rounded())
    }
    nonisolated static func colorIndex(_ remaining: Double?) -> Int {
        guard let remaining else { return 0 }
        return remaining <= 5 ? 3 : remaining <= 15 ? 2 : remaining <= 30 ? 1 : 0
    }
    init() {
        var url = Bundle.main.url(forResource: "fantasy-cat-base", withExtension: "png")
        #if DEBUG
        // SwiftPM tests load checked-in assets. Release apps only use bundled assets,
        // avoiding SwiftPM's generated absolute build-directory fallback in the binary.
        if url == nil {
            url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("Resources/fantasy-cat-base.png")
        }
        #endif
        let source = url.flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
            .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        importedSuccessfully = source != nil
        var pixels = [UInt8](repeating: 0, count: 72 * 80 * 4)
        let flags = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        if let source, let context = CGContext(data: &pixels, width: 72, height: 80, bitsPerComponent: 8,
                                                bytesPerRow: 72 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: flags) {
            context.interpolationQuality = .none
            context.setShouldAntialias(false)
            context.draw(source, in: CGRect(x: 0, y: 0, width: 72, height: 80))
        }
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Int(pixels[i]), g = Int(pixels[i+1]), b = Int(pixels[i+2])
            let keyed = r > 70 && b > 70 && r-g > 55 && b-g > 55
            if keyed || pixels[i + 3] < 128 {
                for c in 0..<4 { pixels[i + c] = 0 }
            } else { pixels[i + 3] = 255 }
        }
        alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
        var detailPixels = [UInt8](repeating: 0, count: pixels.count)
        var covers = detailPixels, lids = detailPixels
        for y in 0..<80 {
            for x in 0..<72 {
                let i = (y * 72 + x) * 4
                guard pixels[i + 3] > 0 else { continue }
                let r = Double(pixels[i]), g = Double(pixels[i+1]), b = Double(pixels[i+2])
                var edge = false
                let neighbors: [(Int,Int)] = [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]
                for neighbor in neighbors {
                    let nx = neighbor.0, ny = neighbor.1
                    if nx < 0 || nx >= 72 || ny < 0 || ny >= 80 { edge = true }
                    else if pixels[(ny * 72 + nx) * 4 + 3] == 0 { edge = true }
                }
                let light = (0.2126*r + 0.7152*g + 0.0722*b) / 255
                let facialColor = y < 34 && max(r,g,b) - min(r,g,b) > 55
                if edge || light < 0.22 || facialColor {
                    for c in 0..<4 { detailPixels[i+c] = pixels[i+c] }
                }
                // Tiny elliptical covers follow the two actual eyes, not a rectangular plate.
                for (cx,cy) in [(19.0,23.0),(33.0,24.0)] {
                    let dx = (Double(x)-cx)/4.0, dy = (Double(y)-cy)/4.7
                    if dx*dx + dy*dy <= 1 {
                        let sample = (max(0,y-9) * 72 + x) * 4
                        for c in 0..<3 { covers[i+c] = pixels[sample+c] }
                        covers[i+3] = 255
                    }
                    if y == Int(cy), abs(Double(x)-cx) <= 3 {
                        lids[i] = 25; lids[i+1] = 49; lids[i+2] = 66; lids[i+3] = 255
                    }
                }
            }
        }
        body = Self.image(pixels); details = Self.image(detailPixels)
        eyeCover = Self.image(covers); eyelids = Self.image(lids)
        let tints: [(Double,Double,Double)] = [(114,213,232),(255,182,72),(255,138,61),(255,94,87),(100,205,179),(180,154,222)]
        colors = tints.map { Self.image(Self.tinted(pixels, color: $0)) }
        coloredEyeCovers = tints.map { Self.image(Self.tinted(covers, color: $0)) }
        sourcePixels = pixels; coverPixels = covers
    }
    private static func tinted(_ pixels: [UInt8], color: (Double,Double,Double)) -> [UInt8] {
        var result = pixels
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i+3] > 0 {
            let l = (0.2126*Double(pixels[i]) + 0.7152*Double(pixels[i+1]) + 0.0722*Double(pixels[i+2])) / 255
            for (channel, target) in [color.0,color.1,color.2].enumerated() {
                let value = l <= 0.75 ? target * l / 0.85 : target + (255-target) * (l-0.75)/0.25 * 0.65
                result[i+channel] = UInt8(min(255,max(0,value.rounded())))
            }
        }
        return result
    }
    private static func image(_ pixels: [UInt8]) -> CGImage {
        let data = Data(pixels) as CFData
        return CGImage(width: 72, height: 80, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 288,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}

struct PixelCatShape: Shape {
    func path(in rect: CGRect) -> Path {
        // The native pointer controller retains its 72×80 target. SwiftUI gets a
        // conservative rounded hit area, independent of source-image file dimensions.
        Path(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: 14)
    }
}

struct CatFillMask: Shape {
    let remaining: Double?
    func path(in rect: CGRect) -> Path {
        let rows = CGFloat(FantasyCatTexture.fillRows(remaining))
        return Path(CGRect(x: 0, y: (76-rows) * rect.height/80, width: rect.width, height: rows * rect.height/80))
    }
}
