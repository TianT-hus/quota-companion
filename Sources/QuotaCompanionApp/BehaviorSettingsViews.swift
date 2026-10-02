import AppKit
import SwiftUI
import QuotaCore

struct StartupPreferences: View {
    @StateObject private var dialogOwner = DialogOwner()
    @ObservedObject var model: CompanionModel
    @ObservedObject var follow: CodexFollowSettings
    private var c: Copybook { model.copy }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsToggle(c.text("跟随 Codex 启停", "Follow Codex launch and quit"), isOn: Binding(get: { follow.enabled }, set: { change(.followCodex, $0) }))
                .toggleStyle(.switch).accessibilityIdentifier("settings.followCodex")
                .help(c.text("Codex 启动时显示桌宠，⌘Q 退出时关闭；关闭窗口不算退出。需要允许后台服务运行。", "Launch with Codex; quit when Codex exits with ⌘Q. Closing a window does not quit. Requires a background item."))
            SettingsRowDivider()
            SettingsToggle(c.text("开机启动", "Launch at login"), isOn: Binding(get: { follow.launchAtLogin }, set: { change(.login, $0) }))
                .toggleStyle(.switch).accessibilityIdentifier("settings.launchAtLogin")
                .help(c.text("登录 Mac 后自动显示桌宠，无需先打开 Codex。", "Show the companion when you sign in, without opening Codex first."))
            Text(c.text("两种启动方式任选其一；开启另一种时会先请你确认切换。", "Choose one startup method. Switching to the other asks for confirmation."))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !follow.message.isEmpty {
                Text(follow.message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(c.text("打开系统登录项设置", "Open Login Items"), action: follow.openSystemSettings)
            }
        }.disabled(follow.changing).background(DialogOwnerReader(owner: dialogOwner))
            .onAppear { follow.refresh(copy: c) }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in follow.refresh(copy: c) }
            .onChange(of: model.language) { follow.refresh(copy: c) }
    }
    private func change(_ method: StartupMethod, _ enabled: Bool) {
        follow.request(method, enabled: enabled, copy: c) {
            let alert = NSAlert()
            alert.messageText = method == .login ? c.text("切换为开机启动？", "Switch to launch at login?") : c.text("切换为跟随 Codex 启停？", "Switch to following Codex?")
            alert.informativeText = method == .login
                ? c.text("确认后将关闭“跟随 Codex 启停”。下次登录 Mac 时，朝夕将独立启动。", "This turns off Follow Codex. Zhaoxi will launch independently when you next sign in to your Mac.")
                : c.text("确认后将关闭“开机启动”。朝夕将随 Codex 启动，并在 Codex 退出时关闭。", "This turns off Launch at login. Zhaoxi will launch and quit with Codex.")
            alert.addButton(withTitle: c.text("确认切换", "Switch"))
            alert.addButton(withTitle: c.text("取消", "Cancel"))
            return alert.runOwnedModal(parent: dialogOwner.window) == .alertFirstButtonReturn
        }
    }
}

