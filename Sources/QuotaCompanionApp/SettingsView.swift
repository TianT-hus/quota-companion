import SwiftUI
import QuotaCore

enum SettingsPage: String, CaseIterable {
    case appearance, general, advanced
    var icon: String { switch self { case .appearance: "paintbrush.fill"; case .general: "gearshape"; case .advanced: "link" } }
    func title(_ c: Copybook) -> String { switch self { case .appearance: c.text("外观", "Appearance"); case .general: c.text("通用", "General"); case .advanced: c.text("连接与高级", "Connection & advanced") } }
}
@MainActor final class SettingsNavigation: ObservableObject {
    @Published var page: SettingsPage = .appearance
    @Published var session = UUID()
    func reset() { page = .appearance; session = UUID() }
}

struct SettingsView: View {
    @ObservedObject var model: CompanionModel
    @ObservedObject var navigation: SettingsNavigation
    @Environment(\.colorSchemeContrast) private var contrast
    private var c: Copybook { model.copy }
    private var chinese: Bool { c.locale.language.languageCode?.identifier == "zh" }
    private let ink = QuotaCore.RGBColor(hex: 0x10233C).color
    private let accent = QuotaCore.RGBColor(hex: 0x1685A6).color
    private let secondary = QuotaCore.RGBColor(hex: 0x50647B).color
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 5) {
                ForEach(SettingsPage.allCases, id: \.self) { p in
                    Button { navigation.page = p } label: {
                        HStack(spacing: 9) {
                            Image(systemName: p.icon).font(.system(size: 16)).frame(width: 20)
                            Text(p.title(c)).fontWeight(navigation.page == p ? .semibold : .regular).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 10).padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading)
                            .background(navigation.page == p ? accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("settings.nav.\(p.rawValue)")
                        .accessibilityAddTraits(navigation.page == p ? [.isSelected] : [])
                }
                Spacer()
            }.padding(.horizontal, 10).padding(.top, 18).frame(width: 164).background(QuotaCore.RGBColor(hex: 0xE5F2FB).color)
            Rectangle().fill(ink.opacity(contrast == .increased ? 0.45 : 0.12)).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(navigation.page.title(c)).font(.system(size: 17, weight: .semibold)).accessibilityAddTraits(.isHeader)
                        help(subtitle)
                    }
                    Group {
                        switch navigation.page { case .appearance: appearancePage; case .general: generalPage; case .advanced: advancedPage }
                    }.id(navigation.session)
                    Label(c.text("更改自动保存", "Changes save automatically"), systemImage: "checkmark.circle").font(.system(size: 12)).foregroundStyle(secondary)
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }.id(navigation.page).background(QuotaCore.RGBColor(hex: 0xF8FBFE).color)
        }.font(.system(size: 13)).foregroundStyle(ink).tint(accent).frame(width: 780, height: 620).environment(\.colorScheme, .light)
    }
    private var subtitle: String {
        switch navigation.page {
        case .appearance: c.text("调整桌宠和详情栏的显示效果。", "Adjust how the companion and detail card look.")
        case .general: c.text("设置语言、启动方式和语音提醒。", "Choose your language, startup behavior and spoken alerts.")
        case .advanced: c.text("查看额度连接，或配置不常用的选项。", "Check the quota connection and less frequently used options.")
        }
    }
    private func help(_ text: String) -> some View { Text(text).font(.system(size: 12)).foregroundStyle(secondary).fixedSize(horizontal: false, vertical: true) }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 14, weight: .semibold)).accessibilityAddTraits(.isHeader)
            content()
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ink.opacity(contrast == .increased ? 0.45 : 0.10), lineWidth: 1))
    }
    private func row<Content: View>(_ title: String, _ detail: String, @ViewBuilder control: () -> Content) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) { Text(title).fontWeight(.medium); help(detail) }.frame(maxWidth: .infinity, alignment: .leading)
            control().frame(width: 236)
        }.padding(.vertical, 2)
    }
    private var appearancePage: some View {
        Group {
            section(c.text("桌宠形象", "Companion character")) {
                CharacterSettings(library: model.characterLibrary, copy: c)
            }
            section(c.text("显示", "Display")) {
                row(c.text("桌宠大小", "Companion size"), c.text("猫咪和详情栏一起缩放。", "Scale the cat and card together.")) {
                    Picker(c.text("桌宠大小", "Companion size"), selection: $model.companionSize) {
                        ForEach(CompanionSize.allCases, id: \.self) { Text($0.title(chinese: chinese)).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("settings.size")
                }
                Divider()
                AppearanceColorControls(model: model)
            }
            section(c.text("详情栏背景", "Detail card background")) {
                help(c.text("只改变详情栏，不影响猫咪。", "Changes the card only, not the cat."))
                SettingsCardPreview(model: model).frame(height: 72)
                HStack {
                    help(c.text("效果预览", "Effect preview")); Spacer()
                    help(model.customBackgroundName == nil ? c.text("默认冰蓝玻璃", "Default ice-blue glass") : c.text("自选图片", "Custom image"))
                }
                HStack {
                    Button(model.customBackgroundName == nil ? c.text("选择图片…", "Choose image…") : c.text("更换图片…", "Change image…"), action: model.chooseBackground)
                        .disabled(model.isImportingBackground).accessibilityIdentifier("settings.background.choose")
                    Button(c.text("恢复默认", "Restore default"), action: model.restoreDefaultBackground).disabled(model.customBackgroundName == nil || model.isImportingBackground)
                    Button(c.text("调整图片…", "Adjust image…"), action: model.editBackground).disabled(model.background == nil || model.isImportingBackground)
                    if model.isImportingBackground { ProgressView().controlSize(.small) }
                }
                if model.background != nil {
                    HStack {
                        Text(c.text("图片不透明度", "Image opacity"))
                        Slider(value: Binding(get: { model.customAppearance.background?.safeOpacity ?? 0.12 }, set: { value in
                            var composition = model.customAppearance.background ?? BackgroundComposition()
                            composition.opacity = value; model.customAppearance.background = composition
                        }), in: 0...1).accessibilityLabel(c.text("图片不透明度", "Image opacity"))
                        Text("\(Int((model.customAppearance.background?.safeOpacity ?? 0.12)*100))%").monospacedDigit().frame(width: 38)
                    }
                    help(c.text("阅读保护会影响最终图片浓度。", "Readability protection affects the final image intensity."))
                }
                help(model.backgroundMessage.isEmpty ? c.text("图片仅保存在本机，文字清晰度会自动调整。支持 PNG、JPEG、WebP、HEIC，最大 32MB。", "Images stay on this Mac; readability adjusts automatically. PNG, JPEG, WebP or HEIC, up to 32MB.") : model.backgroundMessage)
            }
        }.sheet(item: $model.backgroundDraft) { draft in BackgroundEditor(model: model, draft: draft) }
    }
    private func textTitle(_ s: ChestTextStyle) -> String { switch s { case .whiteInk: c.text("白色", "White"); case .goldInk: c.text("暖金", "Gold"); case .inkWhite: c.text("深色", "Dark") } }
    private func choice<Sample: View>(_ title: String, selected: Bool, id: String, action: @escaping () -> Void, @ViewBuilder sample: () -> Sample) -> some View {
        Button(action: action) {
            VStack(spacing: 5) { sample(); Text(title).font(.system(size: 12)).lineLimit(1) }.frame(maxWidth: .infinity).padding(.vertical, 6)
                .background(selected ? accent.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? accent : .clear, lineWidth: 1.3)).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityIdentifier("settings.\(id)").accessibilityAddTraits(selected ? [.isSelected] : [])
    }
    private var generalPage: some View {
        section(c.text("偏好设置", "Preferences")) {
            row(c.text("界面语言", "Interface language"), c.text("更改设置和桌宠使用的语言。", "Language used by settings and the companion.")) {
                Picker(c.text("界面语言", "Interface language"), selection: $model.language) { ForEach(AppLanguage.allCases) { Text($0.title).tag($0) } }
                    .labelsHidden().accessibilityIdentifier("settings.language")
            }
            Divider()
            row(c.text("开机启动", "Launch at login"), c.text("登录 Mac 后自动显示猫咪。", "Show the cat automatically when you sign in to your Mac.")) {
                Toggle(c.text("开机启动", "Launch at login"), isOn: $model.launchAtLogin).labelsHidden().toggleStyle(.switch).frame(maxWidth: .infinity, alignment: .trailing)
            }
            if !model.launchAtLoginMessage.isEmpty { help(model.launchAtLoginMessage) }
            Divider()
            row(c.text("语音提醒", "Spoken alerts"), c.text("额度触发低余额提醒时朗读通知。", "Read notifications aloud when quota falls below an alert threshold.")) {
                Toggle(c.text("语音提醒", "Spoken alerts"), isOn: $model.speechEnabled).labelsHidden().toggleStyle(.switch).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
    private var advancedPage: some View {
        Group {
            section(c.text("额度连接", "Quota connection")) {
                HStack {
                    Label(connectionText, systemImage: model.snapshot.state == .live ? "checkmark.circle" : "wifi.slash"); Spacer()
                    Button(model.isConnecting ? c.text("正在刷新…", "Refreshing…") : c.text("刷新额度", "Refresh quota"), action: model.refreshNow).disabled(model.isConnecting)
                }
                if model.snapshot.state == .unavailable {
                    help(c.text("请先在本机 Codex 登录，再检查 CLI 路径和网络，点击刷新。应用不会提供或共享登录凭据。", "Sign in to Codex on this Mac, check the CLI path and network, then refresh. This app does not provide or share credentials."))
                }
                DisclosureGroup(c.text("技术诊断", "Technical diagnostics")) { help(model.diagnosticMessage.isEmpty ? c.text("暂无诊断信息。", "No diagnostic information yet.") : model.diagnosticMessage).textSelection(.enabled) }
                Divider()
                DisclosureGroup(c.text("自定义 Codex 路径", "Custom Codex path")) {
                    VStack(alignment: .leading, spacing: 8) {
                        help(c.text("通常无需填写，仅自动查找失败时使用。留空即可自动查找，更改后刷新额度。", "Usually unnecessary. Use only if automatic discovery fails. Leave blank for automatic discovery; refresh after changing."))
                        TextField(c.text("Codex 可执行文件路径（可选）", "Codex executable path (optional)"), text: $model.customCLIPath).textFieldStyle(.roundedBorder)
                    }.padding(.top, 6)
                }
            }
            section(c.text("Codex 对话插件", "Codex conversation plugin")) {
                help(c.text("在 Codex 对话里查询额度或控制猫咪。", "Read quota or control the cat from a Codex conversation."))
                DisclosureGroup(c.text("查看安装命令", "View installation command")) {
                    Text(model.pluginInstallCommand).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
                Button(c.text("安装插件…", "Install plugin…"), action: model.confirmAndInstallPlugin)
                help(c.text("安装前会展示命令和修改目标，请确认后再继续。", "Review the command and destination before confirming installation."))
                if !model.installMessage.isEmpty { help(model.installMessage) }
            }
            section(c.text("开发测试", "Developer testing")) {
                DisclosureGroup(c.text("示例额度与离线状态", "Sample quotas and offline state")) {
                    VStack(alignment: .leading, spacing: 10) {
                        help(c.text("会临时改变桌宠显示，不代表真实额度。", "Temporarily changes the companion display; these are not real quotas."))
                        HStack {
                            ForEach([100, 30, 15, 5, 0], id: \.self) { value in Button("\(value)%") { model.preview(remaining: value) } }
                            Button(c.text("离线", "Offline")) { model.preview(remaining: nil) }
                        }
                        Button(c.text("读取真实额度", "Read real quota"), action: model.refreshNow).disabled(model.isConnecting)
                    }.padding(.top, 6)
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
    var accessibility = CompanionAccessibility()
    var body: some View {
        let a = (model.background?.appearances ?? .standard)[BackgroundAppearanceKey(dark: false, highContrast: accessibility.contrast == .increased, reduceTransparency: accessibility.reduceTransparency)]
        ZStack {
            GlassCardSurface(background: model.background, appearance: a, solid: accessibility.reduceTransparency || accessibility.contrast == .increased, composition: model.customAppearance.background)
            VStack(spacing: 8) {
                HStack {
                    Text(model.copy.text("周 79%", "Week 79%")).font(.system(size: 14, weight: .semibold, design: .monospaced)); Spacer()
                    Label(model.copy.text("6天12时", "6d12h"), systemImage: "clock").font(.system(size: 12))
                }
                LiquidProgressView(remaining: 79, active: false, stale: false, appearance: a, palette: model.palette, customTint: model.progressTint).frame(height: 14)
            }.padding(.horizontal, 16).foregroundStyle(a.text.color)
        }.frame(maxWidth: 380).frame(maxWidth: .infinity).accessibilityElement(children: .ignore)
            .accessibilityLabel(model.copy.text("效果预览，示例额度百分之七十九", "Effect preview, sample quota 79 percent"))
    }
}
