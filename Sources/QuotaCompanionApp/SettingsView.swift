import SwiftUI
import QuotaCore

enum SettingsPage: String, CaseIterable {
    case day, todos, appearance, speech, general, advanced
    var isSchedule: Bool { self == .day || self == .todos }
    var icon: String { switch self { case .day: "calendar"; case .todos: "checklist"; case .appearance: "paintbrush.fill"; case .general: "gearshape"; case .speech: "speaker.wave.2"; case .advanced: "link" } }
    func title(_ c: Copybook) -> String { switch self { case .day: c.text("日程", "Schedule"); case .todos: c.text("待办", "To-dos"); case .appearance: c.text("外观", "Appearance"); case .general: c.text("通用", "General"); case .speech: c.text("语音", "Speech"); case .advanced: c.text("连接与高级", "Connection & advanced") } }
    func windowTitle(_ c: Copybook) -> String { isSchedule ? c.text("今日安排", "Today's schedule") : c.text("设置", "Settings") }
}
@MainActor final class SettingsNavigation: ObservableObject {
    @Published var page: SettingsPage = .appearance
    @Published var session = UUID()
    @Published var visible = false
    @Published var closeEditorRequest = 0
    var closeAfterEditor = false
    @Published var todoTitle = ""
    @Published var editingTodo: UUID?
    @Published var editingReminder: ReminderValue?
    @Published var originalTodoTitle = ""
    var requestPage: ((SettingsPage) -> Void)?
    var hasTodoDraft: Bool { todoTitle != originalTodoTitle }
    func clearTodoDraft() { todoTitle = ""; originalTodoTitle = ""; editingTodo = nil; editingReminder = nil }
    func reset() { page = .appearance; session = UUID() }
}

