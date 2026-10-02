import AppKit
import SwiftUI
import UniformTypeIdentifiers

let voiceReadingExample = "你好，这是我平时说话的声音。今天我会按自己的节奏安排工作，先整理资料，再完成重要的任务。需要休息的时候，请温柔地提醒我，让每一天都过得清楚、有序。"

@MainActor enum VoiceDraftLifecycle {
    static var mayTerminate: (() -> Bool)?
}

extension PersonalVoiceState {
    func title(_ c: Copybook) -> String {
        switch self {
        case .pending: c.text("结果待确认", "Result uncertain")
        case .created: c.text("已创建，待验证", "Created, not verified")
        case .verified: c.text("已验证", "Verified")
        case .deleted: c.text("云端已删除，待保存", "Deleted remotely, save pending")
        }
    }
}
extension VoiceClonePhase {
    func title(_ c: Copybook) -> String {
        switch self {
        case .preparing: c.text("准备音频", "Preparing audio")
        case .uploading: c.text("上传音频", "Uploading audio")
        case .creating: c.text("创建声音", "Creating voice")
        case .checking: c.text("查询声音", "Checking voice")
        case .previewing: c.text("生成试听", "Generating preview")
        case .deleting: c.text("删除声音", "Deleting voice")
        }
    }
}

func previewBilling(_ c: Copybook, provider: APIProvider) -> String {
    provider == .minimax
    ? c.text("MiniMax 正式合成试听可能包含音色首次使用费用和合成费用。未正式调用的复刻音色可能在 7 天后被清理。重新生成会再次调用服务。", "MiniMax preview uses formal synthesis and may include first-use and synthesis fees. Voices not used for formal synthesis may be removed after 7 days. Generating again makes another paid request.")
    : c.text("使用百炼绑定的复刻模型合成固定示例，可能产生合成费用。重新生成会再次调用服务。", "The fixed sample uses the bound Bailian cloning model and may incur synthesis fees. Generating again makes another request.")
}
@ViewBuilder func billingLinks(_ c: Copybook) -> some View {
    HStack {
        Link(c.text("百炼计费说明", "Bailian pricing"), destination: URL(string: "https://help.aliyun.com/zh/model-studio/model-pricing")!)
        Link(c.text("MiniMax 复刻与计费规则", "MiniMax cloning and billing"), destination: URL(string: "https://platform.minimax.cn/docs/api-reference/voice-cloning-clone")!)
    }
}

struct PersonalVoiceManager: View {
    @ObservedObject var speech: CompanionSpeech
    @ObservedObject var controller: PersonalVoiceController
    let copy: Copybook
    @Environment(\.ownedDismiss) private var dismiss
    @State private var selected: PersonalVoice?
    @State private var action = ""
    @State private var confirm = false
    @State private var renaming = false
    @State private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(copy.text("管理我的声音", "Manage my voices")).font(.headline)
            Text(copy.text("仅管理朝夕创建的声音。删除当前音色前，请在语音页为使用它的每种语言选择替代声音。", "Only voices created by this app are managed here. Before deleting a selected voice, choose a replacement for each language using it."))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if controller.voices.isEmpty { Text(copy.text("还没有个人音色，请先点击“添加我的声音”。", "No personal voices yet. Choose Add my voice first.")) }
                    ForEach(controller.voices) { voice in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text(voice.name).fontWeight(.semibold); Spacer(); Text(voice.provider.name) }
                            Text(voice.createdAt.formatted(date: .abbreviated, time: .shortened) + " · " + voice.state.title(copy)).foregroundStyle(.secondary)
                            if voice.deletionPending == true { Text(copy.text("删除结果待确认，请主动查询；不会自动重试删除。", "Deletion result uncertain. Check explicitly; deletion will not retry automatically.")) }
                            if speech.usesPersonalVoice(voice) { Text(copy.text("当前正在使用", "Currently selected")).foregroundStyle(.blue) }
                            HStack {
                                if controller.hasRecovery(voice), voice.state != .pending { Button(copy.text("重试保存", "Retry save")) { controller.retrySave(voice, copy: copy) } }
                                if voice.state != .deleted {
                                    Button(copy.text("改名", "Rename")) { selected = voice; name = voice.name; renaming = true }
                                    Button(copy.text("查询", "Check")) { controller.check(voice, copy: copy) }
                                    if voice.state != .pending {
                                        Button(copy.text("试听", "Preview")) { if controller.hasCachedPreview(voice) { controller.audition(voice, copy: copy) } else { selected = voice; action = "preview"; confirm = true } }
                                        Button(copy.text("启用", "Use")) { _ = speech.usePersonalVoice(voice, copy: copy); if let error = speech.dialog { controller.error = error; speech.dialog = nil } }.disabled(!speech.canUse(voice) || controller.hasRecovery(voice))
                                        Button(copy.text("删除", "Delete")) { selected = voice; action = "delete"; confirm = true }.disabled(speech.usesPersonalVoice(voice))
                                    }
                                }
                            }.disabled(controller.busy)
                        }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 10))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 290)
            if controller.busy { HStack { ProgressView().controlSize(.small); Text(controller.phase.title(copy)) } }
            if let error = controller.error { Text(error).foregroundStyle(.red) }
            HStack { Button(copy.text("停止试听", "Stop preview")) { controller.stopAudio() }; Spacer(); Button(copy.text("关闭", "Close")) { controller.cancel(); dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 590).font(.system(size: 13)).interactiveDismissDisabled().onDisappear { controller.cancel() }
        .ownedAlert(action == "delete" ? copy.text("删除云端声音？", "Delete cloud voice?") : copy.text("生成试听？", "Generate preview?"), isPresented: $confirm) {
            Button(copy.text("取消", "Cancel"), role: .cancel) {}
            Button(action == "delete" ? copy.text("确认删除", "Delete voice") : copy.text("同意并生成", "Agree and generate")) {
                guard let selected else { return }
                if action == "delete" { controller.delete(selected, copy: copy) } else { controller.audition(selected, copy: copy) }
            }
        } message: { Text(action == "delete" ? copy.text("将删除平台音色与本地记录，可能影响同一账户下其他应用。此操作不可恢复。", "This removes the provider voice and local record and may affect other apps on the same account. This cannot be undone.") : previewBilling(copy, provider: selected?.provider ?? .bailian)) }
        .ownedSheet(isPresented: $renaming) {
            VStack(alignment: .leading, spacing: 16) {
                Text(copy.text("声音名称", "Voice name")).font(.headline)
                TextField(copy.text("1～30 字符", "1–30 characters"), text: $name).textFieldStyle(.roundedBorder)
                if let error = controller.error { Text(error).foregroundStyle(.red) }
                HStack { Button(copy.text("取消", "Cancel")) { renaming = false }; Spacer(); Button(copy.text("保存", "Save")) { if let selected, controller.rename(selected, name: name, copy: copy) { renaming = false } } }
            }.padding(24).frame(width: 360).interactiveDismissDisabled()
        }
    }
}
