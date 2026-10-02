import AVFoundation
import AppKit
import Combine
import QuotaCore

struct CompanionVoice: Identifiable {
    let id: String
    let name: String
    let language: String
    let quality: Int
}

@MainActor protocol CloudAudioPlaying {
    func play(_ data: Data, rate: Double, volume: Double) throws
    func stop()
}
@MainActor final class CloudAudioPlayer: CloudAudioPlaying {
    private var player: AVAudioPlayer?
    func play(_ data: Data, rate: Double, volume: Double) throws {
        let player = try AVAudioPlayer(data: data)
        player.enableRate = true; player.rate = Float(min(2, max(0.5, rate / 0.48)))
        player.volume = Float(min(1, max(0, volume)))
        guard player.prepareToPlay(), player.play() else { throw CloudSpeechError.audio }
        self.player = player
    }
    func stop() { player?.stop(); player = nil }
}

@MainActor final class CompanionSpeech: ObservableObject {
    @Published private(set) var source: SpeechSource
    @Published var cloudLanguage: SpeechLanguage { didSet { stop(); apiStatus = .unknown; speechProblem = nil; defaults.set(cloudLanguage.rawValue, forKey: "speech.cloud.language.v1") } }
    @Published private(set) var apiStatus: SpeechRuntimeStatus = .unknown {
        didSet { apiStatuses[provider.rawValue + "|" + endpoint] = apiStatus }
    }
    private var apiStatuses: [String: SpeechRuntimeStatus] = [:]
    @Published private(set) var speechProblem: SpeechRuntimeStatus?
    @Published private(set) var cloudVoices: [String: String]
    @Published private(set) var cloudBusy = false
    @Published var dialog: String?
    @Published var draft: SpeechEditingDraft?
    let configuration: SpeechConfigurationStore
    lazy var personalVoiceController: PersonalVoiceController = {
        if VoiceCloneQA.enabled { return PersonalVoiceController(speech: self, directory: configuration.directory, service: VoiceCloneQAService(), synth: VoiceCloneQASynth(), player: VoiceCloneQAPlayer()) }
        return PersonalVoiceController(speech: self, directory: configuration.directory)
    }()
    private let credentials: (any SpeechCredentials)?
    let credentialSession = SpeechCredentialSession()
    private let cloud: (any CloudSpeechSynthesizing)?
    private let translator: any SpeechTranslating
    private var configurationChange: AnyCancellable?
    private var translationTask: Task<Void, Never>?
    private var translationDeadline: Task<Void, Never>?
    private let player: any CloudAudioPlaying
    private let timeout: Duration
    private let translationTimeout: Duration
    private var generation = UUID()
    private var cloudTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    @Published var scheduleEnabled: Bool { didSet { defaults.set(scheduleEnabled, forKey: "speech.schedule.v1"); if !scheduleEnabled { stop() } } }
    @Published var voiceID: String { didSet { defaults.set(voiceID, forKey: "speech.voice.v1") } }
    @Published var rate: Double { didSet { defaults.set(rate, forKey: "speech.rate.v1") } }
    @Published var volume: Double { didSet { defaults.set(volume, forKey: "speech.volume.v1") } }
    @Published private(set) var voices: [CompanionVoice] = []
    @Published private(set) var message = ""
    private let defaults: UserDefaults
    private let synthesizer = AVSpeechSynthesizer()
    private var expiry: Timer?
    init(defaults: UserDefaults, directory: URL? = nil, credentials: (any SpeechCredentials)? = nil, cloud: (any CloudSpeechSynthesizing)? = nil, player: any CloudAudioPlaying = CloudAudioPlayer(), timeout: Duration = .seconds(10), translator: (any SpeechTranslating)? = nil, translationTimeout: Duration = .seconds(5)) {
        self.defaults = defaults
        configuration = SpeechConfigurationStore(directory: directory, defaults: defaults)
        self.translator = translator ?? SystemSpeechTranslator(defaults: defaults)
        self.translationTimeout = translationTimeout
        self.credentials = credentials ?? (SpeechStatusQA.enabled ? StatusQAKey() : nil)
        self.cloud = cloud ?? (SpeechStatusQA.enabled ? StatusQAService() : nil)
        self.player = SpeechStatusQA.enabled ? VoiceCloneQAPlayer() : player; self.timeout = timeout
        source = defaults.bool(forKey: "speech.cloud.consent.v1") ? (SpeechSource(rawValue: defaults.string(forKey: "speech.source.v1") ?? "") ?? .local) : .local
        cloudLanguage = SpeechLanguage(rawValue: defaults.string(forKey: "speech.cloud.language.v1") ?? "") ?? .chinese
        cloudVoices = defaults.dictionary(forKey: "speech.cloud.voices.v1") as? [String: String] ?? [:]
        scheduleEnabled = defaults.bool(forKey: "speech.schedule.v1")
        voiceID = defaults.string(forKey: "speech.voice.v1") ?? ""
        rate = (defaults.object(forKey: "speech.rate.v1") as? Double).map { min(0.6, max(0.3, $0)) } ?? 0.48
        volume = (defaults.object(forKey: "speech.volume.v1") as? Double).map { min(1, max(0, $0)) } ?? 0.8
        reloadVoices()
        configurationChange = configuration.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    var provider: APIProvider { configuration.value.provider }
    func credentialPresence(_ provider: APIProvider) -> CredentialPresence {
        // Test/preview instances must not touch the user's Keychain.
        guard credentials == nil, Bundle.main.object(forInfoDictionaryKey: "QuotaSecretaryPreview") as? Bool != true else { return .unknown }
        return KeychainSpeechCredentials(provider: provider).presence()
    }
    func translationPrepared(from source: SpeechLanguage) {
        var pairs = Set(defaults.stringArray(forKey: "speech.translation.prepared.v1") ?? [])
        pairs.insert(SystemSpeechTranslator.pair(Locale.Language(identifier: source.code), cloudLanguage))
        defaults.set(pairs.sorted(), forKey: "speech.translation.prepared.v1")
    }
    var apiVoices: [BailianVoice] { provider == .bailian ? BailianVoice.available(cloudLanguage) : MiniMaxSpeechClient.voices(cloudLanguage) }
    func canUse(_ voice: PersonalVoice) -> Bool {
        let pending = personalVoiceController.voices.first { $0.id == voice.id }
        return voice.state == .verified && voice.deletionPending != true && pending?.deletionPending != true && pending?.state != .deleted && voice.credentialRevision == configuration.value.credentialRevision(voice.provider) && voice.descriptor != nil
    }
    func personalKey(_ provider: APIProvider) async throws -> String {
        if VoiceCloneQA.enabled { return "isolated-fixture-not-a-key" }
        return try await credentialSession.read(provider: provider, interaction: true, injected: credentials)
    }
    func selectedPersonalVoice() -> PersonalVoice? {
        let selected = configuration.value.voices["\(provider.rawValue):\(cloudLanguage.rawValue)"]
        return configuration.value.voiceLibrary.first { $0.selectionID == selected && $0.provider == provider }
    }
    func usesPersonalVoice(_ voice: PersonalVoice) -> Bool { configuration.value.voices.values.contains(voice.selectionID) }
    func usePersonalVoice(_ voice: PersonalVoice) throws {
        guard canUse(voice), configuration.value.voiceLibrary.contains(where: { $0.id == voice.id }), configuredProviders.contains(voice.provider) else { throw VoiceCloneError.configurationChanged }
        var next = configuration.value; next.provider = voice.provider
        next.voices["\(voice.provider.rawValue):\(cloudLanguage.rawValue)"] = voice.selectionID
        try configuration.save(next); selectSource(.bailian, consent: true); apiStatus = .unknown
    }
    func usePersonalVoice(_ voice: PersonalVoice, copy: Copybook) -> Bool {
        do { try usePersonalVoice(voice); return true }
        catch { dialog = (error as? VoiceCloneError)?.message(copy) ?? VoiceCloneError.storage.message(copy); return false }
    }
    var configuredProviders: [APIProvider] { APIProvider.allCases.filter { configuration.value.consented.contains($0) } }
    var combinedVoiceChoices: [SettingsChoice<String>] {
        configuredProviders.flatMap { vendor in
            let voices = vendor == .bailian ? BailianVoice.available(cloudLanguage) : MiniMaxSpeechClient.voices(cloudLanguage)
            let c = Copybook(language: .system)
            return voices.map { SettingsChoice(vendor.rawValue + ":" + $0.id, $0.title, group: vendor.name + c.text(" · 系统音色", " · System voices")) }
                + configuration.value.voiceLibrary.filter { $0.provider == vendor && canUse($0) }.map { SettingsChoice(vendor.rawValue + ":" + $0.selectionID, $0.name, group: vendor.name + c.text(" · 我的声音", " · My voices")) }
        }
    }
    var combinedVoice: String {
        get { provider.rawValue + ":" + cloudVoice }
        set {
            guard combinedVoiceChoices.contains(where: { $0.value == newValue }),
                  let colon = newValue.firstIndex(of: ":"), let vendor = APIProvider(rawValue: String(newValue[..<colon])) else { return }
            let voice = String(newValue[newValue.index(after: colon)...])
            var next = configuration.value; next.provider = vendor; next.voices["\(vendor.rawValue):\(cloudLanguage.rawValue)"] = voice
            do {
                try configuration.save(next)
                let restoredStatus = apiStatuses[vendor.rawValue + "|" + endpoint] ?? .unknown
                stop(); speechProblem = nil; apiStatus = restoredStatus.phase == .testing ? .unknown : restoredStatus
            } catch { dialog = Copybook(language: .system).text("声音选择保存失败。", "Could not save voice selection.") }
        }
    }
    var endpoint: String { configuration.value.endpoints[provider.rawValue] ?? provider.endpoint }
    var spokenVoices: [CompanionVoice] { voices.filter { $0.language.hasPrefix(String(cloudLanguage.code.prefix(2))) } }
    var localVoice: String {
        get {
            let saved = configuration.value.voices["local:\(cloudLanguage.rawValue)"] ?? voiceID
            return spokenVoices.contains(where: { $0.id == saved }) ? saved : ""
        }
        set {
            stop(); speechProblem = nil; var next = configuration.value; next.voices["local:\(cloudLanguage.rawValue)"] = newValue
            do { try configuration.save(next) } catch { dialog = Copybook(language: .system).text("声音选择保存失败。", "Could not save voice selection.") }
        }
    }
    func saveAPI(provider: APIProvider, address: String, key: String, consent: Bool, copy: Copybook) -> Bool {
        guard APIProvider.identify(address) == provider else { dialog = copy.text("请选择受支持的官方 HTTPS 接口地址。", "Choose a supported official HTTPS endpoint."); return false }
        guard consent || configuration.value.consented.contains(provider) else { return false }
        let previous = configuration.value
        do {
            guard !key.contains(where: \.isWhitespace) else { throw CloudSpeechError.missingKey }
            var next = configuration.value; next.endpoints[provider.rawValue] = address
            if !key.isEmpty || (next.endpoints[provider.rawValue] != previous.endpoints[provider.rawValue]) {
                var revisions = next.credentialRevisions ?? [:]; revisions[provider.rawValue] = UUID().uuidString; next.credentialRevisions = revisions
                next.personalVoices = next.voiceLibrary.map { voice in var v = voice; if v.provider == provider && v.state == .verified { v.state = .created }; return v }
            }
            next.consented.insert(provider); try configuration.save(next)
            if !key.isEmpty {
                do { try (credentials ?? KeychainSpeechCredentials(provider: provider)).save(key) }
                catch { try configuration.save(previous); throw error }
                credentialSession.clear()
            }
            apiStatuses = apiStatuses.filter { !$0.key.hasPrefix(provider.rawValue + "|") }
            if self.provider == provider { stop(); apiStatus = .unknown; speechProblem = nil }
            message = copy.text("API 配置已保存。", "API configuration saved."); return true
        } catch { dialog = copy.text("无法保存 API 配置，请检查钥匙串和存储权限。", "Could not save API configuration. Check Keychain and storage access."); return false }
    }
    var cloudVoice: String {
        get {
            let saved = configuration.value.voices["\(provider.rawValue):\(cloudLanguage.rawValue)"] ?? (provider == .bailian ? cloudVoices[cloudLanguage.rawValue] : nil)
            // Never silently substitute a different paid voice when a personal voice needs verification.
            if let saved, saved.hasPrefix("personal:") { return saved }
            return apiVoices.first(where: { $0.id == saved })?.id ?? (provider == .bailian && cloudLanguage == .japanese ? "Ono Anna" : apiVoices[0].id)
        }
        set {
            stop(); apiStatus = .unknown; speechProblem = nil; var next = configuration.value; next.voices["\(provider.rawValue):\(cloudLanguage.rawValue)"] = newValue
            do {
                try configuration.save(next)
                if provider == .bailian { cloudVoices[cloudLanguage.rawValue] = newValue; defaults.set(cloudVoices, forKey: "speech.cloud.voices.v1") }
            } catch { dialog = Copybook(language: .system).text("声音选择保存失败。", "Could not save voice selection.") }
        }
    }
    var cloudConsented: Bool { configuration.value.consented.contains(provider) || (provider == .bailian && defaults.bool(forKey: "speech.cloud.consent.v1")) }
    func selectSource(_ value: SpeechSource, consent: Bool = false) {
        if value == .bailian {
            guard consent || cloudConsented else { return }
            defaults.set(true, forKey: "speech.cloud.consent.v1")
        }
        stop(); if value == .local { credentialSession.clear() }; speechProblem = nil; source = value; defaults.set(value.rawValue, forKey: "speech.source.v1")
    }
    func saveKey(_ value: String, copy: Copybook) -> Bool {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains(where: { $0.isWhitespace }) else { dialog = CloudSpeechError.missingKey.message(copy); return false }
        return saveAPI(provider: provider, address: endpoint, key: key, consent: cloudConsented, copy: copy)
    }
    func status(copy: Copybook) -> SpeechRuntimeStatus {
        if let speechProblem { return speechProblem }
        if source == .bailian { return apiStatus }
        return spokenVoices.isEmpty && AVSpeechSynthesisVoice(language: cloudLanguage.code) == nil
            ? .failed(copy.text("没有可用的系统声音，请下载此语言的声音。", "No local voice available. Download a voice for this language."))
            : .ready(copy.text("本地声音已就绪。", "Local voice ready."))
    }
    func testConnection(copy: Copybook) {
        guard !cloudBusy else { return }
        guard cloudConsented else {
            apiStatus = .failed(copy.text("请先打开“配置 API”，保存并确认此平台的使用与计费说明，再测试连接。", "Open Configure API and save this provider's configuration with consent before testing."))
            return
        }
        cloudSpeak(cloudLanguage.sample, copy: copy, deadline: nil, audition: false, play: false, authorize: true)
    }
    func testAPI(provider: APIProvider, address: String, key: String, copy: Copybook, completion: @escaping @MainActor (SpeechRuntimeStatus) -> Void) {
        guard !cloudBusy else { return }
        guard APIProvider.identify(address) == provider else { completion(.failed(copy.text("暂不支持此接口地址。", "Unsupported endpoint."))); return }
        cloudSpeak(cloudLanguage.sample, copy: copy, deadline: nil, audition: true, play: false, testing: (provider, address, key), result: completion)
    }
    private func cloudSpeak(_ text: String, copy: Copybook, deadline: Date?, audition: Bool, play: Bool = true, authorize: Bool = false, testing: (APIProvider, String, String)? = nil, result: (@MainActor (SpeechRuntimeStatus) -> Void)? = nil) {
        stop(); message = ""
        guard testing != nil || cloudConsented else { return }
        guard deadline == nil || deadline! > .now else { return }
        let chosenProvider = testing?.0 ?? provider, chosenEndpoint = testing?.1 ?? endpoint
        let token = generation, language = cloudLanguage
        let voice = chosenProvider == provider ? cloudVoice : (chosenProvider == .bailian ? BailianVoice.available(language) : MiniMaxSpeechClient.voices(language))[0].id
        let descriptor: SpeechVoiceDescriptor
        if voice.hasPrefix("personal:"), testing == nil {
            guard let personal = selectedPersonalVoice(), canUse(personal), let value = personal.descriptor else {
                speechProblem = .failed(VoiceCloneError.configurationChanged.message(copy)); return
            }
            descriptor = value
        } else {
            let systemID = voice.hasPrefix("personal:") ? (chosenProvider == .bailian ? BailianVoice.available(language) : MiniMaxSpeechClient.voices(language))[0].id : voice
            descriptor = .init(provider: chosenProvider, id: systemID, model: chosenProvider == .bailian ? "qwen3-tts-flash" : "speech-2.8-turbo")
        }
        cloudBusy = true
        if testing == nil { apiStatus = .testing }
        result?(.testing)
        cloudTask = Task { [weak self] in
            guard let self else { return }
            do {
                let key: String
                if let draftKey = testing?.2, !draftKey.isEmpty { key = draftKey }
                else { key = try await credentialSession.read(provider: chosenProvider, interaction: authorize || audition, injected: credentials) }
                guard !Task.isCancelled, generation == token, deadline == nil || deadline! > .now else {
                    if generation == token { stop() }; return
                }
                timeoutTask = Task { [weak self] in
                    guard let self else { return }
                    do { try await Task.sleep(for: timeout) } catch { return }
                    guard generation == token else { return }
                    stop(); message = CloudSpeechError.timeout.message(copy)
                    if testing == nil { apiStatus = .failed(message) }
                    if let result { result(.failed(message)) } else if audition && play { dialog = message }
                }
                let service: any CloudSpeechSynthesizing = cloud ?? (chosenProvider == .bailian ? BailianSpeechClient() as any CloudSpeechSynthesizing : MiniMaxSpeechClient(endpoint: chosenEndpoint))
                let data = try await service.synthesize(text: text, language: language, descriptor: descriptor, key: key)
                guard !Task.isCancelled, generation == token else { return }
                timeoutTask?.cancel(); timeoutTask = nil; cloudBusy = false
                let success = SpeechRuntimeStatus.ready(copy.text("API 最近一次调用成功。", "The latest API request succeeded."), at: .now)
                if testing == nil { apiStatus = success; if play { speechProblem = nil } }
                result?(success)
                guard deadline == nil || deadline! > .now else { return }
                if play { try player.play(data, rate: rate, volume: volume) }
                message = copy.text("API 连接正常。", "API connection successful.")
                if play, let deadline {
                    expiry = Timer.scheduledTimer(withTimeInterval: max(0.01, deadline.timeIntervalSinceNow), repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.stop() } }
                }
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                timeoutTask?.cancel(); timeoutTask = nil; cloudBusy = false
                let failure = error as? CloudSpeechError ?? ((error as? URLError)?.code == .timedOut ? .timeout : .network)
                message = failure.message(copy)
                if testing == nil {
                    if apiStatus.phase == .ready { speechProblem = .failed(message) }
                    else { apiStatus = .failed(message) }
                }
                if let result { result(.failed(message)) } else if audition && play { dialog = message }
            }
        }
    }
    func reloadVoices() {
        speechProblem = nil
        voices = AVSpeechSynthesisVoice.speechVoices().map {
            CompanionVoice(id: $0.identifier, name: $0.name, language: $0.language, quality: Int($0.quality.rawValue))
        }.sorted { $0.language == $1.language ? ($0.quality == $1.quality ? $0.name < $1.name : $0.quality > $1.quality) : $0.language < $1.language }
    }
    func speak(_ text: String, copy: Copybook, until deadline: Date? = nil) {
        if source == .bailian { cloudSpeak(text, copy: copy, deadline: deadline ?? Date().addingTimeInterval(30), audition: false); return }
        stop(); message = ""; speechProblem = nil
        guard deadline == nil || deadline! > .now else { return }
        let language = String(cloudLanguage.code.prefix(2))
        let system = AVSpeechSynthesisVoice(language: cloudLanguage.code)
        let automatic = voices.filter { system == nil ? $0.language.hasPrefix(language) : $0.language == system?.language }.max { $0.quality < $1.quality }
        let preferred = automatic.flatMap { candidate in
            if let system, candidate.quality <= Int(system.quality.rawValue) { return system }
            return AVSpeechSynthesisVoice(identifier: candidate.id)
        } ?? system
        let chosen = localVoice.isEmpty ? nil : AVSpeechSynthesisVoice(identifier: localVoice).flatMap { $0.language.hasPrefix(language) ? $0 : nil }
        let voice = chosen ?? preferred
        guard let voice else { message = copy.text("没有可用的系统声音，请在系统设置下载声音。", "No system voice is available. Download one in System Settings."); speechProblem = .failed(message); return }
        if !voiceID.isEmpty && chosen == nil { message = copy.text("所选声音暂不可用，本次使用系统可用声音。", "Selected voice unavailable; using an available system voice.") }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice; utterance.rate = Float(min(0.6, max(0.3, rate))); utterance.volume = Float(min(1, max(0, volume)))
        synthesizer.speak(utterance)
        if let deadline {
            expiry = Timer.scheduledTimer(withTimeInterval: max(0.01, deadline.timeIntervalSinceNow), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
        }
    }
    func announce(_ block: ScheduleBlock, date: Date, copy: Copybook) {
        guard scheduleEnabled else { return }
        let deadline = Self.endDate(block, date: date)
        let template = template(.schedule, copy: copy)
        let now = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
        speakTemplate(template, values: [.now: time(now), .start: time(block.start), .end: time(block.end), .event: block.title], copy: copy, deadline: deadline)
    }
    nonisolated static func announcement(_ block: ScheduleBlock, chinese: Bool) -> String {
        func time(_ minute: Int) -> String { SpokenTime.format(minute, language: .chinese) }
        return chinese ? "现在是\(time(block.start))到\(time(block.end))，\(block.title)。" : "From \(block.timeLabel), \(block.title)."
    }
    static func endDate(_ block: ScheduleBlock, date: Date, calendar: Calendar = .current) -> Date? {
        if block.end == 1440 { return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) }
        return calendar.date(bySettingHour: block.end / 60, minute: block.end % 60, second: 0, of: date)
    }
    func preview(copy: Copybook, parent: NSWindow? = nil) {
        if let draft { previewTemplate(draft.template, copy: copy); return }
        let alert = NSAlert(); alert.messageText = copy.text("选择试听播报", "Choose an announcement preview")
        alert.addButton(withTitle: copy.text("日程播报", "Schedule announcement"))
        alert.addButton(withTitle: copy.text("低额度提醒", "Low-quota alert"))
        alert.addButton(withTitle: copy.text("取消", "Cancel"))
        switch alert.runOwnedModal(parent: parent) {
        case .alertFirstButtonReturn: previewSaved(.schedule, copy: copy)
        case .alertSecondButtonReturn: previewSaved(.quota, copy: copy)
        default: break
        }
    }
    func previewSaved(_ kind: SpeechTemplateKind, copy: Copybook) { previewTemplate(template(kind, copy: copy), copy: copy) }
    func template(_ kind: SpeechTemplateKind, copy: Copybook) -> SpeechTemplate {
        configuration.value.templates[kind.rawValue] ?? .standard(kind, chinese: copy.locale.language.languageCode?.identifier == "zh")
    }
    func editTemplate(_ kind: SpeechTemplateKind, copy: Copybook, parent: NSWindow? = nil) {
        guard discardDraft(copy: copy, parent: parent) else { return }
        draft = SpeechEditingDraft(template: template(kind, copy: copy), rule: configuration.value.quota)
    }
    func discardDraft(copy: Copybook, parent: NSWindow? = nil) -> Bool {
        if draft?.dirty == true {
            let alert = NSAlert(); alert.messageText = copy.text("放弃未保存的播报修改？", "Discard unsaved speech changes?")
            alert.addButton(withTitle: copy.text("继续编辑", "Keep editing")); alert.addButton(withTitle: copy.text("放弃修改", "Discard changes"))
            guard alert.runOwnedModal(parent: parent) == .alertSecondButtonReturn else { return false }
        }
        draft = nil; return true
    }
    func saveDraft(copy: Copybook) {
        guard let draft else { return }
        do {
            try draft.template.validate(); var next = configuration.value
            next.templates[draft.template.kind.rawValue] = draft.template
            if draft.template.kind == .quota { next.quota.delivery = draft.rule.delivery; next.quota.thresholds = try QuotaSpeechRule.parse(draft.thresholdText) }
            try configuration.save(next); self.draft = nil; stop()
        } catch {
            dialog = copy.text("无法保存：文案不能为空，最多 40 个片段、400 字自定义文字；阈值需为 0–100 的整数。请同时检查存储权限。", "Could not save. Enter nonempty text with at most 40 pieces and 400 custom-text characters; thresholds must be integers from 0–100. Also check storage permissions.")
        }
    }
    func setQuotaEnabled(_ enabled: Bool, copy: Copybook) {
        do { var next = configuration.value; next.quota.enabled = enabled; try configuration.save(next); if !enabled { stop() } }
        catch { dialog = copy.text("提醒开关保存失败。", "Could not save reminder setting.") }
    }
    func time(_ minute: Int) -> String {
        SpokenTime.format(minute, language: cloudLanguage)
    }
    func quotaValues(_ window: QuotaWindow) -> [SpeechToken: String] {
        let p = Int(window.remainingPercent.rounded()), primary = window.kind == .primary
        switch cloudLanguage {
        case .chinese: return [.quota: primary ? "五小时额度" : "每周额度", .percent: "百分之\(p)"]
        case .english: return [.quota: primary ? "Five-hour quota" : "Weekly quota", .percent: "\(p) percent"]
        case .japanese: return [.quota: primary ? "五時間の利用枠" : "週間の利用枠", .percent: "\(p)パーセント"]
        }
    }
    func speakTemplate(_ template: SpeechTemplate, values: [SpeechToken: String], copy: Copybook, deadline: Date? = nil, audition: Bool = false) {
        stop(); let token = generation; message = ""; speechProblem = nil; cloudBusy = true
        translationDeadline = Task { [weak self] in
            do { try await Task.sleep(for: self?.translationTimeout ?? .seconds(5)) } catch { return }
            guard let self, generation == token else { return }
            stop(); message = copy.text("系统翻译超时，本次不播报。", "System translation timed out; speech skipped.")
            speechProblem = .failed(message)
            if audition { dialog = message }
        }
        translationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try template.validate()
                var translatedValues = values
                if template.pieces.contains(where: { $0.token == .event }) {
                    guard let event = values[.event], !event.isEmpty else { throw SpeechConfigError.invalidTemplate }
                    translatedValues[.event] = try await translator.translate(event, to: cloudLanguage)
                    guard !Task.isCancelled, generation == token else { return }
                }
                var replacements: [String: String] = [:]
                let input = template.pieces.enumerated().map { index, piece -> String in
                    guard let key = piece.token else { return piece.text }
                    let marker = "⟦\(index)⟧"; replacements[marker] = translatedValues[key] ?? ""; return marker
                }.joined()
                var output = try await translator.translate(input, to: cloudLanguage)
                guard !Task.isCancelled, generation == token else { return }
                for (marker, value) in replacements {
                    guard output.components(separatedBy: marker).count == 2 else { throw SpeechConfigError.translationUnavailable }
                    output = output.replacingOccurrences(of: marker, with: value)
                }
                guard output.count <= (source == .local ? 10000 : provider == .bailian ? 600 : 9999) else { throw CloudSpeechError.invalidText }
                translationDeadline?.cancel(); translationDeadline = nil; cloudBusy = false
                guard deadline == nil || deadline! > .now else { return }
                if source == .bailian { cloudSpeak(output, copy: copy, deadline: deadline ?? Date().addingTimeInterval(30), audition: audition) }
                else { speak(output, copy: copy, until: deadline) }
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                translationDeadline?.cancel(); cloudBusy = false
                message = (error as? CloudSpeechError)?.message(copy) ?? copy.text("系统翻译不可用，请在语音设置准备语言资源；本次仅保留视觉提醒。", "System translation unavailable. Prepare language resources in Speech settings; only the visual reminder remains.")
                if case SpeechConfigError.invalidTemplate = error { message = copy.text("请输入播报内容，最多 40 个片段、400 字自定义文字。", "Enter an announcement with at most 40 pieces and 400 characters of custom text.") }
                speechProblem = .failed(message)
                if audition { dialog = message }
            }
        }
    }
    func previewTemplate(_ template: SpeechTemplate, copy: Copybook) {
        let values: [SpeechToken: String] = [.now: time(780), .start: time(780), .end: time(1050), .event: copy.text("整理资料", "Organize documents"), .quota: quotaValues(QuotaWindow(kind: .primary, usedPercent: 90, windowDurationMinutes: 300, resetsAt: .now))[.quota]!, .percent: quotaValues(QuotaWindow(kind: .primary, usedPercent: 90, windowDurationMinutes: 300, resetsAt: .now))[.percent]!]
        speakTemplate(template, values: values, copy: copy, audition: true)
    }
    func stop() {
        if apiStatus.phase == .testing { apiStatus = .unknown }
        translationTask?.cancel(); translationTask = nil; translationDeadline?.cancel(); translationDeadline = nil; translator.cancel()
        generation = UUID(); cloudTask?.cancel(); cloudTask = nil; timeoutTask?.cancel(); timeoutTask = nil; cloudBusy = false
        player.stop(); expiry?.invalidate(); expiry = nil; synthesizer.stopSpeaking(at: .immediate)
    }
}
