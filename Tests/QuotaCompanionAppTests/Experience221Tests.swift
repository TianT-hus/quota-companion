import AppKit
import SwiftUI
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@MainActor private final class Key221: SpeechCredentials {
    var reads = 0
    func read() throws -> String { reads += 1; return "isolated-fixture" }
    func save(_ value: String) throws {}
}
private actor API221: CloudSpeechSynthesizing {
    var texts: [String] = []
    let delay: Duration
    let failure: CloudSpeechError?
    init(delay: Duration = .milliseconds(10), failure: CloudSpeechError? = nil) { self.delay = delay; self.failure = failure }
    func synthesize(text: String, language: SpeechLanguage, voice: String, key: String) async throws -> Data {
        texts.append(text)
        await Task.detached { try? await Task.sleep(for: self.delay) }.value
        if let failure { throw failure }
        return Data([1])
    }
}
@MainActor private final class Player221: CloudAudioPlaying {
    var plays = 0
    func play(_ data: Data, rate: Double, volume: Double) throws { plays += 1 }
    func stop() {}
}
@MainActor private final class Translation221: SpeechTranslating {
    var fail = false
    func translate(_ text: String, to target: SpeechLanguage) async throws -> String {
        if fail { throw SpeechConfigError.translationUnavailable }
        return text
    }
    func cancel() {}
}

