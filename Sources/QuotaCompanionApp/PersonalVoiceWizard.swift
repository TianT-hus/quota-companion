import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PersonalVoiceWizard: View {
    @ObservedObject var speech: CompanionSpeech
    @ObservedObject var controller: PersonalVoiceController
    let copy: Copybook
    @StateObject var draft: VoiceWizardSession
    @ObservedObject var recorder: VoiceRecorder
    @StateObject var owner = DialogOwner()
    @Environment(\.ownedDismiss) private var dismiss
    @State var configure=false
    @State var guide=false
    @State var confirmation: VoiceWizardConfirmation?
    @State var size=CGSize(width:868,height:728)
    init(speech:CompanionSpeech,controller:PersonalVoiceController,copy:Copybook,session:VoiceWizardSession? = nil) {
        self.speech=speech; self.controller=controller; self.copy=copy
        let state=session ?? VoiceWizardSession(speech:speech,controller:controller,copy:copy)
        _draft=StateObject(wrappedValue:state); recorder=state.recorder
    }
    var c: Copybook { copy }
    var current: PersonalVoice? { draft.current }
    var busy: Bool { controller.busy || draft.localBusy }
    var message: String? { draft.error ?? recorder.error ?? controller.error }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:8) {
                    Text(c.text("添加我的声音","Add my voice")).font(.system(size:23,weight:.semibold))
                    Text(draft.page == .platform ? c.text("用自己的声音，播报日程与额度提醒","Use your voice for schedules and quota alerts") : draft.provider.name+" · "+c.text("声音复刻","Voice cloning"))
                        .font(.system(size:12)).foregroundStyle(WizardStyle.secondary)
                }
                Spacer()
                Label(draft.step < 2 ? c.text("确认前不上传","No upload before consent") : c.text("仅所选平台","Selected provider only"),systemImage:"lock.shield")
                    .font(.system(size:11)).foregroundStyle(WizardStyle.secondary)
            }
            Divider()
            WizardStepBar(titles:[c.text("选择平台","Provider"),c.text("准备声音","Sample"),c.text("检查并创建","Review & create"),c.text("试听效果","Preview"),c.text("完成并使用","Finish & use")],step:draft.step,complete:draft.page == .done,copy:c)
            Divider()
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment:.leading,spacing:22) {
                        VStack(alignment:.leading,spacing:12) {
                            HStack(alignment:.firstTextBaseline) {
                                Text(title).font(.system(size:21,weight:.semibold)).fixedSize(horizontal:false,vertical:true)
                                Spacer(minLength:12)
                                Text(c.text("第 \(draft.step+1) / 5 步","Step \(draft.step+1) of 5")).font(.system(size:12,weight:.medium)).foregroundStyle(WizardStyle.secondary).fixedSize()
                            }
                            Text(subtitle).foregroundStyle(WizardStyle.secondary).fixedSize(horizontal:false,vertical:true)
                        }.id("top")
                        if VoiceCloneQA.enabled { note(c.text("隔离模拟验收 · 不上传、不计费、不生成真实声音","Isolated simulation · No uploads, charges or real voices"),icon:"testtube.2") }
                        if let message { Label(message,systemImage:"exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Color.red.opacity(0.04),in:RoundedRectangle(cornerRadius:8)).accessibilityIdentifier("voiceWizard.error") }
                        if controller.busy { HStack { ProgressView().controlSize(.small); Text(controller.phase.title(c)); Spacer(); Text(c.text("请勿重复提交","Please do not submit again")).foregroundStyle(WizardStyle.secondary) }.accessibilityElement(children:.combine) }
                        if draft.loading || recorder.finishing || recorder.starting {
                            HStack { ProgressView().controlSize(.small); Text(recorder.starting ? c.text("正在准备录音…","Preparing recording…"):c.text("正在本机检查音频…","Checking audio locally…")) }
                        }
                        content
                    }.padding(.vertical,3).padding(.horizontal,2)
                }.onChange(of:draft.page) { _,_ in scroll.scrollTo("top",anchor:.top) }
                    .onChange(of:message) { _,new in if new != nil { scroll.scrollTo("top",anchor:.top) } }
            }.frame(maxHeight:.infinity)
            Divider()
            footer
        }.font(.system(size:13)).foregroundStyle(ManagementStyle.ink).tint(WizardStyle.blue)
            .padding(28).frame(width:size.width,height:size.height).background(.white)
            .background(DialogOwnerReader(owner:owner)).interactiveDismissDisabled()
            .onAppear { draft.start(); fitScreen(); installQuitGuard() }
            .onReceive(NotificationCenter.default.publisher(for:NSWindow.didChangeScreenNotification)) { n in if let w=n.object as? NSWindow, w === owner.window { fitScreen() } }
            .onDisappear { cleanup() }
            .onChange(of:controller.lastCreated) { _,_ in draft.synchronize() }
            .onChange(of:controller.revision) { _,_ in draft.synchronize() }
            .onChange(of:controller.busy) { _,_ in draft.synchronize() }
            .ownedSheet(isPresented:$configure) { APIConfigurationEditor(speech:speech,copy:c) }
            .ownedSheet(item:$confirmation) { item in VoiceWizardConfirmView(kind:item,provider:draft.provider,copy:c) { confirmed(item) } }
    }
    private func fitScreen() {
        let visible=(owner.window?.screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width:1000,height:900)
        size=CGSize(width:min(868,max(580,visible.width-48)),height:min(728,max(480,visible.height-72)))
    }
    @ViewBuilder var content: some View {
        switch draft.page {
        case .platform: platformPage
        case .audioChoice: methodPage
        case .record: recordPage
        case .importAudio: importPage
        case .review: reviewPage
        case .preview: previewPage
        case .finish,.done: finishPage
        }
    }
    var title: String {
        switch draft.page {
        case .platform: c.text("选择声音复刻平台","Choose your voice provider")
        case .audioChoice: c.text("你想怎样准备声音？","How would you like to prepare your sample?")
        case .record: c.text("录下你平时说话的声音","Record your everyday voice")
        case .importAudio: c.text("选择一段清晰的单人录音","Choose a clear, single-speaker recording")
        case .review: current?.state == .pending ? c.text("先确认上一次创建的结果","Check the previous request first") : c.text("确认样本，再上传创建","Review your sample before uploading")
        case .preview: c.text("听听复刻后的效果","Listen to your cloned voice")
        case .finish: c.text("声音已准备好，要现在使用吗？","Your voice is ready. Use it now?")
        case .done: draft.applied ? c.text("已用于日常播报","Ready for daily announcements"):c.text("已保留在“我的声音”","Saved in My voices")
        }
    }
    var subtitle: String {
        switch draft.page {
        case .platform: c.text("只需配置一个平台。接下来准备样本、确认创建并试听，无需填写模型或音色 ID。","One provider is enough. Prepare a sample, confirm creation and preview it—no model or voice IDs needed.")
        case .audioChoice: c.text("准备声音 · 1/2　直接录音和导入文件都可以，接下来只显示你选择的方式。","Sample · 1/2. Record here or import a file; next, follow the instructions for your choice.")
        case .record: c.text("准备声音 · 2/2　建议录制 15～20 秒，自然朗读即可；停止后先回听，再继续。","Sample · 2/2. Aim for 15–20 seconds in your natural voice. Stop, listen back, then continue.")
        case .importAudio: c.text("准备声音 · 2/2　文件只在本机检查，原始文件不会改变，也不会在这一步上传。","Sample · 2/2. The file is checked locally. The original is unchanged and nothing is uploaded yet.")
        case .review: c.text("这是第一次会上传样本的操作。核对平台和声音名称，并阅读授权与费用说明。","This is the first action that uploads your sample. Check the provider, name, permission and billing notice.")
        case .preview: c.text("创建与试听是两次不同的操作。主动生成试听，确认效果后才能用于日常播报。","Creation and preview are separate actions. Generate a preview explicitly before using this voice for announcements.")
        case .finish: c.text("创建和正式合成验证已完成。只有你选择“用于日常播报”，当前声音才会改变。","Creation and synthesis verification are complete. Your current voice changes only if you choose Use for announcements.")
        case .done: c.text("以后可在语音页的声音列表里选择，也可在“管理我的声音”中继续管理。","Select this voice in the voice list later, or open Manage my voices.")
        }
    }
    var footer: some View {
        HStack(spacing:12) {
            if draft.page != .done { Button(c.text("取消","Cancel"),action:requestClose).keyboardShortcut(.cancelAction).accessibilityIdentifier("voiceWizard.cancel") }
            Spacer(minLength:8)
            if draft.canGoBack { Button(c.text("上一步","Back")) { draft.back() }.accessibilityIdentifier("voiceWizard.back") }
            if draft.page == .done {
                Button(c.text("返回语音设置","Back to voice settings"),action:close).buttonStyle(WizardButtonStyle(primary:true)).accessibilityIdentifier("voiceWizard.close")
            } else if draft.page == .finish {
                Button(c.text("暂不切换","Keep current voice")) { _ = draft.finish(use:false) }.disabled(!draft.verified || busy).accessibilityIdentifier("voiceWizard.keep")
                Button(c.text("用于日常播报","Use for announcements")) { _ = draft.finish(use:true) }.buttonStyle(WizardButtonStyle(primary:true)).disabled(!draft.canAdvance).accessibilityIdentifier("voiceWizard.use")
            } else if draft.page == .review && current != nil {
                Text(controller.busy ? c.text("处理中…","Processing…"):c.text("请先处理上方的创建状态","Resolve the creation status above first")).foregroundStyle(WizardStyle.secondary).font(.system(size:12))
            } else {
                Button(draft.page == .review ? c.text("同意上传并创建声音","Agree, upload and create"):c.text("下一步","Next")) { draft.advance() }
                    .buttonStyle(WizardButtonStyle(primary:true)).disabled(!draft.canAdvance).accessibilityIdentifier("voiceWizard.next")
            }
        }.buttonStyle(WizardButtonStyle()).frame(minHeight:36)
    }
    func chooseAudio() {
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.wav,.mp3,.mpeg4Audio]; panel.allowsMultipleSelection=false
        panel.beginOwned(parent:owner.window) { response in if response == .OK, let url=panel.url { draft.prepare(url) } }
    }
    func exportRecording() {
        guard let recording=draft.recording else { return }
        let panel=NSSavePanel(); panel.allowedContentTypes=[.wav]; panel.nameFieldStringValue=c.text("我的录音.wav","My recording.wav")
        panel.beginOwned(parent:owner.window) { response in
            guard response == .OK, let url=panel.url else { return }
            do { try Data(contentsOf:recording).write(to:url,options:.atomic) } catch { draft.error=c.text("导出失败，录音仍保留在本次向导中。","Export failed. Your recording is still in this wizard.") }
        }
    }
    func requestPreview(regenerate:Bool) {
        guard let current, !busy else { return }
        if !regenerate && controller.hasCachedPreview(current) { controller.audition(current,copy:c) }
        else { confirmation=regenerate ? .regenerate:.preview }
    }
    func requestClose() { if draft.dirty && draft.page != .done { confirmation = .discard } else { close() } }
    private func confirmed(_ action:VoiceWizardConfirmation) {
        switch action {
        case .discard: close()
        case .rerecord: draft.restartSample()
        case .preview,.regenerate: if let current { controller.audition(current,regenerate:action == .regenerate,copy:c) }
        }
    }
    private func close() { cleanup(); dismiss() }
    private func cleanup() { VoiceDraftLifecycle.mayTerminate=nil; draft.cleanup() }
    private func installQuitGuard() {
        VoiceDraftLifecycle.mayTerminate = {
            if draft.dirty && draft.page != .done {
                let alert=NSAlert(); alert.messageText=c.text("放弃声音草稿并退出？","Discard voice draft and quit?")
                alert.informativeText=c.text("临时音频会清理。已创建或结果待确认的云端声音保留在管理页；退出不代表平台已取消。","Temporary audio will be cleared. Created or uncertain voices stay in the manager; quitting does not cancel a remote operation.")
                alert.addButton(withTitle:c.text("继续编辑","Keep editing")); alert.addButton(withTitle:c.text("放弃并退出","Discard and quit"))
                guard alert.runOwnedModal(parent:owner.window) == .alertSecondButtonReturn else { return false }
            }
            cleanup(); return true
        }
    }
    func card<V:View>(@ViewBuilder _ content:()->V) -> some View {
        content().padding(20).frame(maxWidth:.infinity,alignment:.leading).background(.white,in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).strokeBorder(WizardStyle.line))
    }
    func note(_ text:String,icon:String="info.circle") -> some View {
        Label(text,systemImage:icon).font(.system(size:12)).foregroundStyle(WizardStyle.secondary).fixedSize(horizontal:false,vertical:true)
    }
    func summary(_ label:String,_ value:String) -> some View {
        HStack(alignment:.top,spacing:14) { Text(label).foregroundStyle(WizardStyle.secondary).frame(width:100,alignment:.leading); Text(value).frame(maxWidth:.infinity,alignment:.leading) }
    }
}