struct SpeechPreferences: View {
    @StateObject private var dialogOwner = DialogOwner()
    enum Group { case switches, voice, playback }
    @ObservedObject var model: CompanionModel
    @ObservedObject var speech: CompanionSpeech
    var group: Group
    private var c: Copybook { model.copy }
    private var chinese: Bool { c.locale.language.languageCode?.identifier == "zh" }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if group == .switches {
            HStack {
            SettingsToggle(c.text("日程语音播报", "Speak schedule reminders"), isOn: Binding(get: { speech.scheduleEnabled }, set: { enabled in
                if !enabled, speech.draft?.template.kind == .schedule, !speech.discardDraft(copy: c, parent: dialogOwner.window) { return }
                speech.scheduleEnabled = enabled
            }))
                .toggleStyle(.switch).disabled(!model.secretary.data.reminders).accessibilityIdentifier("settings.scheduleSpeech")
                .help(model.secretary.data.reminders ? c.text("到点朗读时间段与事项一次，不补播过期安排。", "Read the time range and task once; no expired reminders.") : c.text("请先在通用页开启日程提醒。", "Enable schedule reminders on the General page first."))
                disclosure(.schedule).disabled(!speech.scheduleEnabled)
            }
            SettingsReveal(expanded: speech.draft?.template.kind == .schedule, trigger: "speech.disclosure.schedule", spacing: 10) { editor }
            SettingsRowDivider()
            HStack {
                SettingsToggle(c.text("低额度提醒", "Low-quota alerts"), isOn: Binding(get: { speech.configuration.value.quota.enabled }, set: { enabled in
                    if !enabled, speech.draft?.template.kind == .quota, !speech.discardDraft(copy: c, parent: dialogOwner.window) { return }
                    speech.setQuotaEnabled(enabled, copy: c)
                }))
                disclosure(.quota).disabled(!speech.configuration.value.quota.enabled)
            }
            SettingsReveal(expanded: speech.draft?.template.kind == .quota, trigger: "speech.disclosure.quota", spacing: 10) { editor }
            }
            if group == .voice {
            CloudSpeechControls(speech: speech, copy: c)
            SettingsRowDivider()
            if speech.source == .local {
            SettingsPicker(c.text("声音", "Voice"), selection: $speech.localVoice,
                           options: [SettingsChoice("", c.text("自动选择本机声音", "Automatic local voice"))] + speech.spokenVoices.map { SettingsChoice($0.id, "\($0.name) · \($0.language)") }).accessibilityIdentifier("settings.voice")
            SettingsRowDivider()
            }
            HStack {
                Button(c.text("试听播报", "Preview announcement")) { speech.preview(copy: c, parent: dialogOwner.window) }.disabled(speech.cloudBusy).accessibilityIdentifier("settings.voice.preview")
                Button(c.text("停止", "Stop"), action: speech.stop)
                if speech.source == .local { Button(c.text("重新读取声音", "Reload voices"), action: speech.reloadVoices) }
            }
            }
            if group == .playback {
            HStack { Text(c.text("语速", "Rate")).frame(width: 58, alignment: .leading); SettingsAdjustmentSlider(value: $speech.rate, range: 0.3...0.6, title: c.text("语速", "Rate")); Text(String(format: "%.2f", speech.rate)).monospacedDigit().frame(width: 40, alignment: .trailing) }
            SettingsRowDivider()
            HStack { Text(c.text("音量", "Volume")).frame(width: 58, alignment: .leading); SettingsAdjustmentSlider(value: $speech.volume, range: 0...1, title: c.text("音量", "Volume")); Text("\(Int(speech.volume*100))%").monospacedDigit().frame(width: 40, alignment: .trailing) }
            }
        }.background(DialogOwnerReader(owner: dialogOwner)).onChange(of: speech.draft?.template.kind) { before, after in
            guard group == .switches, let before, after == nil else { return }
            let target: String
            if before == .schedule && !speech.scheduleEnabled { target = c.text("日程语音播报", "Speak schedule reminders") }
            else if before == .quota && !speech.configuration.value.quota.enabled { target = c.text("低额度提醒", "Low-quota alerts") }
            else { target = "speech.disclosure.\(before.rawValue)" }
            let window = dialogOwner.window
            DispatchQueue.main.async { focusSettingsControl(named: target, in: window) }
        }
    }
    private func disclosure(_ kind: SpeechTemplateKind) -> some View {
        SettingsDisclosureButton(title: c.text("编辑播报内容", "Edit spoken content"), identifier: "speech.disclosure.\(kind.rawValue)", expanded: speech.draft?.template.kind == kind) {
            if speech.draft?.template.kind == kind { _ = speech.discardDraft(copy: c, parent: dialogOwner.window) }
            else { speech.editTemplate(kind, copy: c, parent: dialogOwner.window) }
        }.frame(width: 28, height: 24)
    }
    @ViewBuilder private var editor: some View {
        if let value = speech.draft {
            SpeechTemplateEditor(speech: speech, copy: c, draft: Binding(get: { speech.draft ?? value }, set: { speech.draft = $0 }))
        }
    }
}
