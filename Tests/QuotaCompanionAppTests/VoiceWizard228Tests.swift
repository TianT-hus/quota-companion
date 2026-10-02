import AppKit
import AVFoundation
import SwiftUI
import Testing
@testable import QuotaCompanionApp

@MainActor private final class Key228: SpeechCredentials {
    var reads=0
    func read() throws -> String { reads += 1; return "test-fixture-only" }
    func save(_ value:String) throws {}
}
private actor Clone228: VoiceCloningServicing {
    var creates=0, checks=0
    let timeout:Bool
    init(timeout:Bool=false) { self.timeout=timeout }
    func create(_ voice:PersonalVoice,audio:Data,endpoint:String,key:String,phase:@escaping @Sendable (VoiceClonePhase) async -> Void) async throws -> PersonalVoice {
        creates += 1; await phase(.creating)
        if timeout { throw CloudSpeechError.timeout }
        var v=voice; v.remoteID="mock-only-"+v.operationName; v.state = .created; return v
    }
    func find(_ voice:PersonalVoice,endpoint:String,key:String) async throws -> PersonalVoice { checks += 1; var v=voice; v.remoteID="mock-only-"+v.operationName; v.state = .created; return v }
    func delete(_ voice:PersonalVoice,endpoint:String,key:String) async throws {}
}
private actor Synth228: CloudSpeechSynthesizing {
    var calls=0
    func synthesize(text:String,language:SpeechLanguage,voice:String,key:String) async throws -> Data { calls += 1; return Data([0]) }
}
@MainActor private final class Player228: CloudAudioPlaying {
    func play(_ data:Data,rate:Double,volume:Double) throws {}
    func stop() {}
}
@MainActor private final class Fixture228 {
    let root=URL.temporaryDirectory.appendingPathComponent("voice228-"+UUID().uuidString)
    let suite="voice228-"+UUID().uuidString
    let defaults:UserDefaults
    let key=Key228(), synth=Synth228(), service:Clone228
    let speech:CompanionSpeech
    let controller:PersonalVoiceController
    let s:VoiceWizardSession
    let copy:Copybook
    init(configured:Bool=true,timeout:Bool=false,language:AppLanguage = .zhHans) throws {
        defaults=try #require(UserDefaults(suiteName:suite)); copy=Copybook(language:language)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        speech=CompanionSpeech(defaults:defaults,directory:root,credentials:key)
        if configured { for p in APIProvider.allCases { #expect(speech.saveAPI(provider:p,address:p.endpoint,key:"",consent:true,copy:copy)) } }
        service=Clone228(timeout:timeout)
        controller=PersonalVoiceController(speech:speech,directory:root,service:service,synth:synth,player:Player228())
        s=VoiceWizardSession(speech:speech,controller:controller,copy:copy); s.start()
    }
    func tone(seconds:Double=16) throws -> URL {
        let url=root.appendingPathComponent("synthetic-test-signal.wav")
        let format=try #require(AVAudioFormat(standardFormatWithSampleRate:24000,channels:1))
        let buffer=try #require(AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(seconds*24000)))
        buffer.frameLength=buffer.frameCapacity
        for i in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][i]=Float(sin(Double(i)*2*Double.pi*440/24000)*0.15) }
        let file=try AVAudioFile(forWriting:url,settings:format.settings); try file.write(from:buffer)
        return url
    }
    func review() async throws {
        s.advance(); s.method = .file; s.advance(); s.prepare(try tone()); await s.waitForPreparation(); s.advance(); s.name="我的测试声音"
        #expect(s.page == .review && s.validAudio)
    }
    func created() async throws {
        try await review(); s.rights=true; s.consent=true; s.advance(); await controller.task?.value; s.synchronize()
    }
    func verified() async throws {
        try await created(); controller.audition(try #require(s.current),copy:copy); await controller.task?.value; s.synchronize()
    }
    func cleanup() { s.cleanup(); speech.stop(); defaults.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:root) }
}

