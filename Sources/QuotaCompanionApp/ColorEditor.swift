import AppKit
import SwiftUI
import QuotaCore

enum ColorTarget { case quota, progress, text }
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
        }.font(.system(size: 17, weight: .bold, design: .monospaced)).accessibilityLabel("79%")
    }
}

struct ColorEditor: View {
    let copy: Copybook
    let draft: ColorEditorDraft
    let onSave: (ColorEditorDraft) -> Void
    let onCancel: () -> Void
    @State private var name: String
    @State private var primary: String
    @State private var outline: String
    @State private var editingOutline = false
    @State private var hex: String
    @State private var rgb = ["114", "213", "232"]
    @State private var hue: Double = 0.52
    @State private var saturation: Double = 0.5
    @State private var brightness: Double = 0.9
    init(copy: Copybook, draft: ColorEditorDraft, onSave: @escaping (ColorEditorDraft) -> Void, onCancel: @escaping () -> Void) {
        self.copy = copy; self.draft = draft; self.onSave = onSave; self.onCancel = onCancel
        _name = State(initialValue: draft.name); _primary = State(initialValue: draft.hex)
        _outline = State(initialValue: draft.outline); _hex = State(initialValue: draft.hex)
    }
    private var isText: Bool { draft.target == .text }
    private var valid: Bool { QuotaCore.RGBColor(hexString: hex) != nil && QuotaCore.RGBColor.rgbStrings(rgb) != nil && QuotaCore.RGBColor(hexString: primary) != nil && (!isText || QuotaCore.RGBColor(hexString: outline) != nil) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(copy.text(isText ? "文字样式" : "自定义颜色", isText ? "Text style" : "Custom color")).font(.system(size: 17, weight: .semibold))
            TextField(copy.text("预设名称（可选）", "Preset name (optional)"), text: $name).textFieldStyle(.roundedBorder)
            if isText {
                Picker(copy.text("调整", "Edit"), selection: $editingOutline) {
                    Text(copy.text("文字颜色", "Text color")).tag(false)
                    Text(copy.text("描边颜色", "Outline color")).tag(true)
                }.pickerStyle(.segmented).disabled(!valid)
            }
            colorPlane
            HStack {
                Text(copy.text("色相", "Hue"))
                Slider(value: Binding(get: { hue }, set: { hue = $0; setHSV() }), in: 0...1).accessibilityLabel(copy.text("色相", "Hue"))
                    .background(LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 0.1).map { Color(hue: $0, saturation: 1, brightness: 1) }, startPoint: .leading, endPoint: .trailing).frame(height: 5).clipShape(Capsule()))
            }
            HStack(alignment: .bottom, spacing: 12) {
                RoundedRectangle(cornerRadius: 8).fill((QuotaCore.RGBColor(hexString: hex) ?? QuotaCore.RGBColor(hex: 0x72D5E8)).color).frame(width: 38, height: 38).overlay(RoundedRectangle(cornerRadius: 8).stroke(.gray.opacity(0.4)))
                VStack(alignment: .leading, spacing: 4) {
                    Text("HEX").font(.system(size: 12, weight: .semibold))
                    TextField("#72D5E8", text: Binding(get: { hex }, set: { updateHex($0) })).textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                        .accessibilityLabel("HEX").accessibilityIdentifier("color.hex")
                }
                Button { NSColorSampler().show { color in
                    guard let color = color?.usingColorSpace(.sRGB) else { return }
                    let picked = QuotaCore.RGBColor(Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent))
                    Task { @MainActor in load(picked) }
                } } label: { Label(copy.text("取色", "Pick"), systemImage: "eyedropper") }
            }
            HStack {
                ForEach(0..<3) { index in
                    Text(["R", "G", "B"][index])
                    TextField("0–255", text: Binding(get: { rgb[index] }, set: { value in
                        rgb[index] = value
                        if let color = QuotaCore.RGBColor.rgbStrings(rgb) { hex = color.hexString; commitColor(color); syncHSV(color) }
                    })).textFieldStyle(.roundedBorder).accessibilityLabel(["Red", "Green", "Blue"][index])
                }
            }
            if !valid { Text(copy.text("请输入六位 HEX，或 0–255 的 RGB 整数。", "Enter six HEX digits and RGB integers from 0 to 255.")).foregroundStyle(.red).font(.system(size: 12)) }
            if isText {
                HStack {
                    OutlinedQuotaSample(text: QuotaCore.RGBColor(hexString: primary) ?? QuotaCore.RGBColor(1,1,1), outline: QuotaCore.RGBColor(hexString: outline) ?? QuotaCore.RGBColor(0,0,0))
                        .padding(12).background(QuotaCore.RGBColor(hex: 0xBFEFF7).color, in: RoundedRectangle(cornerRadius: 8))
                    Text(copy.text("效果预览 · 不添加胸前底板", "Preview · No plate behind the text")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if let a = QuotaCore.RGBColor(hexString: primary), let b = QuotaCore.RGBColor(hexString: outline), a.contrast(with: b) < 3 {
                    Text(copy.text("文字与描边颜色接近，建议增加明暗差异。", "Text and outline are similar. Increase their contrast for readability.")).font(.system(size: 12)).foregroundStyle(.orange)
                }
            } else {
                LiquidProgressView(remaining: 79, active: false, stale: false, appearance: BackgroundAppearances.standard[BackgroundAppearanceKey(dark: false, highContrast: false, reduceTransparency: false)], customTint: QuotaCore.RGBColor(hexString: hex)).frame(height: 14)
                Text(copy.text("渐变效果预览；低额度仍使用告警色。", "Gradient preview. Low quotas keep warning colors.")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(copy.text("取消", "Cancel"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(copy.text("保存并应用", "Save & apply")) {
                    var result = draft
                    result.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
                    result.hex = QuotaCore.RGBColor(hexString: primary)!.hexString
                    result.outline = QuotaCore.RGBColor(hexString: outline)!.hexString
                    if result.name.isEmpty { result.name = result.hex }
                    onSave(result)
                }.disabled(!valid).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 480).font(.system(size: 13))
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
        hex = value
        if let color = QuotaCore.RGBColor(hexString: value) { commitColor(color); rgb = [color.r,color.g,color.b].map { String(Int(($0*255).rounded())) }; syncHSV(color) }
    }
    private func load(_ color: QuotaCore.RGBColor) { hex = color.hexString; rgb = [color.r,color.g,color.b].map { String(Int(($0*255).rounded())) }; commitColor(color); syncHSV(color) }
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
        hex = result.hexString; rgb = [result.r,result.g,result.b].map { String(Int(($0*255).rounded())) }; commitColor(result)
    }
}
