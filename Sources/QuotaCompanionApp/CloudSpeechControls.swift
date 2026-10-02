import AppKit
import SwiftUI
import QuotaCore

struct CloudSpeechControls: View {
    @ObservedObject var speech: CompanionSpeech
    let copy: Copybook
    @State private var configure = false
    @State private var prepare = false
    @State private var addVoice = false
    @State private var manageVoices = false
    @Environment(\.settingsPickerWidth) private var pickerWidth
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if SpeechStatusQA.enabled { Text(copy.text("隔离状态灯验收 · 模拟请求交替成功／失败 · 不读密钥、不联网、不计费", "Isolated status QA · Alternating mock success/failure · No keys, network or charges")).font(.caption).foregroundStyle(.secondary) }
            SettingsControlRow(title: copy.text("语音来源", "Speech source"), trailing: true) {
            HStack(spacing: 8) {
            NativeSettingsPicker(title: copy.text("语音来源", "Speech source"), selection: Binding(get: { speech.source }, set: { value in
                if value == .bailian && !speech.cloudConsented { configure = true }
                else { speech.selectSource(value) }
            }), options: [SettingsChoice(.local, copy.text("本地系统", "Local system")), SettingsChoice(.bailian, "API")])
                .accessibilityIdentifier("speech.source")
                .frame(width: max(80, pickerWidth - 32), height: 28)
            SpeechStatusLight(status: speech.status(copy: copy), title: copy.text("语音状态", "Speech status"), copy: copy)
            }
            }
            SettingsPicker(copy.text("播报语言", "Speech language"), selection: $speech.cloudLanguage,
                           options: SpeechLanguage.allCases.map { SettingsChoice($0, $0.title) })
                .accessibilityIdentifier("speech.language")
            HStack {
                Button(copy.text("翻译语言资源", "Translation resources")) { prepare = true }
                    .help(copy.text("跨语言播报使用苹果系统翻译；只在主动准备时下载语言资源。", "Cross-language speech uses Apple translation. Language resources download only when you prepare them."))
            }
            if speech.source == .bailian {
                SettingsRowDivider()
                SettingsControlRow(title: copy.text("API 平台", "API provider"), trailing: true) {
                    HStack(spacing: 8) {
                        Text(speech.provider.name)
                        SpeechStatusLight(status: speech.apiStatus, title: copy.text("测试 API 连接", "Test API connection"), copy: copy, disabled: speech.cloudBusy) { speech.testConnection(copy: copy) }
                    }
                }
                SettingsPicker(copy.text("声音", "Voice"), selection: $speech.combinedVoice,
                               options: speech.combinedVoiceChoices)
                    .accessibilityIdentifier("speech.cloud.voice")
                HStack {
                    Button(copy.text("配置 API", "Configure API")) { configure = true }
                }
            } else {
                Button(copy.text("配置 API", "Configure API")) { configure = true }
            }
            HStack {
                Button(copy.text("添加我的声音", "Add my voice")) { addVoice = true }
                Button(copy.text("管理我的声音", "Manage my voices")) { manageVoices = true }
            }
        }
        .ownedSheet(isPresented: $addVoice) { PersonalVoiceWizard(speech: speech, controller: speech.personalVoiceController, copy: copy) }
        .ownedSheet(isPresented: $manageVoices) { PersonalVoiceManager(speech: speech, controller: speech.personalVoiceController, copy: copy) }
        .ownedSheet(isPresented: $configure) { APIConfigurationEditor(speech: speech, copy: copy) }
        .ownedSheet(isPresented: $prepare) {
            if #available(macOS 15, *) { TranslationPreparation(target: speech.cloudLanguage, copy: copy, prepared: speech.translationPrepared) }
            else {
                VStack(spacing: 16) {
                    Text(copy.text("自动翻译需要 macOS 15 或以上版本。", "Automatic translation requires macOS 15 or later."))
                    Button(copy.text("关闭", "Close")) { prepare = false }
                }.padding(24)
            }
        }
    }
}