@Suite(.serialized) @MainActor struct VoiceWizard228Tests {
    @Test func navigationRetainsDraftAndDoesNotAuthorizeNetwork() async throws {
        let f=try Fixture228(); defer { f.cleanup() }
        #expect(f.s.step == 0 && f.s.canAdvance)
        try await f.review(); f.s.rights=true
        #expect(!f.s.canAdvance)
        f.s.advance(); #expect(!f.controller.busy && f.key.reads == 0)
        f.s.back(); #expect(f.s.page == .importAudio && f.s.step == 1 && f.s.name == "我的测试声音")
        f.s.back(); f.s.method = .record; f.s.advance()
        #expect(f.s.page == .record && f.s.audio != nil && !f.s.recorder.recording)
        f.s.back(); f.s.back(); #expect(f.s.page == .platform && f.s.audio != nil)
        f.s.selectProvider(.minimax); #expect(!f.s.rights && !f.s.consent)
        #expect(f.key.reads == 0); #expect(await f.service.creates == 0); #expect(await f.synth.calls == 0)
    }
    @Test func missingConfigurationAndInvalidNameBlockNext() async throws {
        let f=try Fixture228(configured:false); defer { f.cleanup() }
        f.s.advance(); #expect(f.s.page == .platform && !f.s.canAdvance && f.key.reads == 0)
        #expect(f.speech.saveAPI(provider:.bailian,address:APIProvider.bailian.endpoint,key:"",consent:true,copy:f.copy))
        try await f.review(); f.s.rights=true; f.s.consent=true
        f.s.name=" \n"; #expect(!f.s.canAdvance)
        f.s.name=String(repeating:"字",count:31); #expect(!f.s.canAdvance)
        f.s.name="小明 👩🏽‍💻"; #expect(f.s.canAdvance && f.key.reads == 0)
    }
    @Test func invalidReplacementAndProviderChangeRetainOriginal() async throws {
        let f=try Fixture228(); defer { f.cleanup() }
        let source=try f.tone(seconds:5), bytes=try Data(contentsOf:source)
        f.s.prepare(source); await f.s.waitForPreparation(); let prepared=try #require(f.s.audio)
        f.s.prepare(f.root.appendingPathComponent("missing.wav")); await f.s.waitForPreparation()
        #expect(f.s.error != nil && f.s.audio?.url == prepared.url)
        f.s.selectProvider(.minimax); #expect(!f.s.validAudio && f.s.audio != nil)
        f.s.selectProvider(.bailian); #expect(f.s.validAudio)
        let workspace=try #require(f.s.workspace); f.s.cleanup()
        #expect(!FileManager.default.fileExists(atPath:workspace.path))
        #expect(try Data(contentsOf:source) == bytes)
        f.s.advance(); #expect(!f.s.canAdvance && f.key.reads == 0)
    }
    @Test func unknownCreationStaysInReviewUntilExplicitQuery() async throws {
        let f=try Fixture228(timeout:true); defer { f.cleanup() }
        try await f.created()
        #expect(f.s.page == .review && f.s.current?.state == .pending && !f.s.canAdvance && !f.s.canGoBack)
        f.s.advance(); #expect(await f.service.creates == 1)
        f.controller.check(try #require(f.s.current),copy:f.copy); await f.controller.task?.value; f.s.synchronize()
        #expect(f.s.page == .preview && !f.s.verified && !f.s.canAdvance)
        #expect(await f.service.checks == 1)
        #expect(!f.s.finish(use:true) && f.speech.source == .local)
    }
    @Test func previewGateAndExplicitUsePreserveReminderSwitches() async throws {
        let f=try Fixture228(); defer { f.cleanup() }
        let reminders=f.speech.configuration.value.quota.enabled, schedule=f.speech.scheduleEnabled
        try await f.created(); #expect(f.s.page == .preview && !f.s.canAdvance && !f.s.finish(use:true))
        #expect(f.speech.source == .local)
        f.controller.audition(try #require(f.s.current),copy:f.copy); await f.controller.task?.value; f.s.synchronize()
        #expect(f.s.verified && f.s.canAdvance)
        f.controller.audition(try #require(f.s.current),copy:f.copy); #expect(await f.synth.calls == 1)
        f.s.advance(); #expect(f.s.page == .finish && f.speech.source == .local)
        f.s.back(); #expect(f.s.page == .preview && f.s.verified)
        f.s.advance(); #expect(f.s.finish(use:true) && f.s.page == .done && f.s.applied)
        #expect(f.speech.selectedPersonalVoice()?.id == f.s.current?.id)
        #expect(f.speech.scheduleEnabled == schedule && f.speech.configuration.value.quota.enabled == reminders)
    }
    @Test func keepCurrentAndRestartSampleKeepCloudRecords() async throws {
        let f=try Fixture228(); defer { f.cleanup() }
        try await f.verified(); let first=try #require(f.s.current)
        f.s.restartSample(); #expect(f.s.page == .audioChoice && f.s.current == nil && f.s.audio != nil)
        #expect(f.controller.voices.contains(where:{$0.id == first.id}) && !f.controller.hasCachedPreview(first))
        f.s.method = .file; f.s.advance(); f.s.advance(); f.s.rights=true; f.s.consent=true
        f.s.advance(); await f.controller.task?.value; f.s.synchronize()
        f.controller.audition(try #require(f.s.current),copy:f.copy); await f.controller.task?.value; f.s.synchronize(); f.s.advance()
        #expect(f.s.finish(use:false) && f.s.page == .done && !f.s.applied && f.speech.source == .local)
        #expect(f.controller.voices.count == 2)
    }
    @Test func localSaveFailureBlocksProgressAndOnlyRetriesSaving() async throws {
        let f=try Fixture228(); defer { f.cleanup() }
        let destination=f.root.appendingPathComponent("speech-settings-v3.json")
        try FileManager.default.removeItem(at:destination)
        try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:false)
        try await f.created()
        let voice=try #require(f.s.current)
        #expect(voice.state == .created && f.controller.hasRecovery(voice))
        #expect(f.s.page == .review && !f.s.canAdvance && !f.s.finish(use:true))
        f.s.advance(); #expect(await f.service.creates == 1)
        try FileManager.default.removeItem(at:destination)
        f.controller.retrySave(voice,copy:f.copy); f.s.synchronize()
        #expect(f.s.page == .preview && !f.controller.hasRecovery(voice) && !f.s.verified)
        #expect(await f.service.creates == 1)
    }
    @Test func nativePageEvidence() async throws {
        guard let path=ProcessInfo.processInfo.environment["QUOTA_VOICE_0228_PREVIEW"] else { return }
        _ = NSApplication.shared
        let out=URL(fileURLWithPath:path); try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        let audioFixture=try Fixture228()
        try Data(contentsOf:audioFixture.tone()).write(to:out.appendingPathComponent("synthetic-test-signal.wav"))
        audioFixture.cleanup()
        for language in [AppLanguage.zhHans,.english] {
            for id in ["01-platform","02-method","02a-record","02b-import","02c-ready","03-review","03b-uncertain","04-preview","04b-verified","05-use","05b-done"] {
                let f=try Fixture228(timeout:id == "03b-uncertain",language:language)
                defer { f.cleanup() }
                switch id {
                case "02-method": f.s.advance()
                case "02a-record": f.s.advance(); f.s.advance()
                case "02b-import": f.s.advance(); f.s.method = .file; f.s.advance()
                case "02c-ready": try await f.review(); f.s.back()
                case "03-review": try await f.review()
                case "03b-uncertain","04-preview": try await f.created()
                case "04b-verified": try await f.verified()
                case "05-use": try await f.verified(); f.s.advance()
                case "05b-done": try await f.verified(); f.s.advance(); #expect(f.s.finish(use:false))
                default: break
                }
                let host=NSHostingView(rootView:PersonalVoiceWizard(speech:f.speech,controller:f.controller,copy:f.copy,session:f.s).environment(\.colorScheme,.light))
                let window=NSWindow(contentRect:.init(x:0,y:0,width:868,height:728),styleMask:[.titled],backing:.buffered,defer:false)
                window.isReleasedWhenClosed=false; window.contentView=host; window.orderFront(nil)
                try await Task.sleep(for:.milliseconds(250)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                let full=host.superview ?? host, bitmap=try #require(full.bitmapImageRepForCachingDisplay(in:full.bounds))
                full.cacheDisplay(in:full.bounds,to:bitmap)
                try #require(bitmap.representation(using:.png,properties:[:])).write(to:out.appendingPathComponent("\(language.rawValue)-\(id).png"))
                window.close()
            }
        }
    }
}
