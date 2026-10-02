import AppKit
import SwiftUI
import QuotaCore

enum ColorTarget { case quota, progress, text, schedule }
struct ColorEditorDraft: Identifiable {
    let id = UUID()
    var target: ColorTarget
    var presetID: UUID = UUID()
    var name = ""
    var hex = "#72D5E8"
    var outline = "#10233C"
}

struct OutlinedQuotaSample: View {
    let text: QuotaCore.RGBColor
    let outline: QuotaCore.RGBColor
    var body: some View {
        ZStack {
            ForEach(0..<8) { i in Text("79%").foregroundStyle(outline.color).offset(x: cos(Double(i) * .pi / 4), y: sin(Double(i) * .pi / 4)) }
            Text("79%").foregroundStyle(text.color)
        }.font(.system(size: 17, weight: .bold)).monospacedDigit().accessibilityElement(children: .ignore).accessibilityLabel("79%")
    }
}

struct ColorEditor: View {
    let copy: Copybook
    let draft: ColorEditorDraft
    let onSave: (ColorEditorDraft) -> Void
    let onCancel: () -> Void
    let onDelete: (() -> Void)?
    @Binding var error: String?
    @State private var prompt: String?
    @State private var name: String
    @State private var primary: String
    @State private var outline: String
    @State private var editingOutline = false
    @State private var entry: ColorEntry
    @State private var invalidInput = false
    @State private var invalidField = 0
    @FocusState private var inputFocus: Int?
    @State private var hue: Double = 0.52
    @State private var saturation: Double = 0.5
    @State private var brightness: Double = 0.9
    init(copy: Copybook, draft: ColorEditorDraft, onSave: @escaping (ColorEditorDraft) -> Void, onCancel: @escaping () -> Void, onDelete: (() -> Void)? = nil, error: Binding<String?> = .constant(nil), initialFormat: ColorEntryFormat = .hex) {
        self.copy = copy; self.draft = draft; self.onSave = onSave; self.onCancel = onCancel
        self.onDelete = onDelete; _error = error
        _name = State(initialValue: draft.name); _primary = State(initialValue: draft.hex)
        _outline = State(initialValue: draft.outline)
        var input = ColorEntry(QuotaCore.RGBColor(hexString: draft.hex) ?? .init(hex: 0x72D5E8)); input.select(initialFormat)
        _entry = State(initialValue: input)
    }
    private var isText: Bool { draft.target == .text }
    private var valid: Bool { entry.invalidField == nil }
    private var dirty: Bool { !valid || name != draft.name || QuotaCore.RGBColor(hexString: primary) != QuotaCore.RGBColor(hexString: draft.hex) || QuotaCore.RGBColor(hexString: outline) != QuotaCore.RGBColor(hexString: draft.outline) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(copy.text(isText ? "文字样式" : "自定义颜色", isText ? "Text style" : "Custom color")).font(.system(size: 17, weight: .semibold))
            if draft.target != .schedule {
                TextField(copy.text("预设名称（可选）", "Preset name (optional)"), text: $name).textFieldStyle(.roundedBorder)
            }
            if isText {
                Picker(copy.text("调整", "Edit"), selection: Binding(get: { editingOutline }, set: { if validateInput() { editingOutline = $0 } })) {
                    Text(copy.text("文字颜色", "Text color")).tag(false)
                    Text(copy.text("描边颜色", "Outline color")).tag(true)
                }.pickerStyle(.segmented)
            }
            colorPlane
            HStack {
                Text(copy.text("色相", "Hue"))
                Slider(value: Binding(get: { hue }, set: { hue = $0; setHSV() }), in: 0...1).accessibilityLabel(copy.text("色相", "Hue"))
                    .background(LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 0.1).map { Color(hue: $0, saturation: 1, brightness: 1) }, startPoint: .leading, endPoint: .trailing).frame(height: 5).clipShape(Capsule()))
            }
            HStack(spacing: 12) {
                NativeSettingsPicker(title: copy.text("颜色格式", "Color format"), selection: Binding(get: { entry.format }, set: { mode in
                    if validateInput() { entry.select(mode) }
                }), options: ColorEntryFormat.allCases.map { SettingsChoice($0, $0.rawValue) }).frame(width: 82, height: 28)
                Group {
                    if entry.format == .hex {
                        TextField("#72D5E8", text: Binding(get: { entry.hex }, set: { updateHex($0) }))
                            .focused($inputFocus, equals: 0).accessibilityLabel("HEX").accessibilityIdentifier("color.hex")
                    } else {
                        HStack(spacing: 6) {
                            ForEach(0..<3) { index in
                                TextField(["R", "G", "B"][index], text: Binding(get: { entry.rgb[index] }, set: { value in
                                    entry.editRGB(value, at: index)
                                    if valid { commitColor(entry.color); syncHSV(entry.color) }
                                })).focused($inputFocus, equals: index + 1)
                                    .accessibilityLabel(["Red", "Green", "Blue"][index]).help(["R · 0–255", "G · 0–255", "B · 0–255"][index])
                            }
                        }
                    }
                }.textFieldStyle(.roundedBorder).multilineTextAlignment(.center).onSubmit { _ = validateInput() }
                RoundedRectangle(cornerRadius: 6).fill(entry.color.color).frame(width: 32, height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.gray.opacity(0.4))).accessibilityLabel(copy.text("当前颜色", "Current color"))
                Button { NSColorSampler().show { color in
                    guard let color = color?.usingColorSpace(.sRGB) else { return }
                    let picked = QuotaCore.RGBColor(Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent))
                    Task { @MainActor in load(picked) }
                } } label: { Label(copy.text("取色", "Pick"), systemImage: "eyedropper") }
            }
            if isText {
                HStack {
                    OutlinedQuotaSample(text: QuotaCore.RGBColor(hexString: primary) ?? QuotaCore.RGBColor(1,1,1), outline: QuotaCore.RGBColor(hexString: outline) ?? QuotaCore.RGBColor(0,0,0))
                        .padding(12).background(QuotaCore.RGBColor(hex: 0xBFEFF7).color, in: RoundedRectangle(cornerRadius: 8))
                }
                if let a = QuotaCore.RGBColor(hexString: primary), let b = QuotaCore.RGBColor(hexString: outline), a.contrast(with: b) < 3 {
                    Text(copy.text("文字与描边颜色接近，建议增加明暗差异。", "Text and outline are similar. Increase their contrast for readability.")).font(.system(size: 12)).foregroundStyle(.orange)
                }
            } else if draft.target == .schedule {
                Text(copy.text("示例事项", "Sample event")).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(entry.color.color, in: RoundedRectangle(cornerRadius: 8))
            } else {
                LiquidProgressView(remaining: 79, active: false, stale: false, appearance: BackgroundAppearances.standard[BackgroundAppearanceKey(dark: false, highContrast: false, reduceTransparency: false)], customTint: entry.color).frame(height: 14)
            }
            HStack {
                if let onDelete {
                    Button { prompt = "delete" } label: { Image(systemName: "trash") }.accessibilityLabel(copy.text("删除预设", "Delete preset"))
                        .ownedAlert(copy.text("删除这个预设？", "Delete this preset?"), isPresented: Binding(get: { prompt == "delete" }, set: { if !$0 { prompt = nil } })) {
                            Button(copy.text("取消", "Cancel"), role: .cancel) {}
                            Button(copy.text("删除", "Delete"), role: .destructive, action: onDelete)
                        } message: { Text(copy.text("只从预设库移除，当前使用的外观保持不变。", "Remove from the library without changing the current appearance.")) }
                }
                Spacer()
                Button(copy.text("取消", "Cancel")) {
                    if dirty { prompt = "discard" } else { onCancel() }
                }.keyboardShortcut(.cancelAction)
                    .ownedAlert(copy.text("放弃未保存的修改？", "Discard unsaved changes?"), isPresented: Binding(get: { prompt == "discard" }, set: { if !$0 { prompt = nil } })) {
                        Button(copy.text("继续编辑", "Keep editing"), role: .cancel) {}
                        Button(copy.text("放弃修改", "Discard"), role: .destructive, action: onCancel)
                    }
                Button(draft.target == .schedule ? copy.text("使用颜色", "Use color") : copy.text("保存并应用", "Save & apply")) {
                    guard validateInput() else { return }
                    var result = draft
                    result.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
                    result.hex = QuotaCore.RGBColor(hexString: primary)!.hexString
                    result.outline = QuotaCore.RGBColor(hexString: outline)!.hexString
                    if result.name.isEmpty { result.name = result.hex }
                    onSave(result)
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 480).font(.system(size: 13)).interactiveDismissDisabled()
            .ownedAlert(copy.text("颜色无效", "Invalid color"), isPresented: $invalidInput) {
                Button(copy.text("确定", "OK")) { inputFocus = invalidField }
            } message: { Text(copy.text("请输入六位 HEX，或 0–255 的 RGB 整数。", "Enter six HEX digits or RGB integers from 0 to 255.")) }
            .ownedAlert(copy.text("外观未保存", "Appearance not saved"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button(copy.text("确定", "OK")) { error = nil }
            } message: { Text(error ?? "") }
            .foregroundStyle(QuotaCore.RGBColor(hex: 0x10233C).color)
            .background(QuotaCore.RGBColor(hex: 0xF8FBFE).color).environment(\.colorScheme, .light)
            .onAppear { load(QuotaCore.RGBColor(hexString: primary) ?? QuotaCore.RGBColor(hex: 0x72D5E8)) }
            .onChange(of: editingOutline) { _, value in load(QuotaCore.RGBColor(hexString: value ? outline : primary) ?? QuotaCore.RGBColor(0,0,0)) }
    }
    private var colorPlane: some View {
        GeometryReader { g in
            ZStack {
                Color(hue: hue, saturation: 1, brightness: 1)
                LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                Circle().strokeBorder(.white, lineWidth: 3).background(Circle().stroke(.black.opacity(0.4), lineWidth: 1)).frame(width: 18, height: 18)
                    .position(x: saturation * g.size.width, y: (1-brightness) * g.size.height)
            }.clipShape(RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    saturation = min(1, max(0, Double(value.location.x / g.size.width))); brightness = min(1, max(0, 1-Double(value.location.y/g.size.height))); setHSV()
                })
                .accessibilityElement(children: .ignore).accessibilityLabel(copy.text("颜色区域；也可用 HEX 和 RGB 输入", "Color area; use HEX or RGB fields for keyboard input"))
        }.frame(height: 180)
    }
    private func commitColor(_ color: QuotaCore.RGBColor) { if editingOutline { outline = color.hexString } else { primary = color.hexString } }
    private func updateHex(_ value: String) {
        entry.editHex(value)
        if valid { commitColor(entry.color); syncHSV(entry.color) }
    }
    private func load(_ color: QuotaCore.RGBColor) { entry.load(color); commitColor(color); syncHSV(color) }
    @discardableResult private func validateInput() -> Bool {
        guard let field = entry.invalidField else { return true }
        if !invalidInput { invalidField = field; inputFocus = nil; invalidInput = true }
        return false
    }
    private func syncHSV(_ color: QuotaCore.RGBColor) {
        let native = NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: 1)
        hue = Double(native.hueComponent); saturation = Double(native.saturationComponent); brightness = Double(native.brightnessComponent)
    }
    private func setHSV() {
        let h = hue * 6, chroma = brightness * saturation
        let x = chroma * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)), m = brightness-chroma
        let channels: (Double, Double, Double)
        switch Int(h) % 6 {
        case 0: channels = (chroma,x,0)
        case 1: channels = (x,chroma,0)
        case 2: channels = (0,chroma,x)
        case 3: channels = (0,x,chroma)
        case 4: channels = (x,0,chroma)
        default: channels = (chroma,0,x)
        }
        let result = QuotaCore.RGBColor(channels.0+m, channels.1+m, channels.2+m)
        entry.load(result); commitColor(result)
    }
}