struct APIConfigurationEditor: View {
    @ObservedObject var speech: CompanionSpeech
    let copy: Copybook
    @Environment(\.ownedDismiss) private var dismiss
    @State private var provider: APIProvider = .bailian
    @State private var address = ""
    @State private var key = ""
    @State private var replacingKey = false
    @State private var keyPresence = CredentialPresence.unknown
    @State private var consent = false
    @State private var testing = false
    @State private var failure = ""
    @State private var testStatus = SpeechRuntimeStatus.unknown
    @State private var requestID = UUID()
    @State private var discard = false
    @State private var pendingProvider: APIProvider?
    private var dirty: Bool { !key.isEmpty || address != (speech.configuration.value.endpoints[provider.rawValue] ?? provider.endpoint) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(copy.text("API 配置", "API configuration")).font(.headline)
            ForEach(APIProvider.allCases, id: \.self) { vendor in
                HStack {
                    Text(vendor.name)
                    Spacer()
                    Text(speech.configuredProviders.contains(vendor) ? copy.text("已配置", "Configured") : copy.text("未配置", "Not configured")).foregroundStyle(.secondary)
                    Button(copy.text("编辑", "Edit")) { changeProvider(vendor) }
                }
            }
            SettingsRowDivider()
            SettingsPicker(copy.text("平台", "Provider"), selection: Binding(get: { provider }, set: { changeProvider($0) }),
                           options: APIProvider.allCases.map { SettingsChoice($0, $0.name) })
            HStack(spacing: 8) {
                TextField(copy.text("官方 HTTPS 接口地址", "Official HTTPS endpoint"), text: $address).textFieldStyle(.roundedBorder)
                SpeechStatusLight(status: testStatus, title: copy.text("测试此配置", "Test this configuration"), copy: copy, disabled: speech.cloudBusy) { request(test: true) }
            }
                .onChange(of: address) { _, _ in invalidateTest() }
                .onChange(of: provider) { _, value in invalidateTest(); key = ""; replacingKey = false; keyPresence = speech.credentialPresence(value) }
            Text(APIProvider.identify(address).map { copy.text("已识别：", "Identified: ") + $0.name } ?? copy.text("暂不支持此地址", "Unsupported endpoint"))
            HStack {
                Text("API Key")
                Text(keyPresence.title(copy)).foregroundStyle(.secondary)
                Spacer()
                Button(copy.text("更换密钥", "Replace key")) { replacingKey = true }
            }
            if replacingKey || keyPresence == .missing {
                SecureField(copy.text("API Key（留空保留已存密钥）", "API key (blank keeps saved key)"), text: $key).textFieldStyle(.roundedBorder)
                    .onChange(of: key) { _, _ in invalidateTest() }
            }
            HStack {
                Button(copy.text("取消", "Cancel")) { requestClose() }
                Spacer()
                Button(copy.text("保存", "Save")) { request(test: false) }.disabled(speech.cloudBusy)
            }
        }.padding(24).frame(width: 520)
        .onAppear { provider = speech.provider; address = speech.endpoint; keyPresence = speech.credentialPresence(provider) }
        .onDisappear { invalidateTest(); key = "" }
        .interactiveDismissDisabled()
        .ownedAlert(copy.text("放弃未保存的 API 修改？", "Discard unsaved API changes?"), isPresented: $discard) {
            Button(copy.text("继续编辑", "Keep editing"), role: .cancel) { pendingProvider = nil }
            Button(copy.text("放弃修改", "Discard changes")) {
                key = ""
                if let next = pendingProvider { applyProvider(next); pendingProvider = nil }
                else { invalidateTest(); dismiss() }
            }
        }
        .ownedAlert(copy.text("启用此 API 平台？", "Enable this API provider?"), isPresented: $consent) {
            Button(copy.text("取消", "Cancel"), role: .cancel) {}
            Button(testing ? copy.text("同意并测试", "Agree and test") : copy.text("同意并保存", "Agree and save")) { testing ? test() : save() }
        } message: { Text(copy.text("播报文字将发送至所选平台，连接测试和合成可能产生费用。密钥仅保存在本机钥匙串。保存不会自动测试连接。", "Spoken text will be sent to this provider. Tests and synthesis may incur charges. The key stays in this Mac’s Keychain. Saving does not test the connection.")) }
        .ownedAlert(copy.text("API 配置", "API configuration"), isPresented: Binding(get: { !failure.isEmpty }, set: { if !$0 { failure = "" } })) {
            Button(copy.text("确定", "OK")) { failure = "" }
        } message: { Text(failure) }
    }
    private func applyProvider(_ value: APIProvider) {
        invalidateTest(); provider = value; address = speech.configuration.value.endpoints[value.rawValue] ?? value.endpoint
        key = ""; replacingKey = false; keyPresence = speech.credentialPresence(value)
    }
    private func changeProvider(_ value: APIProvider) {
        guard value != provider else { return }
        if dirty { pendingProvider = value; discard = true } else { applyProvider(value) }
    }
    private func requestClose() {
        OwnedDialogTrace.record("api.cancel.action")
        if dirty { pendingProvider = nil; discard = true }
        else { invalidateTest(); dismiss() }
    }
    private func request(test: Bool) {
        guard APIProvider.identify(address) == provider else { failure = copy.text("只支持列出的官方 HTTPS 地址。", "Only the listed official HTTPS endpoints are supported."); return }
        testing = test
        if speech.configuration.value.consented.contains(provider) { test ? self.test() : save() }
        else { consent = true }
    }
    private func test() {
        let token = UUID(); requestID = token
        speech.testAPI(provider: provider, address: address.trimmingCharacters(in: .whitespacesAndNewlines), key: key, copy: copy) {
            guard requestID == token else { return }
            testStatus = $0
        }
    }
    private func invalidateTest() {
        requestID = UUID()
        if testStatus.phase == .testing { speech.stop() }
        testStatus = .unknown
    }
    private func save() {
        if speech.saveAPI(provider: provider, address: address.trimmingCharacters(in: .whitespacesAndNewlines), key: key, consent: true, copy: copy) {
            key = ""; dismiss()
        } else { failure = speech.dialog ?? copy.text("保存失败。", "Could not save."); speech.dialog = nil }
    }
}

