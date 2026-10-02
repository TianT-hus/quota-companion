import AppKit
import AVFoundation
import Testing
@testable import QuotaCompanionApp

@MainActor private final class Key225: SpeechCredentials {
    var reads = 0
    var denied = false
    func read() throws -> String { reads += 1; if denied { throw CloudSpeechError.keychainPermission }; return "synthetic-test-key" }
    func save(_ value: String) throws {}
}
private actor Clone225: VoiceCloningServicing {
    var creates = 0, checks = 0, deletes = 0
    let delay: Duration
    let fails: Bool
    init(delay: Duration = .zero, fails: Bool = false) { self.delay = delay; self.fails = fails }
    func create(_ voice: PersonalVoice, audio: Data, endpoint: String, key: String, phase: @escaping @Sendable (VoiceClonePhase) async -> Void) async throws -> PersonalVoice {
        creates += 1; await phase(.creating); try? await Task.sleep(for: delay)
        if fails { throw CloudSpeechError.timeout }
        var result = voice; result.remoteID = "remote-" + voice.operationName; result.state = .created; return result
    }
    func find(_ voice: PersonalVoice, endpoint: String, key: String) async throws -> PersonalVoice { checks += 1; var v = voice; v.remoteID = "remote-" + voice.operationName; v.state = .created; return v }
    func delete(_ voice: PersonalVoice, endpoint: String, key: String) async throws { deletes += 1; if fails { throw CloudSpeechError.network } }
}
private actor Synth225: CloudSpeechSynthesizing {
    var calls = 0
    var descriptors: [SpeechVoiceDescriptor] = []
    func synthesize(text: String, language: SpeechLanguage, voice: String, key: String) async throws -> Data { throw CloudSpeechError.response }
    func synthesize(text: String, language: SpeechLanguage, descriptor: SpeechVoiceDescriptor, key: String) async throws -> Data { calls += 1; descriptors.append(descriptor); return Data([1,2]) }
}
@MainActor private final class Play225: CloudAudioPlaying {
    var plays = 0
    func play(_ data: Data, rate: Double, volume: Double) throws { plays += 1 }
    func stop() {}
}
@MainActor private final class Fixture225 {
    let root = URL.temporaryDirectory.appendingPathComponent("voice225-" + UUID().uuidString)
    let suite = "voice225-" + UUID().uuidString
    let defaults: UserDefaults
    let key = Key225()
    let speech: CompanionSpeech
    let c = Copybook(language: .zhHans)
    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        speech = CompanionSpeech(defaults: defaults, directory: root, credentials: key)
        for p in APIProvider.allCases { #expect(speech.saveAPI(provider: p, address: p.endpoint, key: "", consent: true, copy: c)) }
    }
    func audio() throws -> PreparedVoiceAudio { let url = root.appendingPathComponent("mock.wav"); try Data([1,2,3]).write(to: url); return .init(url: url, duration: 16, bytes: 3, audibleSeconds: 16) }
    func voice(_ provider: APIProvider = .bailian) throws -> PersonalVoice {
        var v = PersonalVoice(provider: provider, name: "测试声音", revision: speech.configuration.value.credentialRevision(provider)); v.remoteID = "fixture-voice"; v.state = .created
        var config = speech.configuration.value; config.personalVoices = config.voiceLibrary + [v]; try speech.configuration.save(config); return v
    }
    func cleanup() { speech.stop(); defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
}

@Suite(.serialized) @MainActor struct PersonalVoice225Tests {
    @Test func deniedMicrophoneLeavesImportAvailableWithoutRecording() async {
        let recorder = VoiceRecorder(); recorder.permissionForTesting = { false }
        let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        recorder.start(url:url,copy:Copybook(language:.zhHans))
        while recorder.starting { await Task.yield() }
        #expect(!recorder.recording && recorder.error != nil)
        #expect(!FileManager.default.fileExists(atPath:url.path))
        recorder.cancel()
    }
    @Test func providerLimitsAndNames() throws {
        for tuple in [(APIProvider.bailian, 3.0, 60.0, 10), (.minimax,10.0,300.0,20)] {
            try VoiceAudioPreparation.validate(duration: tuple.1, bytes: tuple.3*1024*1024, provider: tuple.0)
            try VoiceAudioPreparation.validate(duration: tuple.2, bytes: 1, provider: tuple.0)
            for duration in [tuple.1-0.1,tuple.2+0.1,Double.nan] { #expect(throws: (any Error).self) { try VoiceAudioPreparation.validate(duration: duration, bytes: 1, provider: tuple.0) } }
            #expect(throws: (any Error).self) { try VoiceAudioPreparation.validate(duration: tuple.1, bytes: tuple.3*1024*1024+1, provider: tuple.0) }
        }
        #expect(PersonalVoice.validName(String(repeating: "👩🏽‍💻", count:30)))
        #expect(!PersonalVoice.validName(String(repeating:"字",count:31)))
        #expect(!PersonalVoice.validName(" \n"))
    }
    @Test func remoteIDsAndBoundModels() throws {
        let v = PersonalVoice(provider:.minimax,name:"我的声音",revision:"test")
        #expect(v.operationName.count == 16 && v.operationName.first == "z")
        #expect(v.operationName != PersonalVoice(provider:.minimax,name:"我的声音",revision:"test").operationName)
        let body = VoiceCloningClient.qwenBody(PersonalVoice(provider:.bailian,name:"a",revision:"test"),audio:Data([1,2]))
        let input = try #require(body["input"] as? [String:Any])
        #expect(body["model"] as? String == "qwen-voice-enrollment")
        #expect(input["target_model"] as? String == "qwen3-tts-vc-2026-01-22")
        #expect((input["audio"] as? [String:String])?["data"] == "data:audio/wav;base64,AQI=")
    }
    @Test func customVoiceCannotUseSystemModelOrForeignEndpoint() throws {
        let d = SpeechVoiceDescriptor(provider:.bailian,id:"cloned-voice",model:PersonalVoice.model(for:.bailian),personal:true)
        let request = try BailianSpeechClient.request(text:"虚构示例",language:.chinese,descriptor:d,key:"fixture")
        let json = try #require(JSONSerialization.jsonObject(with:request.httpBody!) as? [String:Any])
        #expect(json["model"] as? String == d.model)
        var wrong = d; wrong.model = "qwen3-tts-flash"
        #expect(throws: (any Error).self) { try BailianSpeechClient.request(text:"a",language:.chinese,descriptor:wrong,key:"fixture") }
        #expect(throws: (any Error).self) { try VoiceCloningClient.url(.minimax,endpoint:"https://example.com/v1/t2a_v2",path:"voice_clone") }
        #expect(throws: (any Error).self) { try VoiceCloningClient.url(.minimax,endpoint:APIProvider.bailian.endpoint,path:"voice_clone") }
    }
    @Test func v2MigrationPreservesConfigurationAndBackup() throws {
        let f = try Fixture225(); defer { f.cleanup() }
        try FileManager.default.removeItem(at:f.root.appendingPathComponent("speech-settings-v3.json"))
        var legacy = f.speech.configuration.value; legacy.version = 2; legacy.voices["bailian:Chinese"] = "Chelsie"; legacy.templates["custom"] = .init(kind:.schedule,pieces:[.words("我的自由文案")])
        let bytes = try JSONEncoder().encode(legacy), v2 = f.root.appendingPathComponent("speech-settings-v2.json")
        try bytes.write(to:v2)
        let store = SpeechConfigurationStore(directory:f.root,defaults:f.defaults)
        #expect(store.value.version == 3 && store.value.voices == legacy.voices && store.value.templates == legacy.templates)
        try store.save(store.value)
        #expect(try Data(contentsOf:v2) == bytes)
        #expect(try Data(contentsOf:f.root.appendingPathComponent("before-speech-0225/speech-settings-v2.json")) == bytes)
        #expect(SpeechConfigurationStore(directory:f.root,defaults:f.defaults).value == store.value)
    }
    @Test func corruptedV3AndDuplicateIDsCannotOverwrite() throws {
        let f = try Fixture225(); defer { f.cleanup() }
        let url = f.root.appendingPathComponent("speech-settings-v3.json")
        try Data("broken".utf8).write(to:url)
        let store = SpeechConfigurationStore(directory:f.root,defaults:f.defaults)
        #expect(throws: (any Error).self) { try store.save(SpeechConfiguration()) }
        #expect(try String(contentsOf:url,encoding:.utf8) == "broken")
        let v = PersonalVoice(provider:.bailian,name:"a",revision:"test")
        var config = SpeechConfiguration(); config.personalVoices = [v,v]
        try JSONEncoder().encode(config).write(to:url)
        let duplicate = SpeechConfigurationStore(directory:f.root,defaults:f.defaults)
        #expect(throws: (any Error).self) { try duplicate.save(SpeechConfiguration()) }
    }
    @Test func noConsentNoKeyNoNetworkAndDoubleClickCoalesced() async throws {
        let f = try Fixture225(); defer { f.cleanup() }
        let service = Clone225(delay:.milliseconds(40)), controller = PersonalVoiceController(speech:f.speech,directory:f.root,service:service,player:Play225())
        let a = try f.audio()
        controller.create(audio:a,provider:.bailian,name:"a",consent:false,copy:f.c)
        #expect(f.key.reads == 0 && !controller.busy)
        controller.create(audio:a,provider:.bailian,name:"a",consent:true,copy:f.c)
        controller.create(audio:a,provider:.bailian,name:"a",consent:true,copy:f.c)
        await controller.task?.value
        #expect(await service.creates == 1)
        #expect(controller.voices.count == 1 && controller.voices[0].state == .created)
        #expect(f.speech.source == .local)
    }
    @Test func permissionDenialDoesNotSubmitOrRetry() async throws {
        let f = try Fixture225(); defer { f.cleanup() }; f.key.denied = true
        let service = Clone225(), controller = PersonalVoiceController(speech:f.speech,directory:f.root,service:service,player:Play225())
        controller.create(audio:try f.audio(),provider:.bailian,name:"a",consent:true,copy:f.c); await controller.task?.value
        #expect(f.key.reads == 1 && controller.voices.isEmpty)
        #expect(await service.creates == 0)
    }
    @Test func timeoutPersistsPendingAndDoesNotRecreate() async throws {
        let f = try Fixture225(); defer { f.cleanup() }
        let service = Clone225(fails:true), controller = PersonalVoiceController(speech:f.speech,directory:f.root,service:service,player:Play225())
        let audio = try f.audio()
        controller.create(audio:audio,provider:.minimax,name:"a",consent:true,copy:f.c); await controller.task?.value
        #expect(controller.voices.first?.state == .pending)
        controller.create(audio:audio,provider:.minimax,name:"a",consent:true,copy:f.c); await controller.task?.value
        #expect(await service.creates == 1)
        let restored = PersonalVoiceController(speech:f.speech,directory:f.root,service:service,player:Play225())
        #expect(restored.voices.first?.state == .pending)
        restored.check(try #require(restored.voices.first),copy:f.c); await restored.task?.value
        #expect(restored.voices.first?.state == .created)
    }
    @Test func lateCreatedVoiceRetainedWithoutChangingSelection() async throws {
        let f = try Fixture225(); defer { f.cleanup() }
        let service = Clone225(delay:.milliseconds(90)), controller = PersonalVoiceController(speech:f.speech,directory:f.root,service:service,player:Play225())
        controller.create(audio:try f.audio(),provider:.bailian,name:"a",consent:true,copy:f.c)
        while await service.creates == 0 { await Task.yield() }
        let operation = controller.task; controller.cancel(); controller.resetWizardResult(); await operation?.value
        #expect(controller.voices.first?.state == .created)
        #expect(controller.lastCreated == nil && f.speech.source == .local)
    }
    @Test func previewUsesDescriptorAndReplayDoesNotCharge() async throws {
        let f = try Fixture225(); defer { f.cleanup() }
        let api = Synth225(), player = Play225(), controller = PersonalVoiceController(speech:f.speech,directory:f.root,service:Clone225(),synth:api,player:player)
        let voice = try f.voice(.minimax)
        controller.audition(voice,copy:f.c); await controller.task?.value
        let verified = try #require(controller.voices.first)
        #expect(verified.state == .verified && player.plays == 1)
        controller.audition(verified,copy:f.c)
        #expect(await api.calls == 1); #expect(player.plays == 2)
        #expect(await api.descriptors.first?.model == "speech-2.8-turbo")
        try f.speech.usePersonalVoice(verified)
        #expect(f.speech.provider == .minimax && f.speech.selectedPersonalVoice()?.id == voice.id && !f.speech.scheduleEnabled)
        controller.audition(verified,regenerate:true,copy:f.c); await controller.task?.value
        #expect(await api.calls == 2)
        controller.clearAudio(); #expect(!controller.hasCachedPreview(verified))
    }
    @Test func keyReplacementRequiresReverification() async throws {
        let f = try Fixture225(); defer { f.cleanup() }; let voice = try f.voice()
        let controller = PersonalVoiceController(speech:f.speech,directory:f.root,service:Clone225(),synth:Synth225(),player:Play225())
        controller.audition(voice,copy:f.c); await controller.task?.value
        let verified = try #require(controller.voices.first); #expect(f.speech.canUse(verified))
        #expect(f.speech.saveAPI(provider:.bailian,address:APIProvider.bailian.endpoint,key:"new-fixture",consent:true,copy:f.c))
        #expect(!f.speech.canUse(verified) && controller.voices.first?.state == .created)
        #expect(!f.speech.combinedVoiceChoices.contains { $0.value.contains(voice.id.uuidString) })
    }
    @Test func selectedDeletionProtectedAndFailedDeleteKeepsRecord() async throws {
        let f = try Fixture225(); defer { f.cleanup() }; var voice = try f.voice(); voice.state = .verified
        var config = f.speech.configuration.value; config.personalVoices = [voice]; try f.speech.configuration.save(config); try f.speech.usePersonalVoice(voice)
        let service = Clone225(fails:true), controller = PersonalVoiceController(speech:f.speech,directory:f.root,service:service,player:Play225())
        controller.delete(voice,copy:f.c); #expect(!controller.busy); #expect(await service.deletes == 0)
        f.speech.combinedVoice = try #require(f.speech.combinedVoiceChoices.first { !$0.value.contains("personal:") }).value
        controller.delete(voice,copy:f.c); await controller.task?.value
        #expect(controller.voices.count == 1)
        #expect(await service.deletes == 1)
    }
    @Test func remoteSuccessLocalFailureRecoversWithoutRecreating() async throws {
        let f = try Fixture225(); defer { f.cleanup() }
        let destination = f.root.appendingPathComponent("speech-settings-v3.json")
        try FileManager.default.removeItem(at:destination); try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:false)
        let service = Clone225(), controller = PersonalVoiceController(speech:f.speech,directory:f.root,service:service,player:Play225())
        controller.create(audio:try f.audio(),provider:.bailian,name:"a",consent:true,copy:f.c); await controller.task?.value
        let voice = try #require(controller.voices.first); #expect(voice.state == .created && controller.hasRecovery(voice))
        try FileManager.default.removeItem(at:destination)
        controller.retrySave(voice,copy:f.c)
        #expect(!controller.hasRecovery(voice) && f.speech.configuration.value.voiceLibrary.count == 1)
        #expect(await service.creates == 1)
    }
    @Test func corruptJournalBlocksBeforeCreate() async throws {
        let f = try Fixture225(); defer { f.cleanup() }
        try Data("broken".utf8).write(to:f.root.appendingPathComponent("voice-operations-v1.json"))
        let service = Clone225(), controller = PersonalVoiceController(speech:f.speech,directory:f.root,service:service,player:Play225())
        controller.create(audio:try f.audio(),provider:.bailian,name:"a",consent:true,copy:f.c); await controller.task?.value
        #expect(await service.creates == 0)
    }
    @Test func audioConversionPreservesOriginalAndRejectsSilenceAndCorruption() throws {
        let f = try Fixture225(); defer { f.cleanup() }
        func wav(_ url: URL, amplitude: Float) throws {
            let format = try #require(AVAudioFormat(standardFormatWithSampleRate:44100,channels:2)), buffer = try #require(AVAudioPCMBuffer(pcmFormat:format,frameCapacity:44100*11))
            buffer.frameLength = buffer.frameCapacity
            for c in 0..<2 { for i in 0..<Int(buffer.frameLength) { buffer.floatChannelData![c][i] = amplitude * sin(Float(i)*0.06) } }
            let file = try AVAudioFile(forWriting:url,settings:[AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:44100,AVNumberOfChannelsKey:2,AVLinearPCMBitDepthKey:16,AVLinearPCMIsFloatKey:false,AVLinearPCMIsBigEndianKey:false]); try file.write(from:buffer)
        }
        let source = f.root.appendingPathComponent("source.wav"), result = f.root.appendingPathComponent("result.wav")
        try wav(source,amplitude:0.2); let original = try Data(contentsOf:source)
        let prepared = try VoiceAudioPreparation.prepare(source:source,destination:result,provider:.minimax)
        #expect(abs(prepared.duration-11) < 0.01 && prepared.audibleSeconds > 10)
        let converted = try AVAudioFile(forReading:result)
        #expect(converted.fileFormat.sampleRate == 24000 && converted.fileFormat.channelCount == 1)
        #expect(try Data(contentsOf:source) == original)
        let silent = f.root.appendingPathComponent("silent.wav"); try wav(silent,amplitude:0)
        #expect(throws: (any Error).self) { try VoiceAudioPreparation.prepare(source:silent,destination:f.root.appendingPathComponent("silence-result.wav"),provider:.bailian) }
        let bad = f.root.appendingPathComponent("bad.mp3"); try Data("broken".utf8).write(to:bad)
        #expect(throws: (any Error).self) { try VoiceAudioPreparation.prepare(source:bad,destination:f.root.appendingPathComponent("bad-result.wav"),provider:.bailian) }
    }
}
