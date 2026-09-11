import AppKit
import ImageIO
import SwiftUI
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor
struct PublicReleaseTests {
    @Test func isolatedPreferencesSurviveRestart() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("release-defaults-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try IsolatedDefaults(directory: root)
        first.set("en", forKey: "language"); first.set(true, forKey: "speechEnabled")
        first.set(Data([1,2,3]), forKey: "customAppearance.v1")
        first.set("{40, 50}", forKey: "pixelPetOrigin.1")
        let second = try IsolatedDefaults(directory: root)
        #expect(second.string(forKey: "language") == "en")
        #expect(second.bool(forKey: "speechEnabled"))
        #expect(second.data(forKey: "customAppearance.v1") == Data([1,2,3]))
        #expect(second.string(forKey: "pixelPetOrigin.1") == "{40, 50}")
        second.removeObject(forKey: "language")
        #expect(try IsolatedDefaults(directory: root).string(forKey: "language") == nil)
    }
    @Test func syntheticHDPackageAndCache() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("release-hd-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var manifest = CharacterManifest(name: "Synthetic geometry", label: CharacterLabelRect(x: 12,y: 40,width: 48,height: 24),fillTop: 32,fillBottom: 77)
        manifest.version = 2
        try JSONEncoder().encode(manifest).write(to: root.appendingPathComponent("character.json"))
        for name in ["base.png","fill-mask.png","details.png"] {
            var pixels = [UInt8](repeating: 0,count: 288*320*4)
            for y in 16..<308 { for x in 40..<248 {
                if name == "base.png" || (name == "details.png" ? y < 128 : y >= 128) {
                    let i=(y*288+x)*4; pixels[i]=220; pixels[i+1]=200; pixels[i+2]=180; pixels[i+3]=255
                }
            } }
            let image = try #require(CGImage(width: 288,height: 320,bitsPerComponent: 8,bitsPerPixel: 32,bytesPerRow: 1152,space: CGColorSpace(name: CGColorSpace.sRGB)!,bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),provider: CGDataProvider(data: Data(pixels) as CFData)!,decode: nil,shouldInterpolate: false,intent: .defaultIntent))
            let target=try #require(CGImageDestinationCreateWithURL(root.appendingPathComponent(name) as CFURL,"public.png" as CFString,1,nil))
            CGImageDestinationAddImage(target,image,nil); #expect(CGImageDestinationFinalize(target))
        }
        let prepared=try CharacterPackageStore.prepare(folder: root)
        let character=try ImportedCharacter(id: "synthetic",prepared: prepared)
        #expect(character.base.width == 288 && character.base.height == 320)
        for scale in [1.0,1.5,2,3,4] {
            let a=character.textures(QuotaCore.RGBColor(hex: 0x72D5E8),pixelScale: scale)
            let b=character.textures(QuotaCore.RGBColor(hex: 0x72D5E8),pixelScale: scale)
            #expect(a.base === b.base && a.fill === b.fill)
            #expect(a.base.width == Int(72*scale) && a.mask.height == Int(80*scale))
        }
        for i in 0..<40 { _=character.textures(QuotaCore.RGBColor(Double(i)/40,0.5,0.6),pixelScale: 4) }
        #expect(character.cachedCombinationCount == 16)
        #expect(character.cachedTextureBytes <= 288*320*4*4*16)
        var bad=manifest; bad.fillTop=33
        try JSONEncoder().encode(bad).write(to: root.appendingPathComponent("character.json"))
        #expect(throws: (any Error).self) { try CharacterPackageStore.prepare(folder: root) }
    }
    @Test func renderPublicPreview() async throws {
        guard let path=ProcessInfo.processInfo.environment["QUOTA_PUBLIC_PREVIEW"] else { return }
        let output=URL(fileURLWithPath: path);try FileManager.default.createDirectory(at: output,withIntermediateDirectories: true)
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("release-preview-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let defaults=try IsolatedDefaults(directory: root)
        let model=CompanionModel(defaults: defaults,store: SnapshotStore(directory: root))
        model.snapshot = .demo(); model.language = .zhHans
        let panels=PanelController(model: model,positionDefaults: defaults,monitorsSystem: false)
        panels.show(); model.showExpanded();model.holdInteraction(true)
        defer { panels.close() }
        try await Task.sleep(for: .milliseconds(150))
        for (name,window) in [("cat",panels.nativeWindow),("details",panels.detailWindow)] {
            let view=try #require(window.contentView);view.layoutSubtreeIfNeeded();view.displayIfNeeded()
            let bitmap=try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds));view.cacheDisplay(in: view.bounds,to: bitmap)
            try #require(bitmap.representation(using: .png,properties: [:])).write(to: output.appendingPathComponent(name+"-example.png"))
        }
    }
}
