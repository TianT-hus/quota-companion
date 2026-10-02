import AppKit
import Combine

/// Local navigation and draft only. Paid operations remain explicit controller actions.
@MainActor final class VoiceWizardSession: ObservableObject {
    enum Page: String { case platform, audioChoice, record, importAudio, review, preview, finish, done }
    enum Method { case record, file }
    @Published var page: Page = .platform
    @Published var provider: APIProvider = .bailian
    @Published var method: Method = .record
    @Published var name = ""
    @Published var rights = false
    @Published var consent = false
    @Published private(set) var audio: PreparedVoiceAudio?
    @Published private(set) var recording: URL?
    @Published private(set) var filename = ""
    @Published private(set) var audioMethod: Method?
    @Published private(set) var loading = false
    @Published var error: String?
    @Published private(set) var voiceID: UUID?
    @Published private(set) var applied = false
    let recorder = VoiceRecorder()
    private(set) var workspace: URL?
    private var preparation: Task<Void,Never>?
    private var preparationID = UUID()
    private var started = false
    private(set) var closed = false
    let speech: CompanionSpeech
    let controller: PersonalVoiceController
    let copy: Copybook
    init(speech: CompanionSpeech, controller: PersonalVoiceController, copy: Copybook) {
        self.speech=speech; self.controller=controller; self.copy=copy
    }
    var step: Int {
        switch page { case .platform: 0; case .audioChoice,.record,.importAudio: 1; case .review: 2; case .preview: 3; case .finish,.done: 4 }
    }
    var current: PersonalVoice? { controller.voices.first { $0.id == voiceID } }
    var localBusy: Bool { loading || recorder.recording || recorder.starting || recorder.finishing }
    var dirty: Bool { audio != nil || localBusy || current != nil || controller.busy || !name.isEmpty }
    var verified: Bool { current.map { speech.canUse($0) && !controller.hasRecovery($0) } ?? false }
    var canAdvance: Bool {
        guard !closed, !localBusy, !controller.busy, workspace != nil else { return false }
        switch page {
        case .platform: return speech.configuredProviders.contains(provider)
        case .audioChoice: return true
        case .record,.importAudio: return validAudio
        case .review: return current == nil && validAudio && PersonalVoice.validName(name) && rights && consent
        case .preview,.finish: return verified
        case .done: return true
        }
    }
    var validAudio: Bool {
        guard let audio else { return false }
        return (try? VoiceAudioPreparation.validate(duration:audio.duration,bytes:audio.bytes,provider:provider)) != nil
    }
    var canGoBack: Bool { !closed && !localBusy && !controller.busy && (current == nil && page != .platform || page == .finish) }
    func start() {
        guard !started, !closed else { return }; started=true
        controller.resetWizardResult()
        provider=speech.configuredProviders.contains(speech.provider) ? speech.provider : speech.configuredProviders.first ?? .bailian
        do {
            let url=FileManager.default.temporaryDirectory.appendingPathComponent("zhaoxi-voice-"+UUID().uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:url,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]); workspace=url
        } catch { self.error=copy.text("无法准备临时录音目录，请关闭后重试。","Could not prepare temporary audio storage. Close and try again.") }
        recorder.completed = { [weak self] url in self?.prepare(url, recorded:true) }
    }
    func selectProvider(_ value: APIProvider) {
        guard !closed, !controller.busy, !localBusy, current == nil else { return }
        guard value != provider else { return }
        provider=value; rights=false; consent=false; error=nil
        if audio != nil && !validAudio { error=copy.text("已保留上一次样本，但它不符合新平台的时长或大小要求，请重新准备。","The sample is retained but does not meet this provider's duration or size limits. Prepare another sample.") }
    }
    func back() {
        guard canGoBack else { return }; error=nil; recorder.stopPlayback(); controller.stopAudio()
        switch page {
        case .audioChoice: page = .platform
        case .record,.importAudio: page = .audioChoice
        case .review: page = method == .record ? .record : .importAudio
        case .finish: page = .preview
        default: break
        }
    }
    func advance() {
        guard canAdvance else { return }; error=nil; recorder.stopPlayback()
        switch page {
        case .platform: page = .audioChoice
        case .audioChoice: page = method == .record ? .record : .importAudio
        case .record,.importAudio: page = .review
        case .review: controller.create(audio:audio!,provider:provider,name:name,consent:rights && consent,copy:copy)
        case .preview: controller.stopAudio(); page = .finish
        default: break
        }
    }
    func synchronize() {
        guard !closed else { return }
        if let created=controller.lastCreated { voiceID=created.id }
        // A failed, definitively rejected creation removes its pending record.
        if let voiceID, !controller.voices.contains(where:{$0.id == voiceID}), controller.lastCreated == nil { self.voiceID=nil }
        if page == .review, let current, [.created,.verified].contains(current.state), !controller.hasRecovery(current) { page = .preview }
    }
    func restartSample() {
        guard !closed, !controller.busy else { return }
        controller.clearAudio(); controller.resetWizardResult(); voiceID=nil; rights=false; consent=false; error=nil; page = .audioChoice
        // Retain the local sample until its replacement passes local checks.
    }
    func finish(use: Bool) -> Bool {
        guard !closed, verified, !controller.busy else { return false }
        if use, let current, !speech.usePersonalVoice(current,copy:copy) { error=speech.dialog; speech.dialog=nil; return false }
        applied=use; controller.stopAudio(); page = .done; return true
    }
    func record() {
        guard !closed, !localBusy, let workspace else { return }
        error=nil; recorder.start(url:workspace.appendingPathComponent(UUID().uuidString+".wav"),copy:copy)
    }
    func prepare(_ url: URL, recorded: Bool = false) {
        guard !closed, let workspace, current == nil else { return }
        preparation?.cancel(); let id=UUID(); preparationID=id; loading=true; error=nil; recorder.error=nil; recorder.stopPlayback()
        let vendor=provider, destination=workspace.appendingPathComponent(UUID().uuidString+".wav")
        preparation=Task { [weak self] in
            let worker=Task.detached {
                let access=url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                return try VoiceAudioPreparation.prepare(source:url,destination:destination,provider:vendor)
            }
            do {
                let prepared=try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard let self, preparationID == id, !closed, !Task.isCancelled else { return }
                audio=prepared; recording=recorded ? url:nil; filename=recorded ? copy.text("本次录音","This recording"):url.lastPathComponent
                audioMethod=recorded ? .record:.file; rights=false; consent=false; loading=false
            } catch {
                guard let self, preparationID == id, !closed else { return }
                loading=false; self.error=(error as? VoiceCloneError)?.message(copy) ?? VoiceCloneError.invalidAudio.message(copy)
            }
        }
    }
    func waitForPreparation() async { await preparation?.value }
    func cleanup() {
        guard !closed else { return }; closed=true
        preparationID=UUID(); let pending=preparation; pending?.cancel(); recorder.cancel(); controller.cancel()
        if let workspace {
            try? FileManager.default.removeItem(at:workspace); self.workspace=nil
            Task { await pending?.value; try? FileManager.default.removeItem(at:workspace) }
        }
    }
}
