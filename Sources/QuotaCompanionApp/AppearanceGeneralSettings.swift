import SwiftUI
import QuotaCore

struct AppearanceGeneralSettings: View {
    @ObservedObject var model: CompanionModel
    @ObservedObject var library: CharacterLibrary
    @State private var seconds = ""
    @State private var invalid = false
    @FocusState private var focused: Bool
    private var c: Copybook { model.copy }
    private var available: Bool { !library.playbackMotions(for: library.selectedID).isEmpty }
    var body: some View {
        SettingsSection(title: c.text("桌宠通用设置", "Companion settings")) {
            SettingsControlRow(title: c.text("桌宠大小", "Companion size"), expanding: true) {
                AppearancePercentControl(value: Binding(get: { model.companionSize.sliderPercent }, set: { model.companionSize = CompanionSize(sliderPercent: $0.rounded()) }), title: c.text("桌宠大小", "Companion size"), identifier: "settings.size")
            }
            SettingsRowDivider()
            SettingsToggle(c.text("桌宠动画", "Companion animation"), isOn: Binding(get: { available && library.animationEnabled }, set: {
                guard validateBeforeCollapse() else { return }; library.animationEnabled = $0
            })).disabled(!available)
            SettingsReveal(expanded: available && library.animationEnabled, trigger: c.text("桌宠动画", "Companion animation")) {
                SettingsRowDivider()
                SettingsControlRow(title: c.text("动画频率", "Animation frequency"), trailing: true) {
                    NativeSettingsPicker(title: c.text("动画频率", "Animation frequency"), selection: Binding(get: { library.animationInterval.continuous }, set: {
                        guard validateBeforeCollapse() else { return }; library.animationInterval.continuous = $0
                    }), options: [SettingsChoice(true, c.text("连续播放", "Continuous")), SettingsChoice(false, c.text("自定义", "Custom"))])
                        .frame(width: 150, height: 28)
                }
                SettingsReveal(expanded: !library.animationInterval.continuous, trigger: c.text("动画频率", "Animation frequency")) {
                    SettingsRowDivider()
                    SettingsControlRow(title: c.text("播放间隔", "Playback interval")) {
                        HStack(spacing: 8) {
                            TextField("30", text: $seconds).textFieldStyle(.roundedBorder).multilineTextAlignment(.center).frame(width: 72)
                                .focused($focused).onSubmit(commit).accessibilityLabel(c.text("播放间隔秒数", "Playback interval in seconds"))
                            Text(c.text("秒", "seconds"))
                        }
                    }
                }
            }
        }.onAppear { seconds = String(library.animationInterval.seconds) }
            .onChange(of: focused) { was, now in if was && !now && !invalid { commit() } }
            .ownedAlert(c.text("间隔无效", "Invalid interval"), isPresented: $invalid) {
                Button(c.text("确定", "OK")) { focused = true }
            } message: { Text(c.text("请输入 1–3600 的整数秒数。", "Enter a whole number from 1 to 3600 seconds.")) }
    }
    private func commit() {
        guard !invalid else { return }
        guard let value = AnimationInterval.parse(seconds) else { invalid = true; return }
        library.animationInterval.seconds = value; seconds = String(value)
    }
    private func validateBeforeCollapse() -> Bool {
        guard available && library.animationEnabled && !library.animationInterval.continuous else { return true }
        guard AnimationInterval.parse(seconds) != nil else { invalid = true; return false }
        return true
    }
}

struct AppearancePercentControl: View {
    @Binding var value: Double
    let title: String
    var identifier: String = "appearance.percent"
    var body: some View {
        HStack(spacing: 10) {
            SettingsSizeSlider(percent: $value, title: title).frame(height: 24).accessibilityIdentifier(identifier)
            Text("\(Int(value.rounded()))%").monospacedDigit().frame(width: 38, alignment: .trailing)
        }
    }
}

struct AppearanceBackgroundSettings: View {
    @ObservedObject var model: CompanionModel
    private var c: Copybook { model.copy }
    var body: some View {
        SettingsSection(title: c.text("详情栏背景", "Detail card background")) {
            HStack(alignment: .center, spacing: 20) {
                SettingsCardPreview(model: model).frame(width: 300, height: 160)
                VStack(spacing: 10) {
                    Button(c.text("更换图片", "Change image"), action: model.chooseBackground).accessibilityIdentifier("settings.background.choose")
                    Button(c.text("调整图片", "Adjust image"), action: model.editBackground).disabled(model.background == nil)
                    Button(c.text("恢复默认", "Restore default"), action: model.restoreDefaultBackground).disabled(model.customBackgroundName == nil)
                }.buttonStyle(AppearanceActionStyle()).disabled(model.isImportingBackground)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if model.background != nil {
                SettingsRowDivider()
                SettingsControlRow(title: c.text("图片透明度", "Image transparency"), expanding: true) {
                    AppearancePercentControl(value: Binding(get: { 100 * (1 - (model.customAppearance.background?.safeOpacity ?? 0.12)) }, set: {
                        var composition = model.customAppearance.background ?? BackgroundComposition()
                        composition.opacity = 1 - $0 / 100; model.customAppearance.background = composition
                    }), title: c.text("图片透明度", "Image transparency"))
                }
            }
        }
    }
}

struct AppearanceActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13)).frame(width: 118, height: 28)
            .foregroundStyle(enabled ? ManagementStyle.ink : .secondary)
            .background(Color.black.opacity(enabled ? (configuration.isPressed ? 0.12 : 0.08) : 0.04), in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
    }
}
