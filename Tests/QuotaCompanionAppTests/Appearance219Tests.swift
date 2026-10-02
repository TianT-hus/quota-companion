import AppKit
import SwiftUI
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor struct Appearance219Tests {
    @Test func migrationKeepsSelectionAndSeedsOnce() throws {
        var old = CustomAppearance()
        let custom = ColorPreset(name: "same color, distinct identity", hex: "#72D5E8")
        old.save(custom); old.quotaHex = custom.hex; old.quotaPresetID = custom.id
        old.background = .init(opacity: 0.73)
        var value = try JSONDecoder().decode(CustomAppearance.self, from: JSONEncoder().encode(old))
        value.migratePaletteLibrary(legacy: .mint)
        #expect(value.version == 2 && value.colors.count == 4 && value.quotaPresetID == custom.id)
        #expect(value.background == old.background)
        let ids = value.colors.map(\.id)
        ids.forEach { value.removeColor($0) }
        value.migratePaletteLibrary(legacy: .water)
        #expect(value.colors.isEmpty && value.quotaHex == custom.hex && value.quotaPresetID == nil)
        #expect(try JSONDecoder().decode(CustomAppearance.self, from: JSONEncoder().encode(value)) == value)
        for palette in CompanionPalette.allCases {
            var fresh = CustomAppearance(); fresh.migratePaletteLibrary(legacy: palette)
            #expect(fresh.quotaHex == palette.color.hexString)
            #expect(fresh.colors.contains { $0.id == fresh.quotaPresetID })
        }
    }
    @Test func sharedColorEditingAndDeletionKeepResolvedColors() {
        var v = CustomAppearance(); v.migratePaletteLibrary(legacy: .water)
        var p = v.colors[0]; v.progressPresetID = p.id
        p.hex = "#AABBCC"; v.save(p)
        #expect(v.quotaHex == p.hex && v.progressHex == p.hex)
        v.removeColor(p.id)
        #expect(v.quotaHex == p.hex && v.progressHex == p.hex)
        #expect(v.quotaPresetID == nil && v.progressPresetID == nil)
    }
    @Test func atomicPersistenceFailureAndRestart() throws {
        let suite = "appearance219-\(UUID())", dir = URL.temporaryDirectory.appendingPathComponent(suite)
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dir) }
        let legacy = try JSONEncoder().encode(CustomAppearance())
        d.set(legacy, forKey: "customAppearance.v1")
        let model = CompanionModel(defaults: d, store: .init(directory: dir))
        var value = model.customAppearance
        value.colors.removeAll(); value.quotaPresetID = nil
        #expect(model.saveAppearance(value))
        let saved = try Data(contentsOf: model.appearanceStore.url)
        #expect(try Data(contentsOf: dir.appendingPathComponent("appearance-before-v3.json")) == legacy)
        model.appearanceStore.write = { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        var draft = value; draft.quotaHex = "#FF0000"
        #expect(!model.saveAppearance(draft)); #expect(model.customAppearance == value)
        #expect(try Data(contentsOf: model.appearanceStore.url) == saved)
        #expect(model.appearanceDialog != nil)
        let style = model.chestTextStyle, storedStyle = d.string(forKey: "chestTextStyle")
        model.chestTextStyle = ChestTextStyle.allCases.first { $0 != style }!
        #expect(model.chestTextStyle == style && d.string(forKey: "chestTextStyle") == storedStyle)
        let restarted = CompanionModel(defaults: d, store: .init(directory: dir))
        #expect(restarted.customAppearance == value && restarted.customAppearance.colors.isEmpty)
        #expect(d.data(forKey: "customAppearance.v1") == legacy)
    }
    @Test func backgroundFailureKeepsSelectionAndDraft() async throws {
        let suite = "background219-\(UUID())", dir = URL.temporaryDirectory.appendingPathComponent(suite)
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dir) }
        let m = CompanionModel(defaults: d, store: .init(directory: dir))
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/QuotaCompanionApp/Resources/water-mascot.png")
        m.importBackground(from: source, editBeforeApplying: true)
        while m.isImportingBackground { try await Task.sleep(for: .milliseconds(20)) }
        let draft = try #require(m.backgroundDraft), before = m.customAppearance
        m.appearanceStore.write = { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        m.applyBackgroundDraft(draft, composition: .init(opacity: 0.7))
        while m.isImportingBackground { try await Task.sleep(for: .milliseconds(20)) }
        #expect(m.backgroundDraft?.id == draft.id && m.background == nil && m.customBackgroundName == nil)
        #expect(m.customAppearance == before && m.backgroundDialog != nil && m.appearanceDialog == nil)
        #expect(d.string(forKey: "customBackgroundName") == nil)
    }
    @Test func intervalMigrationValidationAndTiming() throws {
        #expect(AnimationInterval(legacy: .once).seconds == 57)
        #expect(AnimationInterval(legacy: .twice).seconds == 27)
        #expect(AnimationInterval(legacy: .four).seconds == 12)
        #expect(AnimationInterval(legacy: .natural).seconds == 30)
        #expect(AnimationInterval(legacy: .continuous).continuous)
        for bad in ["", "0", "3601", "1.5", "-1", "一", " 30", "1\n"] { #expect(AnimationInterval.parse(bad) == nil) }
        for good in ["1", "30", "3600", "003"] { #expect(AnimationInterval.parse(good) != nil) }
        var p = CharacterDancePlayback()
        p.resume(eligible: true, now: 100, delay: 7); #expect(p.nextDeadline == 107)
        p.tick(now: 107, nextDelay: 7); #expect(p.nextDeadline == 110)
        p.tick(now: 110, nextDelay: 7); #expect(p.nextDeadline == 117)
        p.setEligible(false, now: 112, delay: 7); #expect(p.nextDeadline == nil)
        p.resume(eligible: true, now: 200, delay: 7); #expect(p.nextDeadline == 207)
        p.tick(now: 220, nextDelay: 7); #expect(p.nextDeadline == 227)
    }
    @Test func intervalPreferencePreservesLegacy() throws {
        let suite = "interval219-\(UUID())", dir = URL.temporaryDirectory.appendingPathComponent(suite)
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dir) }
        d.set("twice", forKey: "character.animationFrequency.v1")
        let library = CharacterLibrary(directory: dir, defaults: d)
        #expect(library.animationInterval.seconds == 27)
        library.animationInterval = .init(continuous: false, seconds: 8)
        #expect(CharacterLibrary(directory: dir, defaults: d).animationInterval.seconds == 8)
        #expect(d.string(forKey: "character.animationFrequency.v1") == "twice")
    }
    @Test func nativeAppearanceEvidence() async throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_APPEARANCE_0219_PREVIEW"] else { return }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "appearance219-preview-\(UUID())", dir = URL.temporaryDirectory.appendingPathComponent(suite)
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: dir) }
        let m = CompanionModel(defaults: d, store: .init(directory: dir)); m.language = .zhHans
        defer { m.secretary.stop(); m.reminders.stop() }
        let fixture = try PublicCharacterFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture) }
        while m.characterLibrary.isBusy { try await Task.sleep(for: .milliseconds(20)) }
        m.characterLibrary.importPackage(fixture, copy: m.copy)
        while m.characterLibrary.isBusy { try await Task.sleep(for: .milliseconds(20)) }
        let n = SettingsNavigation(); n.visible = true; n.page = .appearance
        for lang in [AppLanguage.zhHans, .english] {
            m.language = lang
            try await render(SettingsView(model: m, navigation: n), to: output.appendingPathComponent("\(lang.rawValue)-appearance.png"))
            try await render(VStack(spacing: 24) {
                SettingsSection(title: m.copy.text("额度通用设置", "Quota settings")) { AppearanceColorControls(model: m) }
                AppearanceBackgroundSettings(model: m)
            }.environment(\.settingsPickerWidth, 340).padding(24).frame(width: 615, height: 620).background(SettingsCardStyle.pageBackground), to: output.appendingPathComponent("\(lang.rawValue)-colors-background.png"), width: 615)
        }
        m.language = .zhHans
        m.characterLibrary.animationInterval.continuous = true
        try await render(AppearanceGeneralSettings(model: m, library: m.characterLibrary).padding(24).frame(width: 615,height: 300), to: output.appendingPathComponent("continuous.png"), width: 615, height: 300)
        m.characterLibrary.animationEnabled = false
        try await render(AppearanceGeneralSettings(model: m, library: m.characterLibrary).padding(24).frame(width: 615,height: 260), to: output.appendingPathComponent("animation-off.png"), width: 615, height: 260)
        m.customAppearance.progressFollowsQuota = false
        try await render(SettingsSection(title: "额度通用设置") { AppearanceColorControls(model: m) }.environment(\.settingsPickerWidth, 340).padding(24).frame(width: 615,height: 420), to: output.appendingPathComponent("independent-progress.png"), width: 615,height: 420)
        let preset = m.customAppearance.colors[0]
        try await render(ColorEditor(copy: m.copy, draft: .init(target: .quota, presetID: preset.id, name: preset.name, hex: preset.hex), onSave: { _ in }, onCancel: {}, onDelete: {}), to: output.appendingPathComponent("color-editor.png"), width: 528,height: 550)
        try await render(SettingsCardPreview(model: m, quotaCount: 1), to: output.appendingPathComponent("single-quota.png"), width: 300,height: 160)
        let source = fixture.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/QuotaCompanionApp/Resources/water-mascot.png")
        m.importBackground(from: source, editBeforeApplying: true)
        while m.isImportingBackground { try await Task.sleep(for: .milliseconds(20)) }
        let draft = try #require(m.backgroundDraft)
        m.applyBackgroundDraft(draft, composition: .init(opacity: 0.5))
        while m.isImportingBackground { try await Task.sleep(for: .milliseconds(20)) }
        try await render(AppearanceBackgroundSettings(model: m).environment(\.settingsPickerWidth, 340).padding(24).frame(width: 615, height: 340), to: output.appendingPathComponent("background-transparency.png"), width: 615, height: 340)
        for i in 0..<20 { m.customAppearance.colors.append(ColorPreset(name: "Long preset \(i)", hex: "#\(String(format: "%06X", (i+1)*300000))")) }
        try await render(SettingsSection(title: "额度通用设置") { AppearanceColorControls(model: m) }.environment(\.settingsPickerWidth, 340).padding(24).frame(width: 615,height: 420), to: output.appendingPathComponent("many-presets.png"), width: 615,height: 420)
        try await render(SettingsSection(title: "额度通用设置") { AppearanceColorControls(model: m) }.environment(\.settingsPickerWidth, 340).environment(\.companionAccessibility, .init(reduceMotion: true, reduceTransparency: true, contrast: .increased)).padding(24).frame(width: 615,height: 420), to: output.appendingPathComponent("high-contrast-reduced-motion.png"), width: 615,height: 420)
        m.customAppearance.colors.map(\.id).forEach { m.customAppearance.removeColor($0) }
        try await render(SettingsSection(title: "额度通用设置") { AppearanceColorControls(model: m) }.environment(\.settingsPickerWidth, 340).padding(24).frame(width: 615,height: 420), to: output.appendingPathComponent("empty-library.png"), width: 615,height: 420)
        let replacement = ColorPreset(name: "Added after empty", hex: "#AABBCC")
        m.customAppearance.save(replacement)
        #expect(m.customAppearance.colors == [replacement])
        #expect(!m.codexFollow.enabled && !m.reminders.enabled)
    }
    private func render<V: View>(_ view: V, to url: URL, width: CGFloat = 780, height: CGFloat = 620) async throws {
        let host = NSHostingView(rootView: view.background(SettingsCardStyle.pageBackground).environment(\.colorScheme, .light))
        let window = NSWindow(contentRect: .init(x: 0,y: 0,width: width,height: height), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        let b = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: b)
        try #require(b.representation(using: .png,properties: [:])).write(to: url)
    }
}
