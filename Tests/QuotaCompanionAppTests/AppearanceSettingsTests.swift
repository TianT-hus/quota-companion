import AppKit
import SwiftUI
import QuotaCore
import Testing
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor
struct AppearanceSettingsTests {
    @Test func sizeChangesKeepAnchorAndRestartChoice() async throws {
        let suite = "size-change-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        let store = SnapshotStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
        let m = CompanionModel(defaults: d, store: store)
        let c = PanelController(model: m, positionDefaults: d, monitorsSystem: false)
        c.show()
        let original = c.nativeWindow.frame
        for size in [CompanionSize.large, .extraLarge, .medium] {
            m.companionSize = size
            try await Task.sleep(for: .milliseconds(70))
            #expect(c.nativeWindow.frame.size == size.petSize)
            #expect(c.nativeWindow.frame.maxX == original.maxX)
            #expect(c.nativeWindow.frame.minY == original.minY)
        }
        m.companionSize = .extraLarge
        try await Task.sleep(for: .milliseconds(70))
        let frame = c.nativeWindow.frame
        c.close()
        let restored = CompanionModel(defaults: d, store: store)
        let restarted = PanelController(model: restored, positionDefaults: d, monitorsSystem: false)
        restarted.show(); defer { restarted.close() }
        #expect(restarted.nativeWindow.frame == frame)
        #expect(restored.companionSize == .extraLarge && !restored.isExpanded)
    }
    @Test func defaultsPersistWithoutReplacingExistingSettings() throws {
        let suite = "appearance-test-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        d.set("old-pet.png", forKey: "customMascotPath")
        let store = SnapshotStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
        let m = CompanionModel(defaults: d, store: store)
        #expect(m.companionSize == .medium && m.palette == .water && m.chestTextStyle == .whiteInk)
        m.companionSize = .extraLarge; m.palette = .mint; m.chestTextStyle = .goldInk
        let restored = CompanionModel(defaults: d, store: store)
        #expect(restored.companionSize == .extraLarge && restored.palette == .mint && restored.chestTextStyle == .goldInk)
        #expect(restored.customMascotPath == "old-pet.png" && !restored.isExpanded)
    }

    @Test func scaledPanelPreview() async throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_018_PREVIEW"] else { return }
        _ = NSApplication.shared
        let dir = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suite = "appearance-preview-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        let m = CompanionModel(defaults: d, store: SnapshotStore(directory: dir.appendingPathComponent("isolated")))
        m.language = .zhHans
        if ProcessInfo.processInfo.environment["QUOTA_CUSTOM_PREVIEW"] == "1" {
            m.customAppearance.quotaHex = "#E795A7"
            m.customAppearance.progressFollowsQuota = false
            m.customAppearance.progressHex = "#A98BE6"
        }
        let now = Date.now
        let windows = [QuotaWindow(kind: .primary, usedPercent: 38, windowDurationMinutes: 300, resetsAt: now.addingTimeInterval(8280)), QuotaWindow(kind: .secondary, usedPercent: 21, windowDurationMinutes: 10080, resetsAt: now.addingTimeInterval(561600))]
        for size in CompanionSize.allCases {
            for style in ChestTextStyle.allCases {
                for count in [1, 2] {
                    m.companionSize = size; m.chestTextStyle = style
                    m.snapshot = QuotaSnapshot(state: .live, source: .appServer, observedAt: now, windows: count == 1 ? [windows[1]] : windows)
                    let c = PanelController(model: m, positionDefaults: d, monitorsSystem: false)
                    c.show()
                    c.nativeWindow.setFrameOrigin(CGPoint(x: 200, y: 300))
                    m.showKeyboardDetails()
                    try await Task.sleep(for: .milliseconds(250))
                    let pet = c.nativeWindow, detail = c.detailWindow
                    #expect(abs(Double(detail.frame.height) - Double(GlassDetailMetrics(windowCount: count).size.height) * size.scale) < 0.01)
                    #expect(abs(Double(pet.frame.intersection(detail.frame).width) - 36 * size.scale) < 0.01)
                    let bounds = pet.frame.union(detail.frame)
                    let context = try #require(CGContext(data: nil, width: Int(bounds.width), height: Int(bounds.height), bitsPerComponent: 8, bytesPerRow: Int(bounds.width) * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                    // Composite actual native backing views at their real panel frames,
                    // detail first and pet foreground. Not a full-desktop screenshot.
                    for panel in [detail, pet] {
                        let view = try #require(panel.contentView)
                        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
                        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                        view.cacheDisplay(in: view.bounds, to: bitmap)
                        if panel === detail {
                            // The gap between glass card and controls must be genuinely transparent.
                            let ratio = Double(bitmap.pixelsWide) / Double(view.bounds.width)
                            let gap = m.detailDirection == .left ? 32.0 : 204.0
                            let pixel = try #require(bitmap.colorAt(x: Int(gap * size.scale * ratio), y: bitmap.pixelsHigh / 2))
                            #expect(pixel.alphaComponent < 0.01)
                            #expect(view.layer?.cornerRadius == 0)
                        }
                        let image = try #require(bitmap.cgImage)
                        context.interpolationQuality = .none
                        context.draw(image, in: panel.frame.offsetBy(dx: -bounds.minX, dy: -bounds.minY))
                    }
                    let bitmap = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
                    try #require(bitmap.representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent("\(size.rawValue)-\(style.rawValue)-\(count).png"))
                    if size == .medium && style == .whiteInk {
                        let large = try #require(CGContext(data: nil, width: Int(bounds.width) * 4, height: Int(bounds.height) * 4, bitsPerComponent: 8, bytesPerRow: Int(bounds.width) * 16, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                        large.interpolationQuality = .none
                        large.draw(try #require(bitmap.cgImage), in: CGRect(x: 0, y: 0, width: bounds.width * 4, height: bounds.height * 4))
                        let output = NSBitmapImageRep(cgImage: try #require(large.makeImage()))
                        try #require(output.representation(using: .png, properties: [:])).write(to: dir.appendingPathComponent("medium-whiteInk-\(count)-4x.png"))
                    }
                    c.close(); m.collapse()
                }
            }
        }
    }
}
