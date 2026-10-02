import Foundation
import Testing
@testable import QuotaCompanionApp

@MainActor private final class FakeSpeechKey: SpeechCredentials {
    var reads = 0
    func read() throws -> String { reads += 1; return "test-only-placeholder" }
    func save(_ value: String) throws {}
}
private actor FakeSpeechService: CloudSpeechSynthesizing {
    var calls = 0
    let delay: Duration
    let failure: CloudSpeechError?
    init(delay: Duration = .milliseconds(5), failure: CloudSpeechError? = nil) { self.delay = delay; self.failure = failure }
    func synthesize(text: String, language: SpeechLanguage, voice: String, key: String) async throws -> Data {
        calls += 1
        // Deliberately ignore parent cancellation, simulating a late transport response.
        await Task.detached { try? await Task.sleep(for: self.delay) }.value
        if let failure { throw failure }
        return Data([1, 2, 3])
    }
}
@MainActor private final class FakeSpeechPlayer: CloudAudioPlaying {
    var plays = 0
    func play(_ data: Data, rate: Double, volume: Double) throws { plays += 1 }
    func stop() {}
}
@Suite(.serialized) @MainActor struct CloudSpeechTests {
    @Test func requestAndAudioSecurity() throws {
        let request = try BailianSpeechClient.request(text: "测试", language: .japanese, voice: "Ono Anna", key: "fixture")
        #expect(request.url == BailianSpeechClient.endpoint && request.httpMethod == "POST")
        let json = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        #expect(json["model"] as? String == "qwen3-tts-flash")
        #expect((json["input"] as? [String: String])?["text"] == "测试")
        #expect(throws: (any Error).self) { try BailianSpeechClient.request(text: String(repeating: "a", count: 601), language: .chinese, voice: "Cherry", key: "fixture") }
        #expect(try BailianSpeechClient.audioURL("http://dashscope-result-bj.oss-cn-beijing.aliyuncs.com/a?signature=fixture").scheme == "https")
        #expect(throws: (any Error).self) { try BailianSpeechClient.audioURL("https://untrusted.example/a") }
        for code in [401,403,402,429,500] {
            let response = HTTPURLResponse(url: BailianSpeechClient.endpoint, statusCode: code, httpVersion: nil, headerFields: nil)!
            #expect(throws: (any Error).self) { try BailianSpeechClient.check(response) }
        }
    }
    @Test func consentAndLanguagePersistence() throws {
        let suite = "cloud-test-\(UUID())", key = FakeSpeechKey()
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let speech = CompanionSpeech(defaults: defaults, credentials: key, cloud: FakeSpeechService(), player: FakeSpeechPlayer())
        #expect(speech.source == .local && key.reads == 0)
        speech.selectSource(.bailian); #expect(speech.source == .local)
        speech.selectSource(.bailian, consent: true)
        speech.cloudVoice = "Ethan"; speech.cloudLanguage = .japanese; speech.cloudVoice = "Ono Anna"
        let restored = CompanionSpeech(defaults: defaults, credentials: key, cloud: FakeSpeechService(), player: FakeSpeechPlayer())
        #expect(restored.source == .bailian && restored.cloudVoice == "Ono Anna")
        restored.cloudLanguage = .chinese; #expect(restored.cloudVoice == "Ethan" && key.reads == 0)
    }
    @Test func successCancellationTimeoutAndErrors() async throws {
        for mode in ["success", "stop", "source", "disable", "expired", "timeout", "auth", "test"] {
            let suite = "cloud-test-\(UUID())"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let player = FakeSpeechPlayer(), key = FakeSpeechKey()
            let service = FakeSpeechService(delay: .milliseconds(70), failure: mode == "auth" ? .authorization : nil)
            let speech = CompanionSpeech(defaults: defaults, credentials: key, cloud: service, player: player, timeout: mode == "timeout" ? .milliseconds(15) : .seconds(10))
            defer { speech.stop() }
            speech.selectSource(.bailian, consent: true)
            let copy = Copybook(language: .zhHans)
            if mode == "test" { speech.testConnection(copy: copy) }
            else { speech.speak("Fixed fixture", copy: copy, until: Date().addingTimeInterval(mode == "expired" ? 0.02 : 10)) }
            try await Task.sleep(for: .milliseconds(10))
            if mode == "stop" { speech.stop() }
            if mode == "source" { speech.selectSource(.local) }
            if mode == "disable" { speech.scheduleEnabled = false }
            try await Task.sleep(for: .milliseconds(130))
            #expect(player.plays == (mode == "success" ? 1 : 0))
            #expect(await service.calls == 1)
            #expect(!speech.cloudBusy)
            #expect(speech.dialog == nil)
            if mode == "auth" || mode == "timeout" { #expect(!speech.message.isEmpty) }
        }
    }
}