struct SpeechStatusLight: View {
    let status: SpeechRuntimeStatus
    let title: String
    let copy: Copybook
    var disabled = false
    var action: (() -> Void)? = nil
    private var help: String {
        (action == nil ? copy.text("当前语音状态：", "Current speech status: ") : disabled && status.phase != .testing ? copy.text("正在处理其他语音请求，请停止或等待完成后再测试。", "Another speech request is active. Stop it or wait before testing. ") : copy.text("点击测试 API 连接：使用固定短句，不播放；可能计费。", "Click to test API connection with a fixed phrase, without playback; charges may apply. ")) + status.description(copy)
    }
    private var dot: some View {
        Circle().fill(status.phase == .ready ? Color(hex: 0x24833B) : status.phase == .failed ? Color(hex: 0xD93232) : Color(hex: 0x888888))
            .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
            .frame(width: 10, height: 10).frame(width: 24, height: 28).contentShape(Rectangle())
    }
    var body: some View {
        Group {
            if let action {
                NativeSpeechStatusLight(status: status, title: title, help: help, enabled: !disabled && status.phase != .testing, action: action)
                    .frame(width: 24, height: 28)
            } else { NativeSpeechStatusLight(status: status, title: title, help: help, enabled: false, action: {}).frame(width: 24, height: 28) }
        }.accessibilityLabel(title).accessibilityValue(status.description(copy)).accessibilityHint(help)
    }
}

struct NativeSpeechStatusLight: NSViewRepresentable {
    let status: SpeechRuntimeStatus
    let title: String
    let help: String
    let enabled: Bool
    let action: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> SpeechStatusButton {
        let view = SpeechStatusButton(); view.setButtonType(.momentaryPushIn); view.isBordered = false; view.title = ""; view.focusRingType = .none
        view.target = context.coordinator; view.action = #selector(Coordinator.activate(_:)); return view
    }
    func updateNSView(_ view: SpeechStatusButton, context: Context) {
        context.coordinator.parent = self; view.phase = status.phase; view.isEnabled = enabled; view.helpText = help; view.toolTip = nil
        view.setAccessibilityLabel(title); view.setAccessibilityValue(help); view.needsDisplay = true
    }
    @MainActor final class Coordinator: NSObject {
        var parent: NativeSpeechStatusLight
        init(_ parent: NativeSpeechStatusLight) { self.parent = parent }
        @objc func activate(_ sender: NSButton) { guard sender.isEnabled else { return }; parent.action() }
    }
}

