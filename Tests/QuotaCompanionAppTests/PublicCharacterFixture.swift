import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import QuotaCore

/// Original geometric layers generated per test; no personal character files.
enum PublicCharacterFixture {
    static func make() throws -> URL {
        let folder = URL.temporaryDirectory.appendingPathComponent("public-character-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            // Intentionally longer than the editor limit, exercising legacy-name support.
            var manifest = CharacterManifest(name: "公开测试合成角色名称", label: .init(x: 12, y: 40, width: 48, height: 24), fillTop: 32, fillBottom: 77)
            manifest.version = 3
            manifest.animation = .init(durationsMilliseconds: Array(repeating: 375, count: 8))
            try manifest.validate()
            try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("character.json"))
            for frame in -1..<8 {
                let prefix = frame < 0 ? "" : "frame-\(frame)-"
                for layer in ["base", "fill-mask", "details"] {
                    var pixels = [UInt8](repeating: 0, count: 288 * 320 * 4)
                    let offset = max(frame, 0) % 3 * 4
                    for y in 16..<308 { for x in (40 + offset)..<(240 + offset) {
                        let include = layer == "base" || (layer == "details" ? y < 128 : y >= 128)
                        if include {
                            let i = (y * 288 + x) * 4
                            pixels[i] = 90; pixels[i + 1] = 180; pixels[i + 2] = 220; pixels[i + 3] = 255
                        }
                    } }
                    guard let provider = CGDataProvider(data: Data(pixels) as CFData),
                          let image = CGImage(width: 288, height: 320, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 288 * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
                          let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent(prefix + layer + ".png") as CFURL, UTType.png.identifier as CFString, 1, nil)
                    else { throw CocoaError(.fileWriteUnknown) }
                    CGImageDestinationAddImage(destination, image, nil)
                    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
                }
            }
            _ = try CharacterPackageStore.prepare(folder: folder)
            return folder
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }
}
