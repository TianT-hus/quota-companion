import AppKit
import SwiftUI
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@MainActor private final class Key222: SpeechCredentials {
    var reads = 0, saves = 0
    var fail = false
    func read() throws -> String { reads += 1; if fail { throw CloudSpeechError.keychainPermission }; return "test-only" }
    func save(_ value: String) throws { saves += 1; if fail { throw CloudSpeechError.keychain }; }
}

@Suite(.serialized) @MainActor struct Experience222Tests {
    @Test func imagePackageRoundTripWithoutTintAndWithPaint() throws {
        let dir = URL.temporaryDirectory.appendingPathComponent("wizard222-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let draft = ImageCharacterDraft(); draft.image = FantasyCatTexture.shared.body; draft.name = "新猫咪"
        let plain = try draft.prepared()
        #expect(plain.manifest.version == 4 && plain.manifest.animation == nil)
        let store = CharacterPackageStore(directory: dir)
        let id = try store.save(plain), reloaded = try store.load(id: id)
        #expect(reloaded.manifest == plain.manifest && reloaded.base == plain.base && reloaded.frames.isEmpty)
        draft.tintEnabled = true
        draft.commitStroke(.init(points: [.init(x:144,y:160)], radius: 80, erasing: false))
        let tinted = try draft.prepared()
        #expect(tinted.fillMask != plain.fillMask && tinted.base == plain.base)
        _ = try store.load(id: store.save(tinted))
        draft.clearMask(); #expect(try draft.prepared().fillMask == plain.fillMask)
        draft.undo(); #expect(try draft.prepared().fillMask == tinted.fillMask)
        draft.undo(); #expect(try draft.prepared().fillMask == plain.fillMask)
        draft.offset = .init(x: 2000,y:2000)
        #expect(throws: ImageCharacterError.self) { try draft.prepared() }
    }
    @Test func packageDiagnosticsAndOpaqueImage() throws {
        let dir = URL.temporaryDirectory.appendingPathComponent("wizard222-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        do { _ = try CharacterPackageStore.prepare(folder: dir); Issue.record("Missing manifest accepted") }
        catch { #expect(error.localizedDescription.contains("character.json")) }
        let data = try ImageCharacterDraft.png(ImageCharacterDraft.raster { ctx in ctx.setFillColor(NSColor.red.cgColor); ctx.fill(.init(x:0,y:0,width:288,height:320)) })
        let url = dir.appendingPathComponent("opaque.png"); try data.write(to: url)
        let draft = ImageCharacterDraft(); try draft.load(url); #expect(draft.opaque)
        let store = CharacterPackageStore(directory: dir.appendingPathComponent("library"))
        _ = try store.load(id: store.save(draft.prepared()))
        #expect(try Data(contentsOf: url) == data)
    }
    @Test func windowCentersAndClampsWithoutChangingSize() {
        let size = NSSize(width:400,height:300), screen = NSRect(x:1000,y:0,width:1200,height:800)
        let parent = NSRect(x:1200,y:100,width:780,height:620)
        let rect = OwnedDialogs.frame(size: size, parent: parent, screen: screen)
        #expect(rect.midX == parent.midX && rect.midY == parent.midY && rect.size == size)
        #expect(screen.contains(OwnedDialogs.frame(size: size, parent: .init(x:2100,y:700,width:780,height:620), screen: screen)))
    }
    @Test func credentialReuseInvalidationAndDenial() async throws {
        let key = Key222(), session = SpeechCredentialSession(lifetime: 0.1)
        let first = Task { try await session.read(provider: .bailian, interaction: true, injected: key) }
        let second = Task { try await session.read(provider: .bailian, interaction: true, injected: key) }
        _ = try await first.value; _ = try await second.value
        #expect(key.reads == 1)
        _ = try await session.read(provider: .bailian, interaction: false, injected: key); #expect(key.reads == 1)
        _ = try await session.read(provider: .minimax, interaction: true, injected: key); #expect(key.reads == 2)
        session.clear()
        _ = try await session.read(provider: .bailian, interaction: true, injected: key); #expect(key.reads == 3)
        try await Task.sleep(for: .milliseconds(150))
        _ = try await session.read(provider: .bailian, interaction: true, injected: key); #expect(key.reads == 4)
        session.clear(); key.fail = true
        do { _ = try await session.read(provider: .bailian, interaction: false, injected: key); Issue.record("Denied key accepted") } catch {}
        #expect(key.reads == 5)
        try await Task.sleep(for: .milliseconds(30)); #expect(key.reads == 5)
        session.clear()
    }
    @Test func failedCredentialSaveRestoresConfigurationAndBlankPreservesKey() throws {
        let suite = "keys222-\(UUID())", defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = Key222(), speech = CompanionSpeech(defaults: defaults, credentials: key)
        let original = speech.configuration.value, c = Copybook(language: .zhHans)
        key.fail = true
        #expect(!speech.saveAPI(provider: .minimax, address: APIProvider.minimax.endpoint, key: "fixture", consent: true, copy: c))
        #expect(speech.configuration.value == original && key.reads == 0)
        key.fail = false
        #expect(speech.saveAPI(provider: .minimax, address: APIProvider.minimax.endpoint, key: "", consent: true, copy: c))
        #expect(key.saves == 1 && key.reads == 0)
        speech.stop(); speech.credentialSession.clear()
    }
    @Test func sliderKeyboardStillHasFocus() throws {
        let window = NSWindow(contentRect: .init(x:0,y:0,width:300,height:100),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let slider = SettingsPercentSlider(frame: .init(x:10,y:10,width:240,height:24)); slider.minValue = 0; slider.maxValue = 100; slider.doubleValue = 40
        window.contentView?.addSubview(slider); window.makeFirstResponder(slider)
        #expect(slider.focusRingType == .default)
        let event = try #require(NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:124))
        slider.keyDown(with:event); #expect(slider.doubleValue == 41)
        slider.isEnabled = false; slider.keyDown(with:event); #expect(slider.doubleValue == 41)
    }
    @Test func nativeEvidence() async throws {
        guard let output = ProcessInfo.processInfo.environment["QUOTA_0222_PREVIEW"] else { return }
        let dir = URL(fileURLWithPath: output); try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let suite = "preview222-\(UUID())", defaults = try #require(UserDefaults(suiteName:suite)), data = URL.temporaryDirectory.appendingPathComponent(suite)
        defer { defaults.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:data) }
        let model = CompanionModel(defaults:defaults,store:.init(directory:data)); model.language = .zhHans
        defer { model.secretary.stop(); model.reminders.stop(); model.speech.stop() }
        try await render(NewCompanionWizard(model:model,close:{}), to:dir.appendingPathComponent("new-paths.png"), size:.init(width:618,height:300))
        try await render(NewCompanionWizard(model:model,close:{},previewRoute:"package"), to:dir.appendingPathComponent("package-guide.png"), size:.init(width:618,height:340))
        for step in 1...3 {
            let draft = ImageCharacterDraft(); draft.image = FantasyCatTexture.shared.body; draft.name = "示例猫咪"; draft.tintEnabled = step == 2
            try await render(NewCompanionWizard(model:model,close:{},previewDraft:draft,previewStep:step,previewRoute:"image"), to:dir.appendingPathComponent("image-step-\(step+1).png"), size:.init(width:618,height:490))
        }
        let previewSpeech = CompanionSpeech(defaults:defaults,credentials:Key222())
        try await render(APIConfigurationEditor(speech:previewSpeech,copy:model.copy), to:dir.appendingPathComponent("api-config.png"), size:.init(width:568,height:300))
        #expect(!model.codexFollow.enabled && !model.reminders.enabled)
    }
    private func render<V:View>(_ view:V,to url:URL,size:CGSize) async throws {
        let host = NSHostingView(rootView:view.frame(width:size.width,height:size.height).background(SettingsCardStyle.pageBackground).environment(\.colorScheme,.light))
        let window = NSWindow(contentRect:.init(origin:.zero,size:size),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false; window.contentView=host; window.orderFront(nil); defer { window.close() }
        try await Task.sleep(for:.milliseconds(250)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in:host.bounds)); host.cacheDisplay(in:host.bounds,to:bitmap)
        try #require(bitmap.representation(using:.png,properties:[:])).write(to:url)
    }
}
