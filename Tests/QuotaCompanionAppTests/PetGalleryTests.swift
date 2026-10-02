import AppKit
import SwiftUI
import QuotaCore
import Testing
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor struct PetGalleryTests {
    @Test func percentageMigrationPersistenceAndEdges() throws {
        let suite = "gallery-size-\(UUID())", root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        for old in CompanionSize.allCases {
            d.removeObject(forKey: "companionSize.percent.v1"); d.removeObject(forKey: "companionSize.slider.v2"); d.set(old.rawValue, forKey: "companionSize")
            let m = CompanionModel(defaults: d, store: SnapshotStore(directory: root))
            #expect(m.companionSize == old)
            #expect(d.object(forKey: "companionSize.percent.v1") == nil)
            m.companionSize = CompanionSize(percent: 83)
            #expect(d.string(forKey: "companionSize") == old.rawValue)
            let restored = CompanionModel(defaults: d, store: SnapshotStore(directory: root))
            #expect(restored.companionSize.percent == 83)
            #expect(!restored.codexFollow.enabled && !restored.reminders.enabled)
        }
        #expect(CompanionSize(percent: 0) == .medium)
        #expect(CompanionSize(percent: 999).percent == 125)
        #expect(CompanionSize(rawValue: "percent:126") == nil)
        for p in 50...125 {
            let size = CompanionSize(percent: p), screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
            #expect(CompanionSize(rawValue: size.rawValue) == size)
            for x in [0.0, 600, 1440-size.petSize.width] {
                for y in [0.0, 300, 900-size.petSize.height] {
                    let pet = CGRect(origin: CGPoint(x: x, y: y), size: size.petSize)
                    let layout = PetPanelLayout(pet: pet, windowCount: 2, screen: screen, scale: size.scale, detailSize: CGSize(width: 150, height: 80))
                    #expect(screen.contains(layout.detail))
                    #expect(layout.detail.size == CGSize(width: 150*size.scale, height: 80*size.scale))
                    #expect(layout.bridge.width > 0)
                }
            }
        }
    }
    @Test func aliasDoesNotRenameResourcesAndImportDoesNotSelect() async throws {
        let suite = "gallery-alias-\(UUID())", root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let c = Copybook(language: .zhHans), library = CharacterLibrary(directory: root, defaults: d)
        try await wait(library)
        #expect(library.rename(nil, to: "我的猫咪", copy: c))
        #expect(!library.rename(nil, to: "  ", copy: c))
        #expect(!library.rename(nil, to: "A\nB", copy: c))
        #expect(!library.rename(nil, to: String(repeating: "字", count: 41), copy: c))
        #expect(library.displayName(for: nil, copy: c) == "我的猫咪")
        let fixture = try PublicCharacterFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture) }
        if FileManager.default.fileExists(atPath: fixture.path) {
            let original = try Data(contentsOf: fixture.appendingPathComponent("character.json"))
            library.importPackage(fixture, copy: c, selectAfterImport: false); try await wait(library)
            #expect(library.selectedID == nil)
            let role = try #require(library.characters.first)
            let saved = try Data(contentsOf: root.appendingPathComponent(role.id).appendingPathComponent("character.json"))
            #expect(library.rename(role.id, to: "我的专注伙伴", copy: c))
            #expect(role.manifest.name != "我的专注伙伴")
            #expect(try Data(contentsOf: fixture.appendingPathComponent("character.json")) == original)
            #expect(try Data(contentsOf: root.appendingPathComponent(role.id).appendingPathComponent("character.json")) == saved)
            library.select(role.id)
            let restarted = CharacterLibrary(directory: root, defaults: d); try await wait(restarted)
            #expect(restarted.selectedID == role.id)
            #expect(restarted.displayName(for: role.id, copy: c) == "我的专注伙伴")
            #expect(restarted.displayName(for: nil, copy: c) == "我的猫咪")
        } else { Issue.record("Required checked-in/local preview fixture missing: \(fixture.path)") }
    }
    @Test func nativeGalleryScreenshots() async throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_GALLERY_0216_PREVIEW"] else { return }
        let output = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "gallery-screens-\(UUID())", root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let m = CompanionModel(defaults: d, store: SnapshotStore(directory: root))
        defer { m.secretary.stop(); m.reminders.stop() }
        m.language = .zhHans; m.companionSize = .extraLarge
        let fixture = try PublicCharacterFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture) }
        try await wait(m.characterLibrary)
        m.characterLibrary.importPackage(fixture, copy: m.copy, selectAfterImport: false)
        try await wait(m.characterLibrary)
        m.characterLibrary.select(m.characterLibrary.characters.first?.id)
        let n = SettingsNavigation(); n.visible = true; n.page = .appearance
        for lang in [AppLanguage.zhHans, .english] {
            m.language = lang
            for page in [SettingsPage.appearance, .general, .speech, .advanced] {
                n.page = page
                try await render(SettingsView(model: m, navigation: n), output.appendingPathComponent("\(lang.rawValue)-\(page.rawValue).png"))
            }
        }
        m.language = .zhHans; n.page = .appearance
        try await render(SettingsView(model: m, navigation: n).environment(\.companionAccessibility, CompanionAccessibilityOptions(reduceMotion: true, reduceTransparency: true, contrast: .increased)), output.appendingPathComponent("gallery-high-contrast.png"))
        if let character = m.characterLibrary.characters.first {
            try await render(CharacterDetail(model: m, library: m.characterLibrary, item: GalleryCharacter(character: character), copy: m.copy, close: {}).frame(width: 780, height: 620).background(SettingsCardStyle.pageBackground), output.appendingPathComponent("character-detail.png"))
        }
    }
    private func wait(_ library: CharacterLibrary) async throws {
        for _ in 0..<400 { if !library.isBusy { return }; try await Task.sleep(for: .milliseconds(25)) }
        Issue.record("Character load/import timed out")
    }
    private func render<V: View>(_ view: V, _ url: URL) async throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .light)); host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: CGRect(x: 0,y: 0,width: 780,height: 620), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}
