import AppKit
import SwiftUI
import QuotaCore
import Testing
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor
struct SettingsTests {
    @Test func windowReuseResetLanguageAndNoDataMutation() async throws {
        let suite = "settings-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        d.set("old-image.png", forKey: "customMascotPath")
        d.set("{450, 300}", forKey: "pixelPetOrigin.2")
        let model = CompanionModel(defaults: d, store: SnapshotStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite)))
        model.language = .zhHans
        let original = model.snapshot
        let prefs = d.persistentDomain(forName: suite)! as NSDictionary
        let controller = SettingsWindowController(model: model)
        controller.show(activate: false)
        let window = try #require(controller.window)
        defer { window.close() }
        #expect(window.title == "设置")
        #expect(window.contentView?.bounds.size == CGSize(width: 780, height: 620))
        for page in SettingsPage.allCases {
            controller.navigation.page = page
            try await Task.sleep(for: .milliseconds(60))
            #expect(model.snapshot == original && !model.isExpanded)
            #expect((d.persistentDomain(forName: suite)! as NSDictionary) == prefs)
        }
        let session = controller.navigation.session
        window.close(); controller.show(activate: false)
        #expect(controller.window === window)
        #expect(controller.navigation.page == .appearance && controller.navigation.session != session)
        model.language = .english
        #expect(window.title == "Settings")
        model.palette = .mint; model.chestTextStyle = .goldInk; model.companionSize = .large
        let restored = CompanionModel(defaults: d, store: SnapshotStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite)))
        #expect(restored.palette == .mint && restored.chestTextStyle == .goldInk && restored.companionSize == .large)
        #expect(restored.customMascotPath == "old-image.png")
        #expect(d.string(forKey: "pixelPetOrigin.2") == "{450, 300}")
    }

    @Test func renderSettingsPages() async throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_019_PREVIEW"] else { return }
        let folder = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "settings-preview-\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        let model = CompanionModel(defaults: d, store: SnapshotStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(suite)))
        model.companionSize = .large
        model.snapshot = QuotaSnapshot(state: .live, source: .appServer, observedAt: .now, windows: QuotaSnapshot.demo().windows)
        let snapshot = model.snapshot
        let controller = SettingsWindowController(model: model)
        controller.show(activate: false)
        let window = try #require(controller.window)
        defer { window.close() }
        for language in [AppLanguage.zhHans, .english] {
            model.language = language
            for page in SettingsPage.allCases {
                controller.navigation.page = page
                try await Task.sleep(for: .milliseconds(180))
                let view = try #require(window.contentView)
                view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("\(language.rawValue)-\(page.rawValue).png"))
                #expect(model.snapshot == snapshot && !model.isExpanded)
                #expect(view.bounds.size == CGSize(width: 780, height: 620))
            }
        }
    }
}
