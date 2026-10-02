import AppKit
import SwiftUI
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@MainActor private final class TestTranslation215: SpeechTranslating {
    var delay: Duration = .milliseconds(1)
    var fail = false
    var loseTokens = false
    var inputs: [String] = []
    func translate(_ text: String, to target: SpeechLanguage) async throws -> String {
        inputs.append(text)
        await Task.detached { [delay] in try? await Task.sleep(for: delay) }.value
        if fail { throw SpeechConfigError.translationUnavailable }
        return loseTokens ? "missing required information" : text.replacingOccurrences(of: "整理资料", with: "Organize documents")
    }
    func cancel() {}
}
@MainActor private final class TestKey215: SpeechCredentials {
    var reads = 0; var writes = 0
    func read() throws -> String { reads += 1; return "fixture-only" }
    func save(_ value: String) throws { writes += 1 }
}
private actor TestAPI215: CloudSpeechSynthesizing {
    var texts: [String] = []
    func synthesize(text: String, language: SpeechLanguage, voice: String, key: String) async throws -> Data {
        texts.append(text); return Data([1])
    }
}
@MainActor private final class TestAudio215: CloudAudioPlaying {
    var plays = 0
    func play(_ data: Data, rate: Double, volume: Double) throws { plays += 1 }
    func stop() {}
}

