import Foundation

/// Double opt-in: an isolated QA bundle and an explicit fixture flag.
/// These fixtures never contact a provider or access the Keychain.
enum VoiceCloneQA {
    static var enabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "QuotaSecretaryPreview") as? Bool == true && Bundle.main.object(forInfoDictionaryKey: "QuotaVoiceCloneMock") as? Bool == true
    }
}
struct VoiceCloneQAService: VoiceCloningServicing {
    func create(_ voice: PersonalVoice, audio: Data, endpoint: String, key: String, phase: @escaping @Sendable (VoiceClonePhase) async -> Void) async throws -> PersonalVoice {
        guard VoiceCloneQA.enabled else { throw VoiceCloneError.unsafe }
        await phase(.uploading); try await Task.sleep(for: .milliseconds(350)); await phase(.creating)
        var result = voice; result.remoteID = "qa-only-" + voice.operationName; result.state = .created; return result
    }
    func find(_ voice: PersonalVoice, endpoint: String, key: String) async throws -> PersonalVoice {
        guard VoiceCloneQA.enabled else { throw VoiceCloneError.unsafe }; var result = voice; result.state = .created; return result
    }
    func delete(_ voice: PersonalVoice, endpoint: String, key: String) async throws { guard VoiceCloneQA.enabled else { throw VoiceCloneError.unsafe } }
}
struct VoiceCloneQASynth: CloudSpeechSynthesizing {
    func synthesize(text: String, language: SpeechLanguage, voice: String, key: String) async throws -> Data {
        guard VoiceCloneQA.enabled else { throw VoiceCloneError.unsafe }; return Data([0])
    }
}
@MainActor final class VoiceCloneQAPlayer: CloudAudioPlaying {
    func play(_ data: Data, rate: Double, volume: Double) throws {}
    func stop() {}
}
