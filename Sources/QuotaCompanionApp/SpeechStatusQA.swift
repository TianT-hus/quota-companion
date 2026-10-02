import Foundation

enum SpeechStatusQA {
    static var enabled: Bool {
        Bundle.main.object(forInfoDictionaryKey:"QuotaSecretaryPreview") as? Bool == true && Bundle.main.object(forInfoDictionaryKey:"QuotaSpeechStatusMock") as? Bool == true
    }
}
@MainActor final class StatusQAKey: SpeechCredentials {
    func read() throws -> String { guard SpeechStatusQA.enabled else { throw CloudSpeechError.missingKey }; return "isolated-status-fixture" }
    func save(_ value:String) throws { guard SpeechStatusQA.enabled else { throw CloudSpeechError.missingKey } }
}
actor StatusQAService: CloudSpeechSynthesizing {
    private var calls=0
    func synthesize(text:String,language:SpeechLanguage,voice:String,key:String) async throws -> Data {
        guard SpeechStatusQA.enabled else { throw CloudSpeechError.network }
        calls += 1; let call=calls
        try await Task.sleep(for:.seconds(1))
        if call % 2 == 0 { throw CloudSpeechError.authorization }
        return Data([0])
    }
}