enum VoiceWizardConfirmation: String,Identifiable { case discard,rerecord,preview,regenerate; var id:String { rawValue } }
struct VoiceWizardConfirmView: View {
    let kind:VoiceWizardConfirmation; let provider:APIProvider; let copy:Copybook; let action:()->Void
    @Environment(\.ownedDismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Text(kind == .discard ? copy.text("关闭声音向导？","Close the voice wizard?"):kind == .rerecord ? copy.text("重新准备声音？","Prepare another sample?"):copy.text("生成云端试听？","Generate a cloud preview?")).font(.system(size:18,weight:.semibold))
            Text(kind == .discard ? copy.text("临时录音和试听会清理。已创建或结果待确认的声音仍保留在“管理我的声音”。关闭不代表平台已取消；原始导入文件和导出的录音不受影响。","Temporary recordings and previews will be cleared. Created or uncertain voices stay in Manage my voices. Closing does not cancel remote work; original imports and exported recordings stay unchanged."):kind == .rerecord ? copy.text("当前云端声音不会删除。可重新录音或导入；再次创建会产生新的音色，并可能再次计费。","The current cloud voice will remain. Record or import another sample; another creation makes a new voice and may incur another charge."):previewBilling(copy,provider:provider))
                .foregroundStyle(WizardStyle.secondary).fixedSize(horizontal:false,vertical:true)
            HStack {
                Button(kind == .discard ? copy.text("继续编辑","Keep editing"):copy.text("取消","Cancel")) { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("voiceWizard.confirm.cancel")
                Spacer()
                Button(kind == .discard ? copy.text("关闭向导","Close wizard"):kind == .rerecord ? copy.text("返回准备","Prepare sample"):copy.text("同意并生成","Agree and generate")) { dismiss(); action() }
                    .buttonStyle(WizardButtonStyle(primary:true)).accessibilityIdentifier("voiceWizard.confirm.accept")
            }.buttonStyle(WizardButtonStyle())
        }.padding(24).frame(width:440).fixedSize(horizontal:false,vertical:true)
    }
}
