import AppKit
import SwiftUI
import QuotaCore

struct BackgroundDraft: Identifiable {
    let id = UUID()
    let image: NSImage
    let prepared: PreparedBackground?
    var composition: BackgroundComposition
}

struct BackgroundEditor: View {
    @ObservedObject var model: CompanionModel
    let draft: BackgroundDraft
    @State private var composition: BackgroundComposition
    @State private var doubleRow = false
    @State private var preview: Bool
    init(model: CompanionModel, draft: BackgroundDraft, startsWithPreview: Bool = false) {
        self.model = model; self.draft = draft
        _composition = State(initialValue: draft.composition); _preview = State(initialValue: startsWithPreview)
    }
    private var c: Copybook { model.copy }
    private var minimumZoom: Double { BackgroundComposition.minimumZoom(image: draft.image.size, viewport: CGSize(width: 200, height: doubleRow ? 80 : 56)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(preview ? c.text("查看卡片效果", "Preview card effect") : c.text("裁剪背景图片", "Crop background image"))
                    .font(.system(size: 17, weight: .semibold))
                Spacer(); Text(preview ? "2 / 2" : "1 / 2").foregroundStyle(.secondary).monospacedDigit()
            }
            Text(preview ? c.text("确认构图后调整图片浓度，应用后才会更改桌宠。", "Adjust image opacity. Your companion changes only after Apply.") : c.text("拖动图片选取画面；双指缩放，或使用下方滑杆。", "Drag to frame the image. Pinch to zoom or use the slider below."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Picker(c.text("卡片比例", "Card aspect ratio"), selection: $doubleRow) {
                Text(c.text("单额度", "One window")).tag(false)
                Text(c.text("双额度", "Two windows")).tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 260)
            if preview {
                effect.frame(height: 280)
                HStack {
                    Text(c.text("图片不透明度", "Image opacity"))
                    Slider(value: $composition.opacity, in: 0...1).accessibilityLabel(c.text("图片不透明度", "Image opacity"))
                    Text("\(Int(composition.safeOpacity*100))%").monospacedDigit().frame(width: 38)
                }
                help(c.text("阅读保护会淡化图片，保证文字清晰。预览数值为示例。", "Readability protection softens the image. Quota values here are samples."))
            } else {
                BackgroundCropCanvas(image: draft.image, composition: $composition, doubleRow: doubleRow,
                    label: c.text("图片裁剪区域，拖动移动，双指缩放；点击后可用方向键微调", "Crop area. Drag or pinch; click then use arrow keys to nudge."))
                    .frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 10))
                HStack {
                    Image(systemName: "minus.magnifyingglass")
                    Slider(value: Binding(get: { max(minimumZoom, composition.zoom) }, set: { composition.zoom = $0; composition.darkestPixelHex = nil }), in: minimumZoom...4)
                        .accessibilityLabel(c.text("缩放", "Zoom"))
                    Image(systemName: "plus.magnifyingglass")
                    Text(String(format: "%.1f×", composition.zoom)).monospacedDigit().frame(width: 38)
                }
                help(c.text("可缩小至完整显示原图，留白显示玻璃底色。两种比例共用构图，取景略有不同。方向键微调，Shift 加快。", "Zoom out to fit the whole image; uncovered areas use glass. Layouts share framing with different crops. Arrow keys nudge; Shift moves faster."))
            }
            if !model.backgroundMessage.isEmpty { help(model.backgroundMessage) }
            HStack {
                if preview {
                    Button(c.text("返回裁剪", "Back to crop")) { preview = false }.disabled(model.isImportingBackground)
                } else {
                    Button(c.text("重置构图", "Reset framing")) { composition.x = 0.5; composition.y = 0.5; composition.zoom = 1; composition.darkestPixelHex = nil }
                }
                Spacer()
                Button(c.text("取消", "Cancel")) { model.backgroundDraft = nil }.keyboardShortcut(.cancelAction).disabled(model.isImportingBackground)
                Button(preview ? c.text("应用", "Apply") : c.text("下一步", "Next")) {
                    if preview { model.applyBackgroundDraft(draft, composition: composition) } else { preview = true }
                }.keyboardShortcut(.defaultAction).disabled(model.isImportingBackground)
            }
        }.padding(24).frame(width: 568).font(.system(size: 13))
            .foregroundStyle(QuotaCore.RGBColor(hex: 0x10233C).color)
            .background(QuotaCore.RGBColor(hex: 0xF8FBFE).color).environment(\.colorScheme, .light)
            .interactiveDismissDisabled(model.isImportingBackground)
    }
    private func help(_ text: String) -> some View { Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    private var effect: some View {
        let appearance = BackgroundAppearances.standard[BackgroundAppearanceKey(dark: false, highContrast: false, reduceTransparency: false)]
        return ZStack {
            GlassCardSurface(background: CompanionBackground(image: draft.image, appearances: .standard), appearance: appearance, solid: false, composition: composition)
            VStack(spacing: 10) {
                if doubleRow { sampleRow("5h 62%", remaining: 62, reset: c.text("2时18分", "2h18m"), appearance: appearance) }
                sampleRow(c.text("周 79%", "Week 79%"), remaining: 79, reset: c.text("6天12时", "6d12h"), appearance: appearance)
            }.padding(18)
        }.frame(height: doubleRow ? 208 : 145.6)
    }
    private func sampleRow(_ label: String, remaining: Double, reset: String, appearance: BackgroundAppearance) -> some View {
        VStack(spacing: 6) {
            HStack { Text(label).bold(); Spacer(); Label(reset, systemImage: "clock") }
            LiquidProgressView(remaining: remaining, active: false, stale: false, appearance: appearance, palette: model.palette, customTint: model.progressTint).frame(height: 14)
        }
    }
}