final class SpeechStatusButton: NSButton {
    var helpText = "" { didSet { if oldValue != helpText && helpPanel?.isVisible == true { showHelp() } } }
    private static weak var activeHelp: SpeechStatusButton?
    static var visibleHelpCount: Int { activeHelp?.helpPanel?.isVisible == true ? 1 : 0 }
    var phase = SpeechRuntimeStatus.Phase.unknown { didSet { updateProgress(); needsDisplay = true } }
    private var hoverArea: NSTrackingArea?
    private var helpTimer: Timer?
    private var helpPanel: SpeechStatusHelpPanel?
    private let progress = StatusProgressIndicator()
    var showsKeyboardFocus: Bool { SettingsInputFocus.keyboard && window?.firstResponder === self }
    override init(frame frameRect: NSRect) { super.init(frame:frameRect); configure() }
    required init?(coder:NSCoder) { super.init(coder:coder); configure() }
    private func configure() {
        focusRingType = .none
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false
        progress.setAccessibilityElement(false); addSubview(progress)
    }
    override func layout() { super.layout(); progress.frame = NSRect(x:bounds.midX-7,y:bounds.midY-7,width:14,height:14) }
    private func updateProgress() {
        if phase == .testing && window != nil { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) {
        helpTimer?.invalidate()
        helpTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.showHelp() }
        }
    }
    override func mouseExited(with event: NSEvent) { dismissHelp() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); dismissHelp(); updateProgress()
        NotificationCenter.default.removeObserver(self,name:NSWindow.didResignKeyNotification,object:nil)
        if let window {
            NotificationCenter.default.addObserver(self,selector:#selector(windowLostFocus),name:NSWindow.didResignKeyNotification,object:window)
        }
    }
    @objc private func windowLostFocus(_ notification:Notification) { dismissHelp() }
    private func showHelp() {
        guard !helpText.isEmpty, window?.isVisible == true else { return }
        if Self.activeHelp !== self { Self.activeHelp?.dismissHelp() }
        Self.activeHelp = self
        let label = NSTextField(wrappingLabelWithString: helpText); label.font = .systemFont(ofSize: 13)
        let height = ceil((helpText as NSString).boundingRect(with: NSSize(width: 280, height: 1000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 13)]).height) + 4
        label.frame = NSRect(x:12,y:12,width:280,height:height)
        let content = NSView(frame:NSRect(x:0,y:0,width:304,height:height+24)); content.wantsLayer=true
        content.layer?.cornerRadius=10; content.layer?.backgroundColor=NSColor.windowBackgroundColor.cgColor
        content.layer?.borderWidth=1; content.layer?.borderColor=NSColor.separatorColor.cgColor; content.addSubview(label)
        // A tooltip must never activate, take focus or consume the first click.
        // NSPopover's transient dismissal competes with NSButton tracking here.
        let panel=helpPanel ?? SpeechStatusHelpPanel(contentRect:content.bounds,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isReleasedWhenClosed=false; panel.isOpaque=false; panel.backgroundColor = .clear
        panel.hasShadow=true; panel.ignoresMouseEvents=true; panel.hidesOnDeactivate=true; panel.contentView=content
        panel.setContentSize(content.bounds.size)
        guard let window else { return }
        let anchor=window.convertToScreen(convert(bounds,to:nil)), screen=window.screen?.visibleFrame ?? anchor
        var origin=NSPoint(x:anchor.midX-152,y:anchor.minY-height-30)
        if origin.y < screen.minY { origin.y=anchor.maxY+6 }
        origin.x=max(screen.minX,min(origin.x,screen.maxX-304)); origin.y=max(screen.minY,min(origin.y,screen.maxY-height-24))
        panel.setFrameOrigin(origin)
        if panel.parent !== window { window.addChildWindow(panel,ordered:.above) }
        helpPanel=panel; panel.orderFront(nil)
    }
    private func dismissHelp() { helpTimer?.invalidate(); helpTimer = nil; if let helpPanel { helpPanel.parent?.removeChildWindow(helpPanel); helpPanel.close() }; helpPanel = nil; if Self.activeHelp === self { Self.activeHelp = nil } }
    override func mouseDown(with event: NSEvent) {
        SettingsInputFocus.setKeyboard(false)
        if !isEnabled { showHelp(); return }
        dismissHelp(); super.mouseDown(with: event)
    }
    override func sendAction(_ action: Selector?, to target: Any?) -> Bool { dismissHelp(); return super.sendAction(action,to:target) }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { !isHiddenOrHasHiddenAncestor }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func keyDown(with event: NSEvent) {
        SettingsInputFocus.setKeyboard(true)
        if event.keyCode == 48 { moveSettingsControlFocus(from: self, backwards: event.modifierFlags.contains(.shift)) }
        else if isEnabled && [36,49,76].contains(event.keyCode), let action { dismissHelp(); _ = sendAction(action, to: target) }
        else { super.keyDown(with: event) }
    }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; if SettingsInputFocus.keyboard { showHelp() }; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; dismissHelp(); return true }
    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor
        switch phase {
        case .ready: color = NSColor(srgbRed: 36.0/255.0, green: 131.0/255.0, blue: 59.0/255.0, alpha: 1)
        case .failed: color = NSColor(srgbRed: 217.0/255.0, green: 50.0/255.0, blue: 50.0/255.0, alpha: 1)
        default: color = .gray
        }
        let dot = NSBezierPath(ovalIn: NSRect(x: bounds.midX-5, y: bounds.midY-5, width: 10, height: 10))
        if phase != .testing { color.setFill(); dot.fill(); NSColor.labelColor.withAlphaComponent(0.25).setStroke(); dot.lineWidth = 1; dot.stroke() }
        if showsKeyboardFocus {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let focus = NSBezierPath(ovalIn: NSRect(x: bounds.midX-9,y: bounds.midY-9,width:18,height:18)); focus.lineWidth = 2; focus.stroke()
        }
    }
}

private final class StatusProgressIndicator: NSProgressIndicator {
    override func hitTest(_ point:NSPoint) -> NSView? { nil }
}
final class SpeechStatusHelpPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
