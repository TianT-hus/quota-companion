import AppKit
import SwiftUI
import QuotaCore
import Testing
import ImageIO
import UniformTypeIdentifiers
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor
struct CompactDetailTests {
    @Test func nativeFlowPreview() async throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_018_FLOW"] else { return }
        let panel = NSPanel(contentRect: CGRect(x: 300, y: 300, width: 296, height: 28), styleMask: .borderless, backing: .buffered, defer: false)
        let view = LiquidProgressCanvas(frame: CGRect(x: 0, y: 0, width: 296, height: 28))
        panel.contentView = view; panel.orderFrontRegardless(); defer { panel.close() }
        let style = BackgroundAppearances.standard[BackgroundAppearanceKey(dark: false, highContrast: false, reduceTransparency: false)]
        view.update(remaining: 79, active: true, stale: false, appearance: style)
        let destination = try #require(CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.gif.identifier as CFString, 72, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        // Sample the live native presentation layer. This is a layer animation export,
        // not a desktop screen recording or a final packaged-app acceptance test.
        var firstFrame: Data?
        var sawMotion = false
        for _ in 0..<72 {
            try await Task.sleep(for: .milliseconds(83))
            let layer = try #require(view.layer?.presentation())
            let context = try #require(CGContext(data: nil, width: 592, height: 56, bitsPerComponent: 8, bytesPerRow: 592 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.scaleBy(x: 2, y: 2); layer.render(in: context)
            let image = try #require(context.makeImage())
            let pixels = try #require(image.dataProvider?.data) as Data
            if let firstFrame { sawMotion = sawMotion || pixels != firstFrame } else { firstFrame = pixels }
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.083]] as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
        #expect(sawMotion)
    }

    @Test func compositorKeepsAnimationAndStopsWhenInactive() throws {
        let panel = NSPanel(contentRect: CGRect(x: 100, y: 100, width: 120, height: 5), styleMask: .borderless, backing: .buffered, defer: false)
        let view = LiquidProgressCanvas(frame: CGRect(x: 0, y: 0, width: 120, height: 5))
        panel.contentView = view
        let style = BackgroundAppearances.standard[BackgroundAppearanceKey(dark: false, highContrast: false, reduceTransparency: false)]
        for value in [100.0, 79, 50, 30, 15, 5, 0] {
            view.update(remaining: value, active: true, stale: false, appearance: style)
            #expect(abs(view.fill.frame.width - 117 * value / 100) < 0.01)
            #expect((view.shine.animation(forKey: "flow") != nil) == (value > 0))
        }
        view.update(remaining: 79, active: true, stale: false, appearance: style)
        let animation = try #require(view.shine.animation(forKey: "flow"))
        #expect(animation.duration == 5)
        view.shine.setValue("retained", forKey: "probe")
        view.update(remaining: 79, active: true, stale: false, appearance: style)
        #expect(view.shine.value(forKey: "probe") as? String == "retained")
        #expect(view.shine.animation(forKey: "flow")?.beginTime == animation.beginTime)
        view.update(remaining: 79, active: false, stale: false, appearance: style)
        #expect(view.shine.animation(forKey: "flow") == nil)
        view.update(remaining: 79, active: true, stale: true, appearance: style)
        #expect(view.shine.animation(forKey: "flow") == nil)
        panel.close()
    }

    @Test func dualFlowPerformance() async throws {
        guard ProcessInfo.processInfo.environment["QUOTA_FLOW_CPU"] == "1" else { return }
        let suite = "quota-flow-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CompanionModel(defaults: defaults, store: SnapshotStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite)))
        model.customAppearance.quotaHex = "#E795A7"
        model.customAppearance.progressFollowsQuota = false
        model.customAppearance.progressHex = "#A98BE6"
        model.snapshot = QuotaSnapshot(state: .live, source: .appServer, observedAt: .now, windows: QuotaSnapshot.demo().windows)
        let controller = PanelController(model: model, positionDefaults: defaults, monitorsSystem: false)
        controller.show(); model.showExpanded(); model.holdInteraction(true); defer { controller.close() }
        try await Task.sleep(for: .seconds(1))
        func cpuSeconds() -> Double {
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        for size in [CompanionSize.medium, .extraLarge] {
            model.companionSize = size
            try await Task.sleep(for: .seconds(1))
            let start = cpuSeconds(), wall = ProcessInfo.processInfo.systemUptime
            try await Task.sleep(for: .seconds(30))
            let percent = (cpuSeconds() - start) / (ProcessInfo.processInfo.systemUptime - wall) * 100
            print("dualFlowReleaseTestCPU size=\(size.rawValue) value=\(percent)% (30s process CPU / wall time; isolated real panels, hover held)")
            #expect(model.isExpanded && controller.detailWindow.isVisible)
            #expect(percent < 5)
        }
        model.holdInteraction(false); model.collapse()
        try await Task.sleep(for: .seconds(1))
        let start = cpuSeconds(), wall = ProcessInfo.processInfo.systemUptime
        try await Task.sleep(for: .seconds(30))
        let percent = (cpuSeconds() - start) / (ProcessInfo.processInfo.systemUptime - wall) * 100
        print("catOnlyReleaseTestCPU size=extraLarge value=\(percent)% (30s isolated process CPU / wall time)")
        #expect(!model.isExpanded && percent < 2)
    }

    @Test func compactNativePreview() async throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_COMPACT_OUTPUT"] else { return }
        let directory = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "quota-preview-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CompanionModel(defaults: defaults, store: SnapshotStore(directory: directory.appendingPathComponent("isolated-cache")))
        model.language = .zhHans
        let now = Date.now
        let week = QuotaWindow(kind: .secondary, usedPercent: 21, windowDurationMinutes: 10080, resetsAt: now.addingTimeInterval(6 * 86400 + 12 * 3600))
        let short = QuotaWindow(kind: .primary, usedPercent: 38, windowDurationMinutes: 300, resetsAt: now.addingTimeInterval(2 * 3600 + 18 * 60))
        for count in [1, 2] {
            model.snapshot = QuotaSnapshot(state: .live, source: .appServer, observedAt: now, windows: count == 1 ? [week] : [short, week])
            model.showExpanded()
            let root = ZStack(alignment: .leading) {
                CompanionRootView(model: model).frame(width: 236, height: GlassDetailMetrics(windowCount: count).size.height).offset(x: 36)
                PixelCatView(snapshot: model.snapshot, locale: model.copy.locale)
            }.frame(width: 272, height: 80, alignment: .leading)
                .environment(\.colorScheme, .light)
            let host = NSHostingView(rootView: root)
            let panel = NSPanel(contentRect: CGRect(x: 200, y: 200, width: 272, height: 80), styleMask: .borderless, backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.contentView = host
            panel.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(250))
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("native-\(count)-retina.png"))
            let source = try #require(bitmap.cgImage)
            for scale in [1, 4] {
                let canvas = try #require(CGContext(data: nil, width: 272 * scale, height: 80 * scale,
                    bitsPerComponent: 8, bytesPerRow: 272 * scale * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                canvas.interpolationQuality = .none
                canvas.draw(source, in: CGRect(x: 0, y: 0, width: 272 * scale, height: 80 * scale))
                let output = NSBitmapImageRep(cgImage: try #require(canvas.makeImage()))
                try #require(output.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("native-\(count)-\(scale)x.png"))
            }
            panel.close()
        }
    }
}