@Suite(.serialized) @MainActor struct Speech215Tests {
    @Test func officialEndpointsOnly() throws {
        #expect(APIProvider.identify(APIProvider.bailian.endpoint) == .bailian)
        #expect(APIProvider.identify(APIProvider.minimax.endpoint) == .minimax)
        for address in ["http://api.minimax.cn/v1/t2a_v2", "https://api.minimax.cn.attacker.test/v1/t2a_v2", "https://key@api.minimax.cn/v1/t2a_v2", "https://api.minimax.cn/v1/t2a_v2?forward=1", "https://api.minimax.cn:443/v1/t2a_v2", "https://other.test/tts"] {
            #expect(APIProvider.identify(address) == nil)
        }
    }
    @Test func miniMaxProtocolAndStrictAudio() throws {
        for language in SpeechLanguage.allCases {
            let request = try MiniMaxSpeechClient.request(endpoint: APIProvider.minimax.endpoint, text: language.sample, language: language, voice: MiniMaxSpeechClient.voices(language)[0].id, key: "fixture")
            let json = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            #expect(json["model"] as? String == "speech-2.8-turbo")
            #expect(json["language_boost"] as? String == language.rawValue)
            #expect(request.timeoutInterval == 10 && request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture")
        }
        #expect(try MiniMaxSpeechClient.decode(Data(#"{"base_resp":{"status_code":0},"data":{"audio":"0102af"}}"#.utf8)) == Data([1,2,175]))
        for json in [#"{"base_resp":{"status_code":1004}}"#, #"{"base_resp":{"status_code":1008}}"#, #"{"base_resp":{"status_code":0},"data":{"audio":"xx"}}"#, #"{"base_resp":{"status_code":0},"data":{"audio":"a"}}"#] {
            #expect(throws: (any Error).self) { try MiniMaxSpeechClient.decode(Data(json.utf8)) }
        }
    }
    @Test func templatesProtectTokensAndAllowReordering() throws {
        var template = SpeechTemplate.standard(.schedule, chinese: true)
        try template.validate()
        template.pieces.reverse(); try template.validate()
        template.pieces.append(.words("请喝水。")); try template.validate()
        template.pieces.removeAll { $0.token == .now }
        try template.validate() // 0.2.24: fields may be omitted.
        var quota = SpeechTemplate.standard(.quota, chinese: true)
        quota.pieces.append(.value(.percent))
        try quota.validate() // 0.2.24: repeated fields are intentional.
        #expect(try QuotaSpeechRule.parse("0,10，15 10、100") == [100,15,10,0])
        for invalid in ["", "-1", "101", "2.5", "１０", "10%"] {
            #expect(throws: (any Error).self) { try QuotaSpeechRule.parse(invalid) }
        }
    }
    @Test func persistenceBackupAndFailureAreAtomic() throws {
        let suite = "speech215-\(UUID())", root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        defaults.set(true, forKey: "speechEnabled")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = Data("untouched fixture".utf8)
        try fixture.write(to: root.appendingPathComponent("secretary-v1.json"))
        let store = SpeechConfigurationStore(directory: root, defaults: defaults)
        #expect(store.value.quota.delivery == .both && store.value.quota.thresholds == [30,15,5])
        var next = store.value; next.provider = .minimax; next.quota.thresholds = [10,0]
        next.templates["schedule"] = .standard(.schedule, chinese: true)
        try store.save(next)
        let restored = SpeechConfigurationStore(directory: root, defaults: defaults)
        #expect(restored.value == next)
        #expect(try Data(contentsOf: root.appendingPathComponent("before-speech-0215/secretary-v1.json")) == fixture)
        #expect(try Data(contentsOf: root.appendingPathComponent("secretary-v1.json")) == fixture)
        var bad = next; bad.quota.thresholds = [-1]
        #expect(throws: (any Error).self) { try store.save(bad) }
        #expect(store.value == next)
        let blocked = root.appendingPathComponent("blocked"); try fixture.write(to: blocked)
        let broken = SpeechConfigurationStore(directory: blocked, defaults: defaults)
        let original = broken.value
        #expect(throws: (any Error).self) { try broken.save(next) }
        #expect(broken.value == original)
    }
    @Test func translationCancelFailureAndExactTokens() async throws {
        for mode in ["success", "stop", "language", "timeout", "failure", "tokens", "expired"] {
            let suite = "speech215-\(UUID())", defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let translator = TestTranslation215(), api = TestAPI215(), key = TestKey215(), audio = TestAudio215()
            translator.delay = .milliseconds(20); translator.fail = mode == "failure"; translator.loseTokens = mode == "tokens"
            let speech = CompanionSpeech(defaults: defaults, credentials: key, cloud: api, player: audio, translator: translator, translationTimeout: mode == "timeout" ? .milliseconds(5) : .seconds(5))
            defer { speech.stop() }
            speech.selectSource(.bailian, consent: true); speech.cloudLanguage = .english
            speech.speakTemplate(.standard(.schedule, chinese: false), values: [.now: "13:02", .start: "13:00", .end: "17:30", .event: "整理资料"], copy: Copybook(language: .english), deadline: Date().addingTimeInterval(mode == "expired" ? 0.01 : 30))
            try await Task.sleep(for: .milliseconds(5))
            if mode == "stop" { speech.stop() }
            if mode == "language" { speech.cloudLanguage = .japanese }
            try await Task.sleep(for: .milliseconds(130))
            for _ in 0..<100 where speech.cloudBusy { try await Task.sleep(for: .milliseconds(20)) }
            let sent = await api.texts
            if mode == "success" {
                #expect(sent == ["It is now 13:02. From 13:00 to 17:30, Organize documents."])
                #expect(audio.plays == 1 && key.reads == 1)
            } else { #expect(sent.isEmpty && audio.plays == 0 && key.reads == 0) }
            #expect(speech.dialog == nil && !speech.cloudBusy)
        }
    }
    @Test func providerIsolationAndDraftCancellation() throws {
        let suite = "speech215-\(UUID())", root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let key = TestKey215(), api = TestAPI215(), copy = Copybook(language: .zhHans)
        let speech = CompanionSpeech(defaults: defaults, directory: root, credentials: key, cloud: api, player: TestAudio215())
        #expect(speech.saveAPI(provider: .minimax, address: APIProvider.minimax.endpoint, key: "fixture", consent: true, copy: copy))
        speech.cloudLanguage = .japanese; speech.combinedVoice = "minimax:" + MiniMaxSpeechClient.voices(.japanese)[1].id
        #expect(speech.saveAPI(provider: .bailian, address: APIProvider.bailian.endpoint, key: "", consent: true, copy: copy))
        speech.combinedVoice = "bailian:" + BailianVoice.available(.japanese)[0].id
        #expect(speech.saveAPI(provider: .minimax, address: APIProvider.minimax.endpoint, key: "", consent: true, copy: copy))
        speech.combinedVoice = "minimax:" + MiniMaxSpeechClient.voices(.japanese)[1].id
        #expect(speech.cloudVoice == MiniMaxSpeechClient.voices(.japanese)[1].id && key.reads == 0 && key.writes == 1)
        speech.editTemplate(.quota, copy: copy)
        #expect(speech.draft?.dirty == false)
        #expect(speech.discardDraft(copy: copy))
        #expect(speech.configuration.value.templates.isEmpty)
        speech.editTemplate(.quota, copy: copy); speech.draft?.thresholdText = "0,10,10"
        speech.saveDraft(copy: copy)
        #expect(speech.configuration.value.quota.thresholds == [10,0] && speech.draft == nil)
        let restored = CompanionSpeech(defaults: defaults, directory: root, credentials: key, cloud: api, player: TestAudio215())
        #expect(restored.provider == .minimax && restored.cloudVoice == speech.cloudVoice)
    }
    @Test func nativePickerHitAreaAndSizing() throws {
        let popup = SettingsPopUpButton(frame: NSRect(x: 0,y: 0,width: 220,height: 28), pullsDown: false)
        popup.addItems(withTitles: ["One", "Longer option"])
        for x in [2.0, 40, 110, 205, 218] { #expect(popup.hitTest(NSPoint(x: x,y: 14)) === popup) }
        #expect(popup.acceptsFirstResponder)
        #expect(SettingsPicker<String>.measuredWidth(["abc"]) < SettingsPicker<String>.measuredWidth(["A much longer option"]))
        #expect(SettingsPicker<String>.measuredWidth([String(repeating: "中", count: 100)]) == 350)
    }
}
