import AppKit
import ImageIO
import QuotaCore
import SwiftUI
import Testing
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor
struct FantasyCatTests {
    @Test func importedSpriteIsCachedAndReallyTransparent() {
        let texture = FantasyCatTexture.shared
        #expect(texture === FantasyCatTexture.shared)
        #expect(texture.importedSuccessfully)
        #expect(texture.body.width == 72 && texture.body.height == 80)
        #expect(texture.alpha.allSatisfy { $0 == 0 || $0 == 255 })
        #expect(texture.alpha[0] == 0 && texture.alpha[71] == 0 && texture.alpha[79*72] == 0)
        #expect(texture.alpha.filter { $0 == 255 }.count > 2500)
        for image in [texture.body, texture.details] + texture.colors {
            let bytes = CFDataGetBytePtr(image.dataProvider!.data!)!
            for i in stride(from: 0, to: 72*80*4, by: 4) where bytes[i+3] > 0 {
                let r = Int(bytes[i]), g = Int(bytes[i+1]), b = Int(bytes[i+2])
                #expect(!(r > 70 && b > 70 && r-g > 55 && b-g > 55))
            }
        }
        for image in texture.colors {
            let bytes = CFDataGetBytePtr(image.dataProvider!.data!)!
            #expect((0..<(72*80)).allSatisfy { bytes[$0*4+3] == texture.alpha[$0] })
        }
    }
    @Test func quotaFillUsesPixelRowsAndPreservesUnknown() {
        #expect([100.0,50,30,15,5,0].map { FantasyCatTexture.fillRows($0) } == [74,37,22,11,4,0])
        #expect(FantasyCatTexture.fillRows(nil) == 0)
        #expect(FantasyCatTexture.fillRows(.nan) == 0)
        #expect([100.0,30,15,5].map { FantasyCatTexture.colorIndex($0) } == [0,1,2,3])
    }
    @Test func nativeRenderingPreview() throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_ART_OUTPUT"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func snapshot(_ remaining: Int) -> QuotaSnapshot {
            QuotaSnapshot(state: .live, source: .appServer, observedAt: .now,
                          windows: [QuotaWindow(kind: .primary, usedPercent: Double(100-remaining),
                                                windowDurationMinutes: 10080, resetsAt: .now)])
        }
        func cat(_ remaining: Int) -> some View {
            PixelCatView(snapshot: snapshot(remaining), locale: Locale(identifier: "zh-Hans"))
                .environment(\.companionAccessibility, CompanionAccessibilityOptions(reduceMotion: true, reduceTransparency: false, contrast: .standard))
        }
        func save(_ image: CGImage, name: String) throws {
            let url = directory.appendingPathComponent(name + ".png")
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
        }
        for remaining in [100,50,30,15,5,0] {
            let renderer = ImageRenderer(content: cat(remaining))
            renderer.scale = 1
            try save(try #require(renderer.cgImage), name: "cat-\(remaining)-72x80")
        }
        try save(FantasyCatTexture.shared.body, name: "fantasy-cat-base")
        let sheet = VStack(spacing: 28) {
            Text("72 × 80 pt · 实际原生视图渲染").font(.system(size: 15, weight: .medium))
            HStack(spacing: 60) {
                ForEach([100,50,5], id: \.self) { value in
                    VStack(spacing: 12) { cat(value); Text("\(value)%").font(.system(size: 12, design: .monospaced)) }.frame(width: 200)
                }
            }
            HStack(spacing: 24) {
                ForEach([100,50,5], id: \.self) { value in cat(value).scaleEffect(4).frame(width: 288,height: 320) }
            }
        }.padding(32).background(Color(red:0.92,green:0.95,blue:0.97)).foregroundStyle(Color(red:0.06,green:0.14,blue:0.24))
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 1
        try save(try #require(renderer.cgImage), name: "native-render-sheet")
    }
}
