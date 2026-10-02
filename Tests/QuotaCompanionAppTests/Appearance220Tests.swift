import AppKit
import SwiftUI
import Testing
import ImageIO
import UniformTypeIdentifiers
import QuotaCore
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor struct Appearance220Tests {
    @Test func colorFormatsPreserveValuesAndInvalidDrafts() {
        var entry = ColorEntry(.init(hex: 0x722ED1))
        #expect(entry.format == .hex && entry.hex == "#722ED1")
        let switched = entry.select(.rgb); #expect(switched); #expect(entry.rgb == ["114", "46", "209"])
        entry.editRGB("256", at: 1)
        #expect(entry.invalidField == 2 && !entry.select(.hex))
        #expect(entry.format == .rgb && entry.rgb[1] == "256" && entry.color.hexString == "#722ED1")
        for bad in ["", "-1", "1.5", "一", "２", "0\n", " 2"] {
            entry.editRGB(bad, at: 1); #expect(entry.invalidField == 2)
        }
        entry.editRGB("0", at: 1); entry.editRGB("255", at: 2)
        #expect(entry.select(.hex) && entry.hex == "#7200FF")
        for bad in ["", "#123", "#1234567", "#GG0000", "#00\n0000"] {
            entry.editHex(bad); #expect(entry.invalidField == 0 && !entry.select(.rgb)); #expect(entry.hex == bad)
        }
        entry.editHex("abcdef"); #expect(entry.select(.rgb) && entry.rgb == ["171", "205", "239"])
        entry.select(.hex); #expect(entry.hex == "#ABCDEF")
    }
    @Test func textMigrationEditingAndEmptyLibrary() throws {
        for style in ChestTextStyle.allCases {
            var v = CustomAppearance(); v.migratePaletteLibrary(legacy: .water); v.migrateTextLibrary(legacy: style)
            #expect(v.version == 3 && v.textPresets.count == 3)
            #expect(v.chest?.text == style.text.hexString && v.chest?.outline == style.outline.hexString)
            let selected = v.chestPresetID; #expect(selected != nil)
            var edited = try #require(v.chest); edited.text = "#123456"; v.save(edited)
            #expect(v.chest?.text == "#123456")
            v.textPresets.map(\.id).forEach { v.removeText($0) }
            v.migrateTextLibrary(legacy: .whiteInk)
            #expect(v.textPresets.isEmpty && v.chestPresetID == nil && v.chest?.text == "#123456")
            let new = TextPreset(name: "New", text: "#123456", outline: "#FFFFFF")
            v.save(new); v.selectText(new)
            let restored = try JSONDecoder().decode(CustomAppearance.self, from: JSONEncoder().encode(v))
            #expect(restored == v && restored.textPresets.count == 1)
        }
        var old = CustomAppearance(); old.migratePaletteLibrary(legacy: .water)
        let custom = TextPreset(name: "Existing", text: "#F4FDFF", outline: "#10233C")
        old.save(custom); old.chest = custom; old.migrateTextLibrary(legacy: .goldInk)
        #expect(old.textPresets.count == 4 && old.chestPresetID == custom.id && old.chest == custom)
        var unlinked = CustomAppearance(); unlinked.chest = custom; unlinked.migrateTextLibrary(legacy: .whiteInk)
        #expect(unlinked.chest == custom && unlinked.chestPresetID == nil)
    }
    @Test func v2BackupAndFailedWriteLeaveOldData() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent("appearance220-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var old = CustomAppearance(); old.migratePaletteLibrary(legacy: .mint)
        let bytes = try JSONEncoder().encode(old), previous = directory.appendingPathComponent("appearance-v2.json")
        try bytes.write(to: previous)
        let store = AppearancePreferencesStore(directory: directory)
        #expect(store.load() == old)
        var next = old; next.migrateTextLibrary(legacy: .goldInk)
        try store.save(next, legacy: nil)
        #expect(try Data(contentsOf: previous) == bytes)
        #expect(try Data(contentsOf: directory.appendingPathComponent("appearance-before-v3.json")) == bytes)
        store.write = { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        next.textPresets.removeAll()
        #expect(throws: CocoaError.self) { try store.save(next, legacy: nil) }
        #expect(AppearancePreferencesStore(directory: directory).load()?.textPresets.count == 3)
    }
    @Test func modelTextFailurePreservesAppliedSnapshot() throws {
        let suite = "appearance220-model-\(UUID())", directory = URL.temporaryDirectory.appendingPathComponent(suite)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let model = CompanionModel(defaults: defaults, store: .init(directory: directory))
        let before = model.customAppearance
        model.appearanceStore.write = { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        var draft = before; draft.removeText(try #require(before.chestPresetID))
        #expect(!model.saveAppearance(draft) && model.customAppearance == before)
        #expect(model.appearanceDialog != nil)
    }
    @Test func switchMotionReversesAndStopsWithoutDuplicateDrawing() async throws {
        let window = NSWindow(contentRect: .init(x:0,y:0,width:100,height:70), styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let control = SettingsCapsuleSwitch(frame: .init(x:25,y:25,width:40,height:24))
        control.setButtonType(.switch); window.contentView?.addSubview(control); window.orderFront(nil)
        control.present(false, animated: true); #expect(control.onFraction == 0)
        control.state = .on; control.present(true, animated: true)
        #expect(SettingsCapsuleSwitch.interpolatedFraction(from:0,to:1,elapsed:0.08) == 0.5)
        #expect(SettingsCapsuleSwitch.interpolatedFraction(from:0.5,to:0,elapsed:0.08) == 0.25)
        try await Task.sleep(for: .milliseconds(65)); #expect((0...1).contains(control.onFraction))
        control.state = .off; control.present(false, animated: true)
        for _ in 0..<50 { if control.onFraction == 0 { break }; try await Task.sleep(for: .milliseconds(20)) }
        #expect(control.onFraction == 0)
        control.present(true, animated: false); #expect(control.onFraction == 1)
        #expect(control.focusRingType == .none)
        control.state = .off; control.present(false, animated: true); control.removeFromSuperview()
        #expect(control.onFraction == 0)
    }
    @Test func disclosureFocusReturnsToExactEnabledTrigger() {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 240, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let button = SettingsDisclosureControl(frame: .init(x: 10, y: 10, width: 28, height: 24))
        button.identifier = .init("speech.disclosure.quota")
        let field = NSTextField(frame: .init(x: 50, y: 10, width: 100, height: 24))
        window.contentView?.addSubview(button); window.contentView?.addSubview(field); window.orderFront(nil)
        window.makeFirstResponder(field)
        focusSettingsControl(named: "speech.disclosure.quota", in: window)
        #expect(window.firstResponder === button)
        window.makeFirstResponder(field)
        focusSettingsControl(named: "speech.disclosure.quota", in: nil)
        #expect(window.firstResponder === button)
        window.makeFirstResponder(field); button.isEnabled = false
        focusSettingsControl(named: "speech.disclosure.quota", in: window)
        #expect(window.firstResponder !== button)
    }
    @Test func native220Evidence() async throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_APPEARANCE_0220_PREVIEW"] else { return }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "appearance220-preview-\(UUID())", directory = URL.temporaryDirectory.appendingPathComponent(suite)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let m = CompanionModel(defaults: defaults, store: .init(directory: directory)); m.language = .zhHans
        defer { m.secretary.stop(); m.reminders.stop() }
        for format in ColorEntryFormat.allCases {
            try await render(ColorEditor(copy: m.copy, draft: .init(target: .quota, name: "紫色", hex: "#722ED1"), onSave: { _ in }, onCancel: {}, onDelete: {}, initialFormat: format), to: output.appendingPathComponent("color-\(format.rawValue).png"), width: 528, height: 520)
        }
        let preset = try #require(m.customAppearance.chest)
        try await render(ColorEditor(copy: m.copy, draft: .init(target: .text, presetID: preset.id, name: preset.name, hex: preset.text, outline: preset.outline), onSave: { _ in }, onCancel: {}, onDelete: {}), to: output.appendingPathComponent("text-preset-editor.png"), width: 528,height: 610)
        try await render(ColorEditor(copy: m.copy, draft: .init(target: .schedule, hex: "#DFEAFE"), onSave: { _ in }, onCancel: {}), to: output.appendingPathComponent("schedule-color.png"), width: 528,height: 480)
        for count in [1,2] { try await render(SettingsCardPreview(model: m, quotaCount: count), to: output.appendingPathComponent("detail-\(count).png"), width: 300,height: 160) }
        let fixture = try PublicCharacterFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture) }
        while m.characterLibrary.isBusy { try await Task.sleep(for: .milliseconds(20)) }
        m.characterLibrary.importPackage(fixture, copy: m.copy)
        while m.characterLibrary.isBusy { try await Task.sleep(for: .milliseconds(20)) }
        let navigation = SettingsNavigation(); navigation.visible = true; navigation.page = .appearance
        try await render(SettingsView(model: m, navigation: navigation), to: output.appendingPathComponent("appearance.png"), width: 780,height: 620)
        m.language = .english
        try await render(SettingsView(model: m, navigation: navigation), to: output.appendingPathComponent("appearance-english.png"), width: 780,height: 620)
        m.language = .zhHans
        for page in [SettingsPage.general, .speech, .advanced] {
            navigation.page = page
            try await render(SettingsView(model: m, navigation: navigation), to: output.appendingPathComponent("settings-\(page.rawValue).png"), width:780,height:620)
        }
        m.speech.editTemplate(.quota, copy: m.copy)
        try await render(SpeechPreferences(model: m, speech: m.speech, group: .switches).padding(24), to: output.appendingPathComponent("speech-expanded.png"), width:600,height:610)
        _ = m.speech.discardDraft(copy: m.copy)
        try await motionEvidence(m, output: output)
        try await render(SettingsSection(title: "额度通用设置") { AppearanceColorControls(model: m) }.padding(24).environment(\.settingsPickerWidth, 340).environment(\.companionAccessibility, .init(reduceMotion:true,reduceTransparency:true,contrast:.increased)), to: output.appendingPathComponent("high-contrast.png"), width:615,height:440)
        #expect(!m.codexFollow.enabled && !m.reminders.enabled)
    }
    private func motionEvidence(_ model: CompanionModel, output: URL) async throws {
        let host = NSHostingView(rootView: SettingsSection(title: "额度通用设置") { AppearanceColorControls(model: model) }.padding(24).frame(width:615,height:440,alignment:.top).background(SettingsCardStyle.pageBackground).environment(\.settingsPickerWidth,340).environment(\.colorScheme,.light))
        let window = NSWindow(contentRect: .init(x:0,y:0,width:615,height:440),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for:.milliseconds(250))
        var frames: [CGImage] = []
        for phase in 0..<5 {
            model.customAppearance.progressFollowsQuota = phase != 1 && phase != 3
            // Reverse the fourth transition before its 180 ms expansion completes.
            for index in 0..<(phase == 3 ? 1 : 7) {
                try await Task.sleep(for:.milliseconds(40)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                let b = try #require(host.bitmapImageRepForCachingDisplay(in:host.bounds)); host.cacheDisplay(in:host.bounds,to:b)
                frames.append(try #require(b.cgImage))
                if [0,2,6].contains(index) { try #require(b.representation(using:.png,properties:[:])).write(to:output.appendingPathComponent("motion-\(phase)-\(index).png")) }
            }
        }
        let destination = try #require(CGImageDestinationCreateWithURL(output.appendingPathComponent("switch-and-expansion.gif") as CFURL, UTType.gif.identifier as CFString, frames.count,nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in frames { CGImageDestinationAddImage(destination,frame,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.06]] as CFDictionary) }
        #expect(CGImageDestinationFinalize(destination))
    }
    private func render<V: View>(_ view: V, to url: URL, width: CGFloat, height: CGFloat) async throws {
        let host = NSHostingView(rootView: view.frame(width:width,height:height).background(SettingsCardStyle.pageBackground).environment(\.colorScheme,.light))
        let window = NSWindow(contentRect:.init(x:0,y:0,width:width,height:height),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for:.milliseconds(250)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        let b = try #require(host.bitmapImageRepForCachingDisplay(in:host.bounds)); host.cacheDisplay(in:host.bounds,to:b)
        try #require(b.representation(using:.png,properties:[:])).write(to:url)
    }
}
