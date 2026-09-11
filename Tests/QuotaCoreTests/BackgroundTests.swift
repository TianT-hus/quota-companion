import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import QuotaCore

struct BackgroundTests {
    private func image(width: Int = 80, height: Int = 40, hex: UInt = 0xFF0099, alpha: CGFloat = 1) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let color = RGBColor(hex: hex)
        context.setFillColor(CGColor(red: color.r, green: color.g, blue: color.b, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }
    private func encode(_ image: CGImage, type: UTType = .png, properties: [CFString: Any] = [:]) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func allAppearanceVariantsMeetContrastEvenForExtremeBackgrounds() {
        let inputs: [BackgroundAnalysis?] = [nil,
            .init(minimum: 0, maximum: 0, mean: 0, detail: 0),
            .init(minimum: 1, maximum: 1, mean: 1, detail: 0),
            .init(minimum: 0, maximum: 1, mean: 0.5, detail: 0.9),
            .init(minimum: 0.1, maximum: 0.8, mean: 0.4, detail: 0.2)]
        for input in inputs {
            let styles = BackgroundAppearances(analysis: input)
            for dark in [false, true] { for high in [false, true] { for reduced in [false, true] {
                let style = styles[.init(dark: dark, highContrast: high, reduceTransparency: reduced)]
                #expect(style.imageOpacity <= 0.25)
                #expect(style.minimumTextContrast >= (high ? 7 : 4.5))
                for remaining in [0.0, 5, 15, 30, 83, 100] {
                    #expect(style.progressColor(remaining: remaining).contrast(with: style.track) >= 3)
                }
            } } }
        }
    }

    @Test func importNormalizesOrientationAndStripsPhotoMetadata() throws {
        let encoded = try encode(image(), type: .jpeg, properties: [kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2001:01:01 12:34:56",
                                             kCGImagePropertyExifUserComment: "private test caption"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.34, kCGImagePropertyGPSLongitude: 56.78]])
        let prepared = try BackgroundImageStore.prepare(data: encoded)
        #expect(prepared.width == 40 && prepared.height == 80)
        let source = try #require(CGImageSourceCreateWithData(prepared.png as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        // ImageIO may synthesize color-space/dimension EXIF for the new PNG.
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] == nil)
        #expect(exif[kCGImagePropertyExifUserComment] == nil)
        #expect(exif.keys.allSatisfy { [kCGImagePropertyExifColorSpace, kCGImagePropertyExifPixelXDimension,
                                      kCGImagePropertyExifPixelYDimension].contains($0) })
        #expect(properties[kCGImagePropertyOrientation] == nil || (properties[kCGImagePropertyOrientation] as? Int) == 1)
    }

    @Test func heicStillIsDecodedToStandalonePNG() throws {
        let prepared = try BackgroundImageStore.prepare(data: encode(image(), type: .heic))
        #expect(prepared.width == 80 && prepared.height == 40)
        let source = try #require(CGImageSourceCreateWithData(prepared.png as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
    }

    @Test func wideTallAndTransparentImagesAreBounded() throws {
        for (width, height) in [(4096, 64), (64, 4096), (100, 100)] {
            let prepared = try BackgroundImageStore.prepare(data: encode(image(width: width, height: height, alpha: 0.3)))
            #expect(max(prepared.width, prepared.height) <= 2048)
            #expect(abs(Double(prepared.width) / Double(prepared.height) - Double(width) / Double(height)) < 0.01)
        }
        for hex: UInt in [0x000000, 0xFFFFFF, 0xFF0000, 0x00FF00, 0x0000FF] {
            let prepared = try BackgroundImageStore.prepare(data: encode(image(hex: hex)))
            #expect(prepared.analysis.minimum >= 0 && prepared.analysis.maximum <= 1)
        }
    }

    @Test func rejectsBrokenUnsupportedAndOversizedInputs() throws {
        #expect(throws: BackgroundImportError.decodeFailed) { try BackgroundImageStore.prepare(data: Data("not an image".utf8)) }
        #expect(throws: BackgroundImportError.tooLarge) {
            try BackgroundImageStore.prepare(data: Data(repeating: 0, count: BackgroundImageStore.maximumBytes + 1))
        }
        let tiff = try encode(image(), type: .tiff)
        #expect(throws: BackgroundImportError.unsupported) { try BackgroundImageStore.prepare(data: tiff) }
    }

    @Test func resourceStorageNeverOverwritesSourceAndRejectsTraversal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("quota-background-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = BackgroundImageStore(directory: directory)
        let prepared = try BackgroundImageStore.prepare(data: encode(image()))
        let first = try storage.save(prepared), second = try storage.save(prepared)
        #expect(first != second)
        #expect(try storage.load(name: first).width == prepared.width)
        #expect(FileManager.default.fileExists(atPath: try storage.resourceURL(name: first).path))
        #expect(throws: BackgroundImportError.invalidResourceName) { try storage.resourceURL(name: "../outside.png") }
        #expect(throws: BackgroundImportError.invalidResourceName) { try storage.resourceURL(name: "/tmp/outside.png") }
    }

    @Test func rejectsPixelBombBeforeDecodingAndRejectsAnimation() throws {
        var png = try encode(image())
        func bytes(_ value: UInt32) -> [UInt8] {
            [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]
        }
        // Only the IHDR declares a huge image; this never allocates a huge bitmap.
        png.replaceSubrange(16..<24, with: bytes(8001) + bytes(8000))
        var crc: UInt32 = 0xFFFFFFFF
        for byte in png[12..<29] {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xEDB88320 : 0) }
        }
        png.replaceSubrange(29..<33, with: bytes(crc ^ 0xFFFFFFFF))
        // ImageIO can reject the inconsistent header before exposing dimensions.
        #expect(throws: BackgroundImportError.self) { try BackgroundImageStore.prepare(data: png) }
        #expect(throws: BackgroundImportError.tooManyPixels) {
            try BackgroundImageStore.validateDimensions(width: 8001, height: 8000)
        }
        try BackgroundImageStore.validateDimensions(width: 8000, height: 8000)

        let animated = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(animated, UTType.png.identifier as CFString, 2, nil))
        CGImageDestinationAddImage(destination, try image(), nil)
        CGImageDestinationAddImage(destination, try image(hex: 0x000000), nil)
        #expect(CGImageDestinationFinalize(destination))
        #expect(throws: BackgroundImportError.animated) { try BackgroundImageStore.prepare(data: animated as Data) }
    }
}
