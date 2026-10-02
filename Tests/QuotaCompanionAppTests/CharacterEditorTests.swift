import AppKit
import SwiftUI
import QuotaCore
import Testing
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor struct CharacterEditorTests {
    let copy = Copybook(language: .zhHans)
    private func wait(_ library: CharacterLibrary) async throws {
        for _ in 0..<400 { if !library.isBusy { return }; try await Task.sleep(for: .milliseconds(10)) }
        throw CharacterEditError.missing
    }
    private func makeLibrary() async throws -> (CharacterLibrary, UserDefaults, URL, String) {
        let suite = "character-0217-\(UUID())", root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let d = try #require(UserDefaults(suiteName: suite))
        let l = CharacterLibrary(directory: root, defaults: d); try await wait(l)
        return (l, d, root, suite)
    }
    @Test func namesUseWeightedWholeCharactersAndRealWidth() {
        #expect(CharacterNamePolicy.units("猫Cat12") == 7)
        #expect(CharacterNamePolicy.units("👩‍👩‍👧‍👦") == 2)
        #expect(CharacterNamePolicy.valid("蓝花礼裙抛接手捧"))
        #expect(!CharacterNamePolicy.valid("蓝花礼裙抛接手捧花"))
        #expect(CharacterNamePolicy.valid("iiiiiiiiiiiiiiii"))
        #expect(!CharacterNamePolicy.valid("iiiiiiiiiiiiiiiii"))
        #expect(!CharacterNamePolicy.valid("WWWWWWWWW"))
        #expect(!CharacterNamePolicy.valid("A\nB"))
        #expect(!CharacterNamePolicy.valid("  "))
        #expect(CharacterNamePolicy.valid("我的猫咪"))
    }
    @Test func normalizedSizePreservesLegacyExactly() throws {
        #expect(CompanionSize(sliderPercent: 0).petSize == CGSize(width: 72, height: 80))
        #expect(CompanionSize(sliderPercent: 100).petSize == CGSize(width: 180, height: 200))
        for old in 50...125 {
            let value = CompanionSize(percent: old)
            #expect(CompanionSize(sliderPercent: value.sliderPercent).scale == value.scale)
        }
        #expect(CompanionSize.extraLarge.displayedPercent == 67)
        #expect(CompanionSize(sliderPercent: .nan).displayedPercent == 0)
        let suite = "size-0217-\(UUID())", d = try #require(UserDefaults(suiteName: suite))
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { d.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        d.set(100, forKey: "companionSize.percent.v1")
        let model = CompanionModel(defaults: d, store: SnapshotStore(directory: root))
        #expect(model.companionSize.scale == 2)
        #expect(d.object(forKey: "companionSize.slider.v2") == nil)
        model.companionSize = CompanionSize(sliderPercent: 67)
        #expect(d.integer(forKey: "companionSize.percent.v1") == 100)
        let restart = CompanionModel(defaults: d, store: SnapshotStore(directory: root))
        #expect(restart.companionSize.sliderPercent == 67)
        #expect(abs(restart.companionSize.petSize.width - 144.36) < 0.000001)
    }
    @Test func randomPoolNeverRepeatsAndSingleMotionWorks() {
        #expect(MotionChoice.next([], previous: nil) == nil)
        #expect(MotionChoice.next(["one"], previous: "one") == "one")
        var last: String?
        for _ in 0..<500 {
            let next = MotionChoice.next(["a", "b", "c"], previous: last)
            #expect(next != last); last = next
        }
    }
    @Test func nativeCanvasChoosesOneMotionPerBoundaryAndStops() throws {
        let fixture = try PublicCharacterFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture) }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let prepared = try CharacterPackageStore.prepare(folder: fixture)
        let a = try ImportedCharacter(id: "a", prepared: prepared), b = try ImportedCharacter(id: "b", prepared: prepared)
        let canvas = CharacterAnimationCanvas(frame: CGRect(x: 0,y: 0,width: 144,height: 160))
        let window = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = canvas; window.orderFront(nil)
        defer { canvas.stop(); window.close() }
        canvas.configure(character: a, tint: .init(hex: 0x72D5E8), remaining: 47, pixelScale: 2, eligible: true, frequency: .once, motions: [a,b])
        canvas.playOnceForTesting()
        #expect(canvas.isPlaying)
        let first = canvas.activeMotionID
        canvas.playOnceForTesting()
        #expect(canvas.isPlaying && canvas.activeMotionID != first)
        let second = canvas.activeMotionID
        canvas.configure(character: a, tint: .init(hex: 0x72D5E8), remaining: 35, pixelScale: 2, eligible: true, frequency: .once, motions: [a,b])
        #expect(canvas.activeMotionID == second) // Quota refresh must not choose a new action.
        canvas.configure(character: a, tint: .init(hex: 0x72D5E8), remaining: 35, pixelScale: 2, eligible: false, frequency: .once, motions: [a,b])
        #expect(!canvas.isPlaying && canvas.scheduledDeadline == nil)
    }
    @Test func importDraftCommitRestartAndRollback() async throws {
        let fixture = try PublicCharacterFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let (library, d, root, suite) = try await makeLibrary()
        defer { d.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let prepared = try CharacterPackageStore.prepare(folder: fixture)
        let original = try Data(contentsOf: fixture.appendingPathComponent("character.json"))
        try library.importPrepared(prepared, name: "礼裙", copy: copy)
        let role = try #require(library.characters.first)
        #expect(library.selectedID == nil)
        #expect(library.draftMotions(for: role.id).count == 1)
        let pending = try await library.prepareMotion(fixture, for: role.id)
        #expect(library.draftMotions(for: role.id).count == 1) // Cancelled draft has no writes.
        var motions = library.draftMotions(for: role.id) + [pending]
        let index = root.appendingPathComponent(role.id).appendingPathComponent("companion-edit-v1.json")
        let before = try Data(contentsOf: index)
        #expect(throws: (any Error).self) {
            try library.saveEdit(role.id, name: "礼裙二", motions: motions, copy: copy, writeIndex: { _,_ in throw CocoaError(.fileWriteNoPermission) })
        }
        #expect(try Data(contentsOf: index) == before)
        #expect(library.displayName(for: role.id, copy: copy) == "礼裙")
        #expect(library.playbackMotions(for: role.id).count == 1)
        let folder = root.appendingPathComponent(role.id).appendingPathComponent("motions")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).isEmpty)
        try library.saveEdit(role.id, name: "礼裙二", motions: motions, copy: copy)
        #expect(library.playbackMotions(for: role.id).count == 2)
        let restart = CharacterLibrary(directory: root, defaults: d); try await wait(restart)
        #expect(restart.displayName(for: role.id, copy: copy) == "礼裙二")
        #expect(restart.playbackMotions(for: role.id).count == 2)
        motions = restart.draftMotions(for: role.id)
        for i in motions.indices { motions[i].enabled = false }
        #expect(throws: (any Error).self) { try restart.saveEdit(role.id, name: "礼裙二", motions: motions, copy: copy) }
        #expect(restart.playbackMotions(for: role.id).count == 2)
        motions = restart.draftMotions(for: role.id); motions.removeAll { !$0.original }
        try restart.saveEdit(role.id, name: "礼裙二", motions: motions, copy: copy)
        #expect(restart.playbackMotions(for: role.id).count == 1)
        #expect(try Data(contentsOf: fixture.appendingPathComponent("character.json")) == original)
        var changed = prepared.manifest; changed.fillTop += 1
        let incompatible = PreparedCharacter(manifest: changed, base: prepared.base, fillMask: prepared.fillMask, details: prepared.details, frames: prepared.frames)
        #expect(throws: (any Error).self) { try library.validateMotion(incompatible, for: role.id) }
    }
    @Test func legacyLongNameAnimationOnlyEditAndDeleteFailure() async throws {
        let fixture = try PublicCharacterFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let (library, d, root, suite) = try await makeLibrary()
        defer { d.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        library.importPackage(fixture, copy: copy); try await wait(library)
        let role = try #require(library.selected)
        #expect(!CharacterNamePolicy.valid(role.manifest.name))
        try library.saveEdit(role.id, name: role.manifest.name, motions: library.draftMotions(for: role.id), copy: copy)
        #expect(library.displayName(for: role.id, copy: copy) == role.manifest.name)
        #expect(throws: (any Error).self) { try library.deleteCharacter("builtin") }
        #expect(throws: (any Error).self) { try library.deleteCharacter(role.id, trash: { _ in throw CocoaError(.fileWriteNoPermission) }) }
        #expect(library.selectedID == role.id && library.characters.count == 1)
        let trash = root.appendingPathComponent("test-trash")
        try library.deleteCharacter(role.id, trash: { try FileManager.default.moveItem(at: $0, to: trash) })
        #expect(library.selectedID == nil && library.characters.isEmpty)
        #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent("character.json").path))
        try FileManager.default.moveItem(at: trash, to: root.appendingPathComponent(role.id))
        let restored = CharacterLibrary(directory: root, defaults: d); try await wait(restored)
        #expect(restored.characters.count == 1 && restored.selectedID == nil)
        #expect(restored.displayName(for: role.id, copy: copy) == role.manifest.name)
    }
    @Test func nativeFourColumnScreenshots() async throws {
        let fixture = try PublicCharacterFixture.make()
        defer { try? FileManager.default.removeItem(at: fixture) }
        guard let path = ProcessInfo.processInfo.environment["QUOTA_GALLERY_0217_PREVIEW"] else { return }
        let output = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "screens-0217-\(UUID())", d = try #require(UserDefaults(suiteName: suite)), root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { d.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let model = CompanionModel(defaults: d, store: SnapshotStore(directory: root)); try await wait(model.characterLibrary)
        defer { model.secretary.stop(); model.reminders.stop() }
        model.language = .zhHans; model.companionSize = .extraLarge
        let prepared = try CharacterPackageStore.prepare(folder: fixture)
        for name in ["蓝花礼裙", "小蓝", "手捧花", "周末伙伴"] { try model.characterLibrary.importPrepared(prepared, name: name, copy: copy) }
        let role = try #require(model.characterLibrary.characters.first)
        model.characterLibrary.select(role.id)
        var motions = model.characterLibrary.draftMotions(for: role.id)
        var extra = try await model.characterLibrary.prepareMotion(fixture, for: role.id); extra.name = "动作二（测试副本）"
        motions.append(extra)
        try model.characterLibrary.saveEdit(role.id, name: "蓝花礼裙", motions: motions, copy: copy)
        let n = SettingsNavigation(); n.visible = true; n.page = .appearance
        try await render(SettingsView(model: model, navigation: n), output.appendingPathComponent("appearance-on.png"))
        model.characterLibrary.animationEnabled = false
        try await render(SettingsView(model: model, navigation: n), output.appendingPathComponent("appearance-off.png"))
        model.language = .english
        try await render(SettingsView(model: model, navigation: n), output.appendingPathComponent("appearance-en.png"))
        model.language = .zhHans
        try await render(CharacterEditor(model: model, item: .init(character: role), close: {}, back: {}).frame(width: 780,height: 620).background(SettingsCardStyle.pageBackground), output.appendingPathComponent("editor-multiple.png"))
        try await render(NewCharacterSheet(model: model, draft: .init(prepared: prepared, character: role), close: {}).frame(width: 780,height: 620).background(SettingsCardStyle.pageBackground), output.appendingPathComponent("import-name.png"))
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
