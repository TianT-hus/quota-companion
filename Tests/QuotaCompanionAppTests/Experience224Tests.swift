import AppKit
import SwiftUI
import Testing
@testable import QuotaCompanionApp

@MainActor private final class Key224: SpeechCredentials {
    var reads = 0; var fail = false
    func read() throws -> String { reads += 1; return "test-only" }
    func save(_ value: String) throws { if fail { throw SpeechConfigError.storage } }
}
private actor API224: CloudSpeechSynthesizing {
    var texts: [String] = []
    func synthesize(text: String, language: SpeechLanguage, voice: String, key: String) async throws -> Data {
        texts.append(text)
        try? await Task.sleep(for: .milliseconds(60))
        return Data([1])
    }
}
@MainActor private final class Audio224: CloudAudioPlaying {
    var count = 0
    func play(_ data: Data, rate: Double, volume: Double) throws { count += 1 }
    func stop() {}
}
@MainActor private final class Translation224: SpeechTranslating {
    var inputs: [String] = []
    func translate(_ text: String, to target: SpeechLanguage) async throws -> String { inputs.append(text); return text }
    func cancel() {}
}

@Suite(.serialized) @MainActor struct Experience224Tests {
    let copy = Copybook(language: .zhHans)
    @Test func freeTemplatesAndLimits() throws {
        try SpeechTemplate(kind: .schedule, pieces: [.words("请休息。")]).validate()
        try SpeechTemplate(kind: .schedule, pieces: [.value(.now), .value(.now)]).validate()
        try SpeechTemplate(kind: .quota, pieces: [.value(.percent)]).validate()
        try SpeechTemplate(kind: .quota, pieces: (0..<100).map { _ in .words("字") }).validate()
        for template in [SpeechTemplate(kind: .schedule, pieces: [.words(" \n")]), .init(kind: .quota, pieces: [.value(.event)]), .init(kind: .quota, pieces: (0..<41).map { _ in .value(.percent) }), .init(kind: .quota, pieces: [.words(String(repeating: "字", count: 401))])] {
            #expect(throws: (any Error).self) { try template.validate() }
        }
    }
    @Test func inlineRoundTripAndAtomicAttachment() throws {
        let pieces: [SpeechPiece] = [.words("现在😊"), .value(.now), .words("\n然后"), .value(.now), .value(.event)]
        let attributed = SpeechInlineDocument.attributed(pieces, copy: copy)
        #expect(SpeechInlineDocument.sameContent(pieces, SpeechInlineDocument.pieces(attributed)))
        var attachments = 0
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            if value is SpeechTokenAttachment { attachments += 1; #expect(range.length == 1) }
        }
        #expect(attachments == 3)
    }
    @Test func insertReplaceUndoRedoAndMarkedText() throws {
        let window = NSWindow(contentRect: .init(x:0,y:0,width:400,height:160), styleMask:[.titled], backing:.buffered, defer:false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let text = SpeechInlineTextView(frame: .init(x:0,y:0,width:400,height:160))
        text.allowsUndo = true; text.isRichText = true; text.copybook = copy; text.allowedTokens = [.now,.event]
        window.contentView = text; window.makeFirstResponder(text)
        text.insertText("开始结束", replacementRange: NSRange(location:0,length:0))
        text.setSelectedRange(.init(location:2,length:0)); text.insertToken(.now)
        #expect(SpeechInlineDocument.pieces(text.attributedString()).map(\.token) == [nil,.now,nil])
        text.undoManager?.undo(); #expect(text.string == "开始结束")
        text.undoManager?.redo(); #expect(SpeechInlineDocument.pieces(text.attributedString())[1].token == .now)
        text.breakUndoCoalescing(); text.undoManager?.removeAllActions()
        text.setSelectedRange(.init(location:2,length:1)); text.insertToken(.event)
        #expect(SpeechInlineDocument.pieces(text.attributedString())[1].token == .event)
        text.undoManager?.undo()
        #expect(SpeechInlineDocument.pieces(text.attributedString())[1].token == .now)
        text.undoManager?.redo()
        #expect(SpeechInlineDocument.pieces(text.attributedString())[1].token == .event)
        text.setMarkedText("拼音", selectedRange: .init(location:2,length:0), replacementRange: .init(location:text.string.utf16.count,length:0))
        #expect(text.hasMarkedText())
        text.unmarkText(); #expect(text.string.contains("拼音"))
    }
    @Test func equivalentRecreatedPiecesDoNotDirtyDraft() {
        let original = SpeechTemplate.standard(.schedule,chinese:true)
        var draft = SpeechEditingDraft(template:original,rule:.init())
        draft.template.pieces = SpeechInlineDocument.pieces(SpeechInlineDocument.attributed(original.pieces,copy:copy))
        #expect(!draft.dirty)
        draft.template.pieces.append(.words("提醒")); #expect(draft.dirty)
    }
    @Test func legacyMigrationBackupAndCorruptV2Protection() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString), suite = "speech224-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        var legacy = SpeechConfiguration(); legacy.version = 1; legacy.templates["schedule"] = .standard(.schedule,chinese:true)
        let bytes = try JSONEncoder().encode(legacy), v1 = root.appendingPathComponent("speech-settings-v1.json"), v2 = root.appendingPathComponent("speech-settings-v2.json")
        try bytes.write(to:v1)
        let store = SpeechConfigurationStore(directory:root,defaults:defaults)
        #expect(store.value.version == 3 && store.value.templates == legacy.templates)
        #expect(!FileManager.default.fileExists(atPath:v2.path))
        var next = store.value; next.templates["schedule"] = .init(kind:.schedule,pieces:[.words("纯文字")]); try store.save(next)
        #expect(try Data(contentsOf:v1) == bytes)
        #expect(try Data(contentsOf:root.appendingPathComponent("before-speech-0224/speech-settings-v1.json")) == bytes)
        #expect(SpeechConfigurationStore(directory:root,defaults:defaults).value == next)
        try Data("broken".utf8).write(to:v2)
        // Without a newer v3, a corrupt v2 must still block migration.
        try FileManager.default.removeItem(at: root.appendingPathComponent("speech-settings-v3.json"))
        let broken = SpeechConfigurationStore(directory:root,defaults:defaults)
        #expect(throws: (any Error).self) { try broken.save(next) }
        #expect(try String(contentsOf:v2,encoding:.utf8) == "broken")
    }
    @Test func multiProviderSaveDoesNotSelectOrReadSecrets() throws {
        let suite = "speech224-\(UUID())", defaults = try #require(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let key = Key224(), speech = CompanionSpeech(defaults:defaults,credentials:key)
        for provider in APIProvider.allCases { #expect(speech.saveAPI(provider:provider,address:provider.endpoint,key:"fixture",consent:true,copy:copy)) }
        #expect(speech.provider == .bailian && speech.configuredProviders.count == 2 && key.reads == 0)
        #expect(Set(speech.combinedVoiceChoices.compactMap(\.group)).count == 2)
        let mini = try #require(speech.combinedVoiceChoices.first { $0.value.hasPrefix("minimax:") })
        speech.combinedVoice = mini.value; #expect(speech.provider == .minimax)
        let bailian = try #require(speech.combinedVoiceChoices.first { $0.value.hasPrefix("bailian:") })
        speech.combinedVoice = bailian.value; #expect(speech.provider == .bailian && key.reads == 0)
        let original = speech.configuration.value; key.fail = true
        #expect(!speech.saveAPI(provider:.minimax,address:APIProvider.minimax.endpoint,key:"fixture",consent:true,copy:copy))
        #expect(speech.configuration.value == original)
    }
    @Test func statusIsolationAndLateResponse() async throws {
        let suite = "speech224-\(UUID())", defaults = try #require(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let key = Key224(), api = API224(), speech = CompanionSpeech(defaults:defaults,credentials:key,cloud:api,player:Audio224())
        defer { speech.stop() }
        for provider in APIProvider.allCases { _ = speech.saveAPI(provider:provider,address:provider.endpoint,key:"",consent:true,copy:copy) }
        speech.selectSource(.bailian); speech.testConnection(copy:copy)
        try await Task.sleep(for:.milliseconds(120)); #expect(speech.apiStatus.phase == .ready)
        let b = speech.combinedVoice
        speech.combinedVoice = try #require(speech.combinedVoiceChoices.first { $0.value.hasPrefix("minimax:") }).value
        #expect(speech.apiStatus.phase == .unknown)
        speech.testConnection(copy:copy); try await Task.sleep(for:.milliseconds(10))
        speech.combinedVoice = b
        try await Task.sleep(for:.milliseconds(120))
        #expect(speech.provider == .bailian && speech.apiStatus.phase == .ready)
        speech.combinedVoice = try #require(speech.combinedVoiceChoices.first { $0.value.hasPrefix("minimax:") }).value
        #expect(speech.apiStatus.phase == .unknown)
    }
    @Test func freeTextSkipsUnusedEventTranslation() async throws {
        let suite = "speech224-\(UUID())", defaults = try #require(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let translator = Translation224(), api = API224(), audio = Audio224()
        let speech = CompanionSpeech(defaults:defaults,credentials:Key224(),cloud:api,player:audio,translator:translator)
        defer { speech.stop() }
        speech.selectSource(.bailian,consent:true)
        speech.speakTemplate(.init(kind:.schedule,pieces:[.words("请喝水。")]),values:[:],copy:copy,audition:true)
        try await Task.sleep(for:.milliseconds(150))
        #expect(translator.inputs == ["请喝水。"])
        #expect(await api.texts == ["请喝水。"])
        #expect(audio.count == 1)
    }
    @Test func mouseDecorationAndKeyboardRestoration() throws {
        let w = NSWindow(contentRect:.init(x:0,y:0,width:300,height:100),styleMask:[.titled],backing:.buffered,defer:false)
        w.isReleasedWhenClosed = false; defer { w.close(); SettingsInputFocus.setKeyboard(true) }
        let slider = SettingsPercentSlider(frame:.init(x:0,y:0,width:240,height:24)), disclosure = SettingsDisclosureControl(frame:.init(x:0,y:40,width:28,height:28))
        w.contentView?.addSubview(slider); w.contentView?.addSubview(disclosure)
        SettingsInputFocus.setKeyboard(false)
        #expect(slider.focusRingType == .none && disclosure.focusRingType == .none)
        w.makeFirstResponder(slider); #expect(slider.focusRingType == .none)
        SettingsInputFocus.setKeyboard(true)
        #expect(slider.focusRingType == .default && disclosure.focusRingType == .default)
        #expect(type(of: slider.cell!) == NSSliderCell.self)
    }
    @Test func sourceAndLanguageShareLeftEdge() async throws {
        let suite = "speech224-\(UUID())", defaults = try #require(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        let speech = CompanionSpeech(defaults:defaults,credentials:Key224())
        let w = NSWindow(contentRect:.init(x:100,y:100,width:550,height:400),styleMask:[.titled],backing:.buffered,defer:false)
        w.isReleasedWhenClosed = false; defer { w.close() }
        w.contentView = NSHostingView(rootView:CloudSpeechControls(speech:speech,copy:copy).environment(\.settingsPickerWidth,194).padding(16).frame(width:550,height:400))
        w.makeKeyAndOrderFront(nil); try await Task.sleep(for:.milliseconds(120))
        func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
        let root = try #require(w.contentView), pickers = all(root).compactMap { $0 as? SettingsPopUpButton }
        let source = try #require(pickers.first { $0.cell?.accessibilityLabel() == "语音来源" })
        let language = try #require(pickers.first { $0.cell?.accessibilityLabel() == "播报语言" })
        #expect(abs(source.convert(source.bounds,to:root).minX-language.convert(language.bounds,to:root).minX) < 1)
        #expect(abs(language.convert(language.bounds,to:root).maxX-534) < 1)
    }
}