@Suite(.serialized) @MainActor struct Experience221Tests {
    @Test func spokenTimesAreStructuredAndTwentyFourHour() {
        let cases = [0: "零点", 780: "十三点", 1050: "十七点半", 785: "十三点零五分", 790: "十三点十分", 1439: "二十三点五十九分", 1440: "次日零点"]
        for (minute, expected) in cases { #expect(SpokenTime.format(minute, language: .chinese) == expected) }
        #expect(SpokenTime.format(780, language: .english) == "13:00")
        #expect(SpokenTime.format(1050, language: .japanese) == "17時30分")
        var template = SpeechTemplate.standard(.schedule, chinese: true)
        template.pieces.append(.words(" 原文13:00保持不变"))
        let example = template.example(Copybook(language: .zhHans), language: .chinese)
        #expect(example.contains("十三点") && example.contains("十七点半") && example.hasSuffix("原文13:00保持不变"))
        #expect(SettingsPage.allCases == [.day, .todos, .appearance, .speech, .general, .advanced])
    }
    @Test func cropCountsShareActualDetailGeometry() {
        let bounds = CGRect(x: 0, y: 0, width: 568, height: 280)
        let single = CropGeometry.frame(in: bounds, doubleRow: false), dual = CropGeometry.frame(in: bounds, doubleRow: true)
        #expect(single == dual)
        #expect(abs(single.width / single.height - CompactHoverMetrics.size.width / CompactHoverMetrics.size.height) < 0.00001)
        #expect(bounds.contains(single))
    }
    @Test func statusLightSupportsKeyboardAndDisabledState() throws {
        let window = NSWindow(contentRect: .init(x:0,y:0,width:180,height:80),styleMask:[.titled],backing:.buffered,defer:false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let button = SpeechStatusButton(frame: .init(x:20,y:20,width:24,height:28))
        let target = StatusTarget221(); button.target = target; button.action = #selector(StatusTarget221.activate(_:))
        window.contentView?.addSubview(button); window.orderFront(nil); window.makeFirstResponder(button)
        #expect(window.firstResponder === button && button.canBecomeKeyView)
        for key: UInt16 in [49,36] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: key))
            button.keyDown(with: event)
        }
        #expect(target.calls == 2)
        button.isEnabled = false
        let space = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
        // A testing/passive light remains focusable so its status is readable, but cannot test again.
        button.keyDown(with: space); #expect(target.calls == 2 && button.acceptsFirstResponder)
    }
    @Test func previewDraftSavedAndInvalidNeverWritesOrUsesRealData() async throws {
        let suite = "speech221-preview-\(UUID())", defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = API221(), audio = Player221()
        let speech = CompanionSpeech(defaults: defaults, credentials: Key221(), cloud: api, player: audio, translator: Translation221())
        defer { speech.stop() }
        speech.selectSource(.bailian, consent: true)
        let copy = Copybook(language: .zhHans), before = speech.configuration.value
        var draft = SpeechTemplate.standard(.schedule, chinese: true)
        draft.pieces.reverse(); draft.pieces.append(.words(" 自定义13:00"))
        speech.draft = SpeechEditingDraft(template: draft, rule: before.quota)
        speech.preview(copy: copy)
        try await settle(speech)
        let first = await api.texts
        #expect(first.count == 1 && first[0].hasSuffix("自定义13:00") && first[0].contains("十七点半"))
        #expect(speech.configuration.value == before && speech.draft?.template == draft)
        speech.draft = nil; speech.previewSaved(.quota, copy: copy); try await settle(speech)
        let second = await api.texts
        #expect(second.count == 2 && second[1].contains("百分之10") && audio.plays == 2)
        draft.pieces = [.words(" ")] // Free-form templates reject empty content, not missing fields.
        speech.previewTemplate(draft, copy: copy); try await settle(speech)
        #expect(await api.texts.count == 2 && speech.dialog != nil && speech.configuration.value == before)
    }
    @Test func explicitTestsStatusCancellationAndRestart() async throws {
        for mode in ["success", "failure", "timeout", "stop", "source", "config", "language"] {
            let suite = "speech221-status-\(UUID())", defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let api = API221(delay: .milliseconds(80), failure: mode == "failure" ? .authorization : nil), key = Key221(), player = Player221()
            let speech = CompanionSpeech(defaults: defaults, credentials: key, cloud: api, player: player, timeout: mode == "timeout" ? .milliseconds(10) : .seconds(10))
            defer { speech.stop() }
            let copy = Copybook(language: .zhHans)
            speech.selectSource(.bailian, consent: true)
            _ = speech.status(copy: copy).description(copy)
            #expect(await api.texts.isEmpty && key.reads == 0 && speech.apiStatus.phase == .unknown)
            speech.testConnection(copy: copy); speech.testConnection(copy: copy)
            #expect(speech.apiStatus.phase == .testing)
            try await Task.sleep(for: .milliseconds(5))
            if mode == "stop" { speech.stop() }
            if mode == "source" { speech.selectSource(.local) }
            if mode == "config" { #expect(speech.saveAPI(provider: .bailian, address: APIProvider.bailian.endpoint, key: "fixture", consent: true, copy: copy)) }
            if mode == "language" { speech.cloudLanguage = .japanese }
            try await Task.sleep(for: .milliseconds(150))
            let phase = speech.apiStatus.phase
            #expect(phase == (mode == "success" ? .ready : ["failure", "timeout"].contains(mode) ? .failed : .unknown))
            #expect(await api.texts.count == 1 && player.plays == 0 && speech.dialog == nil && !speech.cloudBusy)
            if mode == "success" { #expect(speech.apiStatus.succeededAt != nil) }
            let restart = CompanionSpeech(defaults: defaults, credentials: key, cloud: api, player: player)
            #expect(restart.apiStatus.phase == .unknown)
        }
    }
    @Test func draftTestsAndTranslationFailuresDoNotPolluteAPIState() async throws {
        let suite = "speech221-isolation-\(UUID())", defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let api = API221(), translator = Translation221(), player = Player221()
        let speech = CompanionSpeech(defaults: defaults, credentials: Key221(), cloud: api, player: player, translator: translator)
        defer { speech.stop() }
        let copy = Copybook(language: .zhHans)
        speech.selectSource(.bailian, consent: true); speech.testConnection(copy: copy); try await settle(speech)
        let savedStatus = speech.apiStatus
        var draftStatus = SpeechRuntimeStatus.unknown
        speech.testAPI(provider: .minimax, address: APIProvider.minimax.endpoint, key: "fixture", copy: copy) { draftStatus = $0 }
        try await settle(speech)
        #expect(draftStatus.phase == .ready && speech.apiStatus == savedStatus && speech.provider == .bailian && player.plays == 0)
        translator.fail = true
        speech.previewSaved(.schedule, copy: copy); try await settle(speech)
        #expect(speech.apiStatus == savedStatus && speech.status(copy: copy).phase == .failed && speech.speechProblem != nil)
        #expect(await api.texts.count == 2)
        speech.dialog = nil
        speech.testConnection(copy: copy); try await settle(speech)
        #expect(speech.apiStatus.phase == .ready && speech.status(copy: copy).phase == .failed && speech.dialog == nil)
    }
    private func settle(_ speech: CompanionSpeech) async throws {
        for _ in 0..<200 { if !speech.cloudBusy { return }; try await Task.sleep(for: .milliseconds(10)) }
        #expect(!speech.cloudBusy)
    }
    @Test func native221Evidence() async throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_APPEARANCE_0221_PREVIEW"] else { return }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suite = "appearance221-preview-\(UUID())", directory = URL.temporaryDirectory.appendingPathComponent(suite)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let model = CompanionModel(defaults: defaults, store: .init(directory: directory)); model.language = .zhHans
        defer { model.secretary.stop(); model.reminders.stop(); model.speech.stop() }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let image = try #require(NSImage(contentsOf: root.appendingPathComponent("Sources/QuotaCompanionApp/Resources/fantasy-cat-base.png")))
        let original = model.customAppearance
        let draft = BackgroundDraft(image: image, prepared: nil, composition: .init())
        try await render(BackgroundEditor(model: model, draft: draft), to: output.appendingPathComponent("crop-rounded.png"), width: 616, height: 510)
        try await render(BackgroundEditor(model: model, draft: draft, startsWithPreview: true), to: output.appendingPathComponent("crop-preview.png"), width: 616, height: 510)
        for count in [1,2] {
            try await render(CompanionRootView(model: model, previewDate: .init(timeIntervalSince1970: 1790606580), sampleQuotaCount: count, sampleScale: 3, previewBackground: .init(image: image, appearances: .standard), previewComposition: .init()), to: output.appendingPathComponent("detail-\(count).png"), width: 450, height: 240)
        }
        for contrast in [false,true] {
            try await render(SettingsSection(title: "额度通用设置") { AppearanceColorControls(model: model) }.padding(24).environment(\.settingsPickerWidth, 340).environment(\.companionAccessibility, .init(reduceMotion: contrast, reduceTransparency: contrast, contrast: contrast ? .increased : .standard)), to: output.appendingPathComponent("swatches-\(contrast ? "contrast" : "normal").png"), width: 615, height: 400)
        }
        let copy = model.copy
        try await render(HStack(spacing: 20) {
            ForEach(0..<4) { i in
                let status: SpeechRuntimeStatus = [ .unknown, .testing, .ready("模拟成功", at: .init(timeIntervalSince1970: 1790606580)), .failed("模拟鉴权失败") ][i]
                VStack { SpeechStatusLight(status: status, title: "API", copy: copy, action: {}); Text(["未验证", "测试中", "成功", "失败"][i]) }
            }
        }.padding(20), to: output.appendingPathComponent("status-mock-states.png"), width: 460, height: 110)
        let navigation = SettingsNavigation(); navigation.visible = true; navigation.page = .speech
        try await render(SettingsView(model: model, navigation: navigation), to: output.appendingPathComponent("speech.png"), width:780,height:620)
        model.speech.editTemplate(.schedule, copy: copy)
        try await render(SpeechPreferences(model: model, speech: model.speech, group: .switches).padding(24), to: output.appendingPathComponent("template-example.png"), width:610,height:690)
        #expect(model.customAppearance == original && !model.codexFollow.enabled && !model.reminders.enabled)
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

@MainActor private final class StatusTarget221: NSObject {
    var calls = 0
    @objc func activate(_ sender: NSButton) { calls += 1 }
}
