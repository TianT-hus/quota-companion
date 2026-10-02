import AppKit
import SwiftUI
import QuotaCore
import Testing
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor struct SettingsCardTests {
    @Test func speechRoutePreservesPreferencesAndData() async throws {
        let suite = "settings-cards-\(UUID())"
        let root = URL.temporaryDirectory.appendingPathComponent(suite)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let model = CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
        model.speech.scheduleEnabled = true
        model.speech.voiceID = "fixture-unavailable-voice"
        model.speech.rate = 0.4; model.speech.volume = 0.65
        #expect(model.secretary.commit { $0.reminders = false })
        let data = model.secretary.data
        let preferences = defaults.persistentDomain(forName: suite)! as NSDictionary
        let controller = SettingsWindowController(model: model)
        controller.show(page: .speech, activate: false)
        let window = try #require(controller.window)
        defer { window.close(); model.secretary.stop(); model.reminders.stop() }
        for page in [SettingsPage.general, .speech, .appearance, .advanced, .speech] {
            controller.navigate(to: page)
            try await Task.sleep(for: .milliseconds(50))
            #expect(controller.navigation.page == page && controller.window === window)
        }
        #expect(model.secretary.data == data)
        #expect(defaults.persistentDomain(forName: suite)! as NSDictionary == preferences)
        #expect(!model.reminders.enabled && !model.codexFollow.enabled)
        let restored = CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
        #expect(restored.speech.scheduleEnabled && restored.speech.voiceID == "fixture-unavailable-voice")
        #expect(restored.speech.rate == 0.4 && restored.speech.volume == 0.65)
        #expect(!restored.secretary.data.reminders)
        #expect(SettingsPage.allCases.map(\.rawValue) == ["day", "todos", "appearance", "speech", "general", "advanced"])
        restored.secretary.stop(); restored.reminders.stop()
    }

    @Test func nativeFourPageScreenshots() async throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_SETTINGS_0213_PREVIEW"] else { return }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "settings-cards-preview-\(UUID())"
        let root = URL.temporaryDirectory.appendingPathComponent(suite)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let model = CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
        defer { model.secretary.stop(); model.reminders.stop() }
        let navigation = SettingsNavigation()
        navigation.visible = true
        navigation.requestPage = { navigation.page = $0 }
        for language in [AppLanguage.zhHans, .english] {
            model.language = language
            for page in [SettingsPage.appearance, .general, .speech, .advanced] {
                navigation.page = page
                try await render(SettingsView(model: model, navigation: navigation), output: output.appendingPathComponent("\(language.rawValue)-\(page.rawValue).png"))
            }
        }
        model.language = .zhHans; navigation.page = .speech
        if ProcessInfo.processInfo.environment["QUOTA_CLOUD_PREVIEW"] == "1" {
            model.speech.selectSource(.bailian, consent: true)
            try await render(SettingsView(model: model, navigation: navigation), output: output.appendingPathComponent("zhHans-cloud.png"))
            model.language = .english
            try await render(SettingsView(model: model, navigation: navigation), output: output.appendingPathComponent("english-cloud.png"))
            model.language = .zhHans
        }
        try await render(SettingsView(model: model, navigation: navigation), output: output.appendingPathComponent("zhHans-speech-high-contrast.png"), highContrast: true)
        for kind in SpeechTemplateKind.allCases {
            model.speech.editTemplate(kind, copy: model.copy)
            try await render(SettingsView(model: model, navigation: navigation), output: output.appendingPathComponent("zhHans-editor-\(kind.rawValue).png"))
            if let draft = model.speech.draft {
                try await render(SettingsSection(title: model.copy.text("播报内容", "Spoken content")) {
                    SpeechTemplateEditor(speech: model.speech, copy: model.copy, draft: Binding(get: { model.speech.draft ?? draft }, set: { model.speech.draft = $0 }))
                }.padding(24).frame(width: 780, height: 620).background(SettingsCardStyle.pageBackground), output: output.appendingPathComponent("zhHans-editor-\(kind.rawValue)-full.png"))
            }
            _ = model.speech.discardDraft(copy: model.copy)
        }
        var api = model.speech.configuration.value; api.provider = .minimax; api.consented.insert(.minimax)
        try model.speech.configuration.save(api)
        model.speech.selectSource(.bailian)
        try await render(SettingsView(model: model, navigation: navigation), output: output.appendingPathComponent("zhHans-minimax.png"))
        #expect(!model.reminders.enabled && !model.codexFollow.enabled)
    }

    private func render<V: View>(_ view: V, output: URL, highContrast: Bool = false) async throws {
        let host = NSHostingView(rootView: view.environment(\.companionAccessibility, highContrast ? CompanionAccessibilityOptions(reduceMotion: true, reduceTransparency: true, contrast: .increased) : nil))
        host.appearance = NSAppearance(named: highContrast ? .accessibilityHighContrastAqua : .aqua)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 780, height: 620), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        #expect(host.bounds.size == CGSize(width: 780, height: 620))
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: output)
    }
}
