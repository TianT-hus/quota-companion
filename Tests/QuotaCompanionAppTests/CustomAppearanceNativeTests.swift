import AppKit
import SwiftUI
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor
struct CustomAppearanceNativeTests {
    @Test func migrationDraftCancelAndPersistence() async throws {
        let suite = "custom-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        d.set("mint", forKey: "companionPalette"); d.set("old.png", forKey: "customMascotPath")
        let store = SnapshotStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite))
        let m = CompanionModel(defaults: d, store: store)
        #expect(m.palette == .mint && m.quotaTint == nil && m.customAppearance.progressFollowsQuota)
        let snapshot = m.snapshot
        m.customAppearance.quotaHex = "#ED869D"
        m.customAppearance.progressFollowsQuota = false; m.customAppearance.progressHex = "#AA88EE"
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/QuotaCompanionApp/Resources/water-mascot.png")
        m.importBackground(from: source, editBeforeApplying: true)
        try await finish(m)
        let draft = try #require(m.backgroundDraft)
        #expect(m.background == nil && m.customBackgroundName == nil)
        m.backgroundDraft = nil
        #expect(m.snapshot == snapshot && m.customBackgroundName == nil)
        m.applyBackgroundDraft(draft, composition: BackgroundComposition(x: 0.7, y: 0.6, zoom: 2, opacity: 0.75))
        try await finish(m)
        #expect(m.customBackgroundName != nil && m.customAppearance.background?.darkestPixelHex != nil)
        let restored = CompanionModel(defaults: d, store: store)
        #expect(restored.customAppearance == m.customAppearance && restored.customMascotPath == "old.png")
        #expect(restored.progressTint?.hexString == "#AA88EE" && restored.quotaTint?.hexString == "#ED869D")
        m.palette = .lavender
        #expect(m.quotaTint == nil && m.snapshot == snapshot)
    }
    private func finish(_ model: CompanionModel) async throws {
        for _ in 0..<250 { if !model.isImportingBackground { return }; try await Task.sleep(for: .milliseconds(20)) }
        Issue.record("Background operation exceeded 5 seconds")
    }
    @Test func cachedTintAndAnimationContinuity() throws {
        let texture = FantasyCatTexture.shared
        let color = QuotaCore.RGBColor(hex: 0xE795A7)
        #expect(texture.customImages(color).0 === texture.customImages(color).0)
        let a = BackgroundAppearances.standard[BackgroundAppearanceKey(dark: false, highContrast: false, reduceTransparency: false)]
        let bar = LiquidProgressCanvas(frame: CGRect(x: 0, y: 0, width: 180, height: 14))
        let w = NSPanel(contentRect: bar.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = bar; defer { w.close() }
        bar.update(remaining: 79, active: true, stale: false, appearance: a, customTint: color)
        let start = try #require(bar.shine.animation(forKey: "flow")?.beginTime)
        bar.update(remaining: 70, active: true, stale: false, appearance: a, customTint: QuotaCore.RGBColor(1,1,1))
        #expect(bar.shine.animation(forKey: "flow")?.beginTime == start)
        bar.update(remaining: 70, active: false, stale: false, appearance: a, customTint: color)
        #expect(bar.shine.animation(forKey: "flow") == nil)
        bar.update(remaining: 70, active: true, stale: true, appearance: a, customTint: color)
        #expect(bar.shine.animation(forKey: "flow") == nil)
    }
    @Test func nativePreviews() async throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_0110_PREVIEW"] else { return }
        let folder = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "custom-preview-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        let m = CompanionModel(defaults: d, store: SnapshotStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite)))
        if let source = ProcessInfo.processInfo.environment["QUOTA_CHARACTER_PREVIEW"], let image = NSImage(contentsOfFile: source) {
            try await capture(VStack(alignment: .leading, spacing: 20) {
                Text("人物尺寸预览 / Character scale").font(.headline)
                HStack(alignment: .bottom, spacing: 32) {
                    VStack { Image(nsImage: image).resizable().interpolation(.none).scaledToFit().frame(width: 72, height: 80); Text("72 × 80 pt") }
                    VStack { Image(nsImage: image).resizable().interpolation(.none).scaledToFit().frame(width: 288, height: 320); Text("4×") }
                }
                Text("美术草稿：棋盘格尚未移除，未导入应用。\nArt draft: opaque checkerboard remains; not imported.").font(.caption)
            }.padding(24).background(Color.white).foregroundStyle(Color.black), to: folder.appendingPathComponent("character-native-scale-draft.png"))
        }
        m.snapshot = QuotaSnapshot(state: .live, source: .demo, observedAt: .now, windows: QuotaSnapshot.demo().windows)
        for language in [AppLanguage.zhHans, .english] {
            m.language = language
            try await capture(SettingsView(model: m, navigation: SettingsNavigation()), to: folder.appendingPathComponent("\(language.rawValue)-appearance.png"))
            try await capture(ColorEditor(copy: m.copy, draft: ColorEditorDraft(target: .quota, name: "Rose", hex: "#E795A7"), onSave: { _ in }, onCancel: {}), to: folder.appendingPathComponent("\(language.rawValue)-color-editor.png"))
            try await capture(ColorEditor(copy: m.copy, draft: ColorEditorDraft(target: .text, name: "Gold", hex: "#FFE5A3"), onSave: { _ in }, onCancel: {}), to: folder.appendingPathComponent("\(language.rawValue)-text-editor.png"))
            let image = NSImage(size: NSSize(width: 600, height: 350), flipped: false) { rect in
                NSGradient(colors: [.systemPurple, .systemPink, .systemOrange])!.draw(in: rect, angle: 30)
                NSColor.white.setFill(); NSBezierPath(ovalIn: CGRect(x: 380, y: 180, width: 90, height: 90)).fill()
                return true
            }
            let draft = BackgroundDraft(image: image, prepared: nil, composition: BackgroundComposition(zoom: 1.5, opacity: 0.65))
            try await capture(BackgroundEditor(model: m, draft: draft), to: folder.appendingPathComponent("\(language.rawValue)-background-editor.png"))
            try await capture(BackgroundEditor(model: m, draft: draft, startsWithPreview: true), to: folder.appendingPathComponent("\(language.rawValue)-background-effect.png"))
            let fitted = BackgroundDraft(image: image, prepared: nil, composition: BackgroundComposition(zoom: BackgroundComposition.minimumZoom(image: image.size, viewport: CGSize(width: 200, height: 56)), opacity: 0.65))
            try await capture(BackgroundEditor(model: m, draft: fitted), to: folder.appendingPathComponent("\(language.rawValue)-background-fit.png"))
            try await capture(BackgroundEditor(model: m, draft: fitted, startsWithPreview: true), to: folder.appendingPathComponent("\(language.rawValue)-background-fit-effect.png"))
        }
    }
    private func capture<V: View>(_ view: V, to url: URL) async throws {
        let host = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: host)
        window.setContentSize(host.view.fittingSize); window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(250))
        let native = try #require(window.contentView)
        native.layoutSubtreeIfNeeded(); native.displayIfNeeded()
        let bitmap = try #require(native.bitmapImageRepForCachingDisplay(in: native.bounds))
        native.cacheDisplay(in: native.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}
