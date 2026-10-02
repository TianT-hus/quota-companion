import Foundation
import Combine

@MainActor final class PersonalVoiceController: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var phase = VoiceClonePhase.preparing
    @Published var error: String?
    @Published private(set) var lastCreated: PersonalVoice?
    @Published private(set) var revision = 0
    private unowned let speech: CompanionSpeech
    let recovery: VoiceRecoveryStore
    private let service: any VoiceCloningServicing
    private let synth: (any CloudSpeechSynthesizing)?
    private let player: any CloudAudioPlaying
    private var volatile: [UUID: PersonalVoice] = [:]
    private var audioCache: [String: Data] = [:]
    private var token = UUID()
    private(set) var task: Task<Void, Never>?
    init(speech: CompanionSpeech, directory: URL?, service: any VoiceCloningServicing = VoiceCloningClient(), synth: (any CloudSpeechSynthesizing)? = nil, player: any CloudAudioPlaying = CloudAudioPlayer()) {
        self.speech = speech; recovery = VoiceRecoveryStore(directory: directory); self.service = service; self.synth = synth; self.player = player
    }
    var voices: [PersonalVoice] {
        var values = Dictionary(uniqueKeysWithValues: speech.configuration.value.voiceLibrary.map { ($0.id, $0) })
        for value in recovery.entries { values[value.id] = value }
        for value in volatile.values { values[value.id] = value }
        return values.values.sorted { $0.createdAt > $1.createdAt }
    }
    func hasRecovery(_ voice: PersonalVoice) -> Bool { volatile[voice.id] != nil || recovery.entries.contains { $0.id == voice.id } }
    private func endpoint(_ provider: APIProvider) -> String { speech.configuration.value.endpoints[provider.rawValue] ?? provider.endpoint }
    private func begin(_ phase: VoiceClonePhase) -> UUID? {
        guard !busy else { return nil }; token = UUID(); busy = true; self.phase = phase; error = nil; player.stop(); return token
    }
    private func finish(_ id: UUID) { if token == id { busy = false; task = nil } }
    private func failure(_ error: Error, copy: Copybook) {
        if error is CancellationError { return }
        self.error = (error as? VoiceCloneError)?.message(copy) ?? (error as? CloudSpeechError)?.message(copy) ?? copy.text("操作未完成，请检查网络或重试保存。", "The operation did not complete. Check the network or retry saving.")
    }
    func cancel() { token = UUID(); task?.cancel(); task = nil; busy = false; player.stop(); audioCache.removeAll() }
    func stopAudio() { player.stop() }
    func clearAudio() { player.stop(); audioCache.removeAll() }
    func hasCachedPreview(_ voice: PersonalVoice) -> Bool {
        audioCache[voice.id.uuidString + speech.cloudLanguage.rawValue + voice.credentialRevision] != nil
    }
    func resetWizardResult() { lastCreated = nil; error = nil }
    private func persist(_ voice: PersonalVoice) throws {
        volatile[voice.id] = voice; revision += 1
        try recovery.put(voice)
        var next = speech.configuration.value
        next.personalVoices = next.voiceLibrary.filter { $0.id != voice.id }
        if voice.state != .deleted { next.personalVoices?.append(voice) }
        try speech.configuration.save(next)
        try recovery.remove(voice.id); volatile[voice.id] = nil; revision += 1
    }
    func retrySave(_ voice: PersonalVoice, copy: Copybook) {
        do { try persist(voice); error = nil } catch { self.error = VoiceCloneError.storage.message(copy) }
    }
    func create(audio: PreparedVoiceAudio, provider: APIProvider, name: String, consent: Bool, copy: Copybook) {
        guard consent else { error = VoiceCloneError.consent.message(copy); return }
        guard PersonalVoice.validName(name) else { error = VoiceCloneError.name.message(copy); return }
        guard speech.configuredProviders.contains(provider) else { error = CloudSpeechError.missingKey.message(copy); return }
        guard lastCreated == nil else { error = VoiceCloneError.unknownResult.message(copy); return }
        guard let id = begin(.preparing) else { return }
        let draft = PersonalVoice(provider: provider, name: name.trimmingCharacters(in: .whitespacesAndNewlines), revision: speech.configuration.value.credentialRevision(provider))
        let address = endpoint(provider)
        task = Task { [weak self] in
            guard let self else { return }; defer { finish(id) }
            var submitted = false
            do {
                try VoiceAudioPreparation.validate(duration: audio.duration, bytes: audio.bytes, provider: provider)
                let bytes = try await Task.detached { try Data(contentsOf: audio.url) }.value
                guard token == id, !Task.isCancelled else { return }
                let key = try await speech.personalKey(provider)
                guard token == id, draft.credentialRevision == speech.configuration.value.credentialRevision(provider) else { throw VoiceCloneError.configurationChanged }
                try recovery.put(draft); revision += 1; submitted = true; lastCreated = draft
                let created = try await service.create(draft, audio: bytes, endpoint: address, key: key) { [weak self] stage in
                    await MainActor.run { if self?.token == id { self?.phase = stage } }
                }
                // Persist remote success even if a late result belongs to a closed wizard.
                do { try persist(created) } catch { throw VoiceCloneError.storage }
                if token == id { lastCreated = created }
            } catch {
                if submitted {
                    let rejected: Bool
                    switch error {
                    case CloudSpeechError.authorization, CloudSpeechError.quota, VoiceCloneError.service: rejected = true
                    default: rejected = false
                    }
                    if rejected {
                        do { try recovery.remove(draft.id); revision += 1; if token == id { lastCreated = nil } }
                        catch { if token == id { self.error = VoiceCloneError.storage.message(copy) }; return }
                    } else if token == id, !(error is VoiceCloneError) { self.error = VoiceCloneError.unknownResult.message(copy); return }
                }
                if token == id { failure(error, copy: copy) }
            }
        }
    }
    func check(_ voice: PersonalVoice, copy: Copybook) {
        guard let id = begin(.checking) else { return }
        let address = endpoint(voice.provider), account = speech.configuration.value.credentialRevision(voice.provider)
        task = Task { [weak self] in
            guard let self else { return }; defer { finish(id) }
            do {
                let key = try await speech.personalKey(voice.provider)
                guard token == id else { return }
                var found = try await service.find(voice, endpoint: address, key: key)
                guard token == id, account == speech.configuration.value.credentialRevision(voice.provider) else { return }
                found.credentialRevision = account; found.deletionPending = nil; try persist(found); lastCreated = found
            } catch {
                guard token == id else { return }
                if case VoiceCloneError.notFound = error, voice.deletionPending == true {
                    var removed = voice; removed.state = .deleted
                    do { try persist(removed) } catch { failure(VoiceCloneError.storage, copy: copy) }
                } else { failure(error, copy: copy) }
            }
        }
    }
    func audition(_ voice: PersonalVoice, regenerate: Bool = false, copy: Copybook) {
        guard voice.deletionPending != true, voice.state == .created || voice.state == .verified, let descriptor = voice.descriptor else { error = VoiceCloneError.unknownResult.message(copy); return }
        guard voice.credentialRevision == speech.configuration.value.credentialRevision(voice.provider) else { error = VoiceCloneError.configurationChanged.message(copy); return }
        let language = speech.cloudLanguage, cacheKey = voice.id.uuidString + language.rawValue + voice.credentialRevision
        if !regenerate, let data = audioCache[cacheKey] { do { try player.play(data, rate: speech.rate, volume: speech.volume) } catch { failure(error, copy: copy) }; return }
        guard let id = begin(.previewing) else { return }
        speech.stop(); let address = endpoint(voice.provider)
        task = Task { [weak self] in
            guard let self else { return }; defer { finish(id) }
            do {
                let key = try await speech.personalKey(voice.provider)
                guard token == id else { return }
                let client: any CloudSpeechSynthesizing = synth ?? (voice.provider == .bailian ? BailianSpeechClient() as any CloudSpeechSynthesizing : MiniMaxSpeechClient(endpoint: address))
                let sample = SpeechTemplate.standard(.schedule, chinese: language == .chinese).example(Copybook(language: language == .chinese ? .zhHans : .english), language: language)
                let data = try await client.synthesize(text: sample, language: language, descriptor: descriptor, key: key)
                guard token == id, voice.credentialRevision == speech.configuration.value.credentialRevision(voice.provider) else { return }
                var verified = voice; verified.state = .verified
                audioCache[cacheKey] = data
                try persist(verified); lastCreated = verified
                try player.play(data, rate: speech.rate, volume: speech.volume)
            } catch { if token == id { failure(error, copy: copy) } }
        }
    }
    func rename(_ voice: PersonalVoice, name: String, copy: Copybook) -> Bool {
        guard PersonalVoice.validName(name) else { error = VoiceCloneError.name.message(copy); return false }
        var next = voice; next.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do { try persist(next); error = nil; return true } catch { failure(VoiceCloneError.storage, copy: copy); return false }
    }
    func delete(_ voice: PersonalVoice, copy: Copybook) {
        guard voice.deletionPending != true else { error = VoiceCloneError.unknownResult.message(copy); return }
        guard !speech.usesPersonalVoice(voice) else { error = VoiceCloneError.selected.message(copy); return }
        guard voice.credentialRevision == speech.configuration.value.credentialRevision(voice.provider) else { error = VoiceCloneError.configurationChanged.message(copy); return }
        guard let id = begin(.deleting) else { return }
        let address = endpoint(voice.provider)
        task = Task { [weak self] in
            guard let self else { return }; defer { finish(id) }
            do {
                let key = try await speech.personalKey(voice.provider)
                guard token == id else { return }
                var pending = voice; pending.deletionPending = true
                try recovery.put(pending); revision += 1
                try await service.delete(voice, endpoint: address, key: key)
                var removed = voice; removed.state = .deleted
                try persist(removed)
                if token == id { clearAudio() }
            } catch { if token == id { failure(error, copy: copy) } }
        }
    }
}