struct SettingsView: View {
    @ObservedObject var model: CompanionModel
    @ObservedObject var navigation: SettingsNavigation
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var optionsRevision = 0
    private var c: Copybook { model.copy }
    private var chinese: Bool { c.locale.language.languageCode?.identifier == "zh" }
    private let ink = ManagementStyle.ink
    private let accent = ManagementStyle.ink
    private let secondary = ManagementStyle.secondary
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 5) {
                ForEach([true, false], id: \.self) { schedule in
                if !schedule { Divider().padding(.vertical, 13) }
                ForEach(SettingsPage.allCases.filter { $0.isSchedule == schedule }, id: \.self) { p in
                    ManagementNavigationRow(title: p.title(c), icon: p.icon, selected: navigation.page == p) {
                        navigation.requestPage?(p)
                    }.accessibilityIdentifier("settings.nav.\(p.rawValue)")
                }
                }
                Spacer()
            }.padding(.leading, 1).padding(.trailing, 10).padding(.top, 18).frame(width: 164).background(.white)
            Rectangle().fill(ink.opacity(contrast == .increased ? 0.45 : 0.12)).frame(width: 1)
            if navigation.page.isSchedule && navigation.visible {
                SecretaryPanel(model: model, secretary: model.secretary, navigation: navigation)
                    .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(ManagementStyle.background)
            } else { ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Group {
                        switch navigation.page { case .appearance: appearancePage; case .general: generalPage; case .speech: speechPage; case .advanced: advancedPage; case .day, .todos: EmptyView() }
                    }.id(navigation.session)
                }.frame(maxWidth: 567, alignment: .leading).padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }.id(navigation.page).background(SettingsCardStyle.pageBackground)
            }
        }.font(.system(size: 13)).foregroundStyle(ink).tint(accent).frame(minWidth: 780, minHeight: 620).environment(\.colorScheme, .light)
            .environment(\.settingsPickerWidth, pickerWidth)
            .onReceive(model.speech.objectWillChange) { _ in optionsRevision += 1 }
            .onReceive(model.characterLibrary.objectWillChange) { _ in optionsRevision += 1 }
            .onReceive(model.reminders.objectWillChange) { _ in optionsRevision += 1 }
            .background(ScheduleErrorPresenter(secretary: model.secretary, copy: c))
            .background(ReminderErrorPresenter(reminders: model.reminders, copy: c))
            .ownedAlert(c.text("语音", "Speech"), isPresented: Binding(get: { model.speech.dialog != nil }, set: { if !$0 { model.speech.dialog = nil } })) {
                Button(c.text("确定", "OK")) { model.speech.dialog = nil }
            } message: { Text(model.speech.dialog ?? "") }
    }
    private var pickerWidth: CGFloat {
        _ = optionsRevision
        var titles: [String]
        switch navigation.page {
        case .appearance:
            return 340
        case .general: titles = AppLanguage.allCases.map(\.title)
        case .advanced: titles = [c.text("本地", "Local"), c.text("原清单暂不可用", "Saved list unavailable")] + model.reminders.state.lists.map(\.title)
        case .speech:
            titles = [c.text("本地系统", "Local system"), "API", c.text("自动选择本机声音", "Automatic local voice")]
            titles += APIProvider.allCases.map(\.name)
            titles += SpeechLanguage.allCases.map(\.title)
            titles += model.speech.voices.filter { voice in ["zh", "en", "ja"].contains(where: { voice.language.hasPrefix($0) }) }.map { "\($0.name) · \($0.language)" }
            for language in SpeechLanguage.allCases {
                titles += BailianVoice.available(language).map(\.title)
                titles += MiniMaxSpeechClient.voices(language).map(\.title)
            }
            titles += QuotaDelivery.allCases.map { $0.title(c) }
        default: titles = []
        }
        let measured = SettingsPicker<String>.measuredWidth(titles)
        return navigation.page == .speech ? min(318, measured) : measured
    }
    private func help(_ text: String) -> some View { Text(text).font(SettingsCardStyle.body).foregroundStyle(secondary).fixedSize(horizontal: false, vertical: true) }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        SettingsSection(title: title, content: content)
    }
    private func row<Content: View>(_ title: String, _ detail: String, @ViewBuilder control: () -> Content) -> some View {
        SettingsControlRow(title: title) { control() }.help(detail).padding(.vertical, 2)
    }
    private var appearancePage: some View {
        Group {
            CharacterGallery(model: model, library: model.characterLibrary, copy: c)
            AppearanceGeneralSettings(model: model, library: model.characterLibrary)
            section(c.text("额度通用设置", "Quota settings")) {
                AppearanceColorControls(model: model)
            }
            AppearanceBackgroundSettings(model: model)
        }.ownedSheet(item: $model.backgroundDraft) { draft in BackgroundEditor(model: model, draft: draft) }
            .ownedAlert(c.text("外观未保存", "Appearance not saved"), isPresented: Binding(get: { !model.colorEditorVisible && model.appearanceDialog != nil }, set: { if !$0 { model.appearanceDialog = nil } })) {
                Button(c.text("确定", "OK")) { model.appearanceDialog = nil }
            } message: { Text(model.appearanceDialog ?? "") }
    }
    private var generalPage: some View {
        Group {
        section(c.text("偏好设置", "Preferences")) {
                SettingsToggle(c.text("日程提醒", "Schedule reminders"), isOn: Binding(get: { model.secretary.data.reminders }, set: { value in
                    if model.secretary.commit({ $0.reminders = value }), !value { model.speech.stop() }
                })).help(c.text("到点提醒一次，可在语音页开启播报。", "One reminder at each time slot; enable spoken alerts on the Speech page."))
            SettingsRowDivider()
            SettingsPicker(c.text("界面语言 / Language", "Interface language"), selection: $model.language, options: AppLanguage.allCases.map { SettingsChoice($0, $0.title) })
                .accessibilityIdentifier("settings.language")
            Text(c.text("可选择简体中文或 English，立即生效；不改变语音播报的语言。", "Choose 简体中文 or English. Applies immediately without changing the spoken language."))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        section(c.text("启动方式", "Startup")) {
            StartupPreferences(model: model, follow: model.codexFollow)
        }
        }
    }
    private var speechPage: some View {
        Group {
            section(c.text("播报开关", "Spoken alerts")) {
                SpeechPreferences(model: model, speech: model.speech, group: .switches)
            }
            section(c.text("声音", "Voice")) {
                SpeechPreferences(model: model, speech: model.speech, group: .voice)
            }
            section(c.text("播放调整", "Playback")) {
                SpeechPreferences(model: model, speech: model.speech, group: .playback)
            }
        }
    }
    private var advancedPage: some View {
        Group {
            section(c.text("苹果提醒事项", "Apple Reminders")) {
                ReminderSettings(reminders: model.reminders, copy: c)
            }
            section(c.text("额度连接", "Quota connection")) {
                HStack {
                    Label(connectionText, systemImage: model.snapshot.state == .live ? "checkmark.circle" : "wifi.slash"); Spacer()
                    Button(model.isConnecting ? c.text("正在刷新…", "Refreshing…") : c.text("刷新额度", "Refresh quota"), action: model.refreshNow).disabled(model.isConnecting)
                }
                DisclosureGroup(c.text("技术诊断", "Technical diagnostics")) { help(model.diagnosticMessage.isEmpty ? c.text("暂无诊断信息。", "No diagnostic information yet.") : model.diagnosticMessage).textSelection(.enabled) }
                SettingsRowDivider()
                DisclosureGroup(c.text("自定义 Codex 路径", "Custom Codex path")) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(c.text("Codex 可执行文件路径（可选）", "Codex executable path (optional)"), text: $model.customCLIPath).textFieldStyle(.roundedBorder)
                            .help(c.text("留空即可自动查找，更改后刷新额度。", "Leave blank for automatic discovery; refresh after changing."))
                    }.padding(.top, 6)
                }
            }
            section(c.text("Codex 对话插件", "Codex conversation plugin")) {
                DisclosureGroup(c.text("查看安装命令", "View installation command")) {
                    Text(model.pluginInstallCommand).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
                Button(c.text("安装插件…", "Install plugin…"), action: model.confirmAndInstallPlugin)
                if !model.installMessage.isEmpty { help(model.installMessage) }
            }
            section(c.text("开发测试", "Developer testing")) {
                DisclosureGroup(c.text("示例额度与离线状态", "Sample quotas and offline state")) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            ForEach([100, 30, 15, 5, 0], id: \.self) { value in Button("\(value)%") { model.preview(remaining: value) } }
                            Button(c.text("离线", "Offline")) { model.preview(remaining: nil) }
                        }
                        Button(c.text("读取真实额度", "Read real quota"), action: model.refreshNow).disabled(model.isConnecting)
                    }.padding(.top, 6).help(c.text("会临时改变桌宠显示，不代表真实额度。", "Temporarily changes the companion display; these are not real quotas."))
                }
            }
        }
    }
    private var connectionText: String {
        if model.snapshot.source == .demo { return c.text("示例数据（非真实额度）", "Sample data (not real quota)") }
        switch model.snapshot.state { case .live: return c.text("实时连接", "Live connection"); case .stale: return c.text("离线 · 显示上次数据", "Offline · showing last data"); case .unavailable: return c.text("暂无数据", "No data yet") }
    }
}

struct SettingsCardPreview: View {
    @ObservedObject var model: CompanionModel
    var quotaCount = 2
    var body: some View {
        CompanionRootView(model: model, previewDate: Date(timeIntervalSince1970: 1790606580), sampleQuotaCount: quotaCount, sampleScale: 2)
            .frame(width: 300, height: 160)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.copy.text("详情栏预览，虚构额度与日程", "Detail card preview with fictional quotas and schedule"))
    }
}
