import AppKit
import QuotaCore
import SwiftUI
import Testing
@testable import QuotaCompanionApp

@Suite(.serialized)
@MainActor
struct AppearanceTests {
    private func checkTransparentCorners(_ image: CGImage) throws {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try #require(CGContext(data: &pixels, width: width, height: height,
                                            bitsPerComponent: 8, bytesPerRow: width * 4,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        for (x, y) in [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)] {
            #expect(pixels[(y * width + x) * 4 + 3] == 0)
        }
        #expect(pixels[((height / 2) * width + width / 2) * 4 + 3] > 0)
    }

    @Test func catHasClearCornersAtEveryQuotaBoundary() throws {
        for remaining in [100, 50, 30, 15, 5, 0, -1] {
            for scheme in [ColorScheme.light, .dark] {
                for reduced in [false, true] {
                    let window = QuotaWindow(kind: .secondary, usedPercent: Double(100 - remaining),
                                             windowDurationMinutes: 10080, resetsAt: .now.addingTimeInterval(3600))
                    let snapshot = QuotaSnapshot(state: remaining < 0 ? .unavailable : (reduced ? .stale : .live),
                                                 source: .appServer, observedAt: .now, windows: remaining < 0 ? [] : [window])
                    let view = PixelCatView(snapshot: snapshot, locale: Locale(identifier: "zh-Hans"))
                        .environment(\.colorScheme, scheme)
                        .environment(\.companionAccessibility, CompanionAccessibilityOptions(
                            reduceMotion: true, reduceTransparency: reduced, contrast: reduced ? .increased : .standard))
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    let image = try #require(renderer.cgImage)
                    #expect(image.width == 144 && image.height == 160)
                    try checkTransparentCorners(image)
                }
            }
        }
    }

    @Test func cardRendersAllDataAndAccessibilityVariantsWithinItsOutline() throws {
        let suite = "quota-companion-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Never read or write the real user's snapshot, language or mascot settings.
        let store = SnapshotStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
        let model = CompanionModel(defaults: defaults, store: store)
        model.setCompanionVisible(false)
        model.showExpanded()
        for count in 0...2 {
            for language in [AppLanguage.zhHans, .english] {
                for scheme in [ColorScheme.light, .dark] {
                    for reduced in [false, true] {
                        model.language = language
                        let windows = Array(QuotaSnapshot.demo().windows.prefix(count))
                        model.snapshot = QuotaSnapshot(state: count == 0 ? .unavailable : (reduced ? .stale : .live),
                                                       source: .cache, observedAt: .now.addingTimeInterval(-95), windows: windows)
                        model.isConnecting = !reduced
                        let size = GlassDetailMetrics(windowCount: count).size
                        let renderer = ImageRenderer(content: CompanionRootView(model: model)
                            .frame(width: size.width, height: size.height)
                            .environment(\.colorScheme, scheme)
                            .environment(\.companionAccessibility, CompanionAccessibilityOptions(
                                reduceMotion: true, reduceTransparency: reduced, contrast: reduced ? .increased : .standard)))
                        renderer.scale = 2
                        let image = try #require(renderer.cgImage)
                        #expect(image.width == Int(size.width * 2) && image.height == Int(size.height * 2))
                        try checkTransparentCorners(image)
                    }
                }
            }
        }
    }
}
