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
    private var minimumZoom: Double { BackgroundComposition.minimumZoom(image: draft.image.size, viewport: CompactHoverMetrics.size) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(preview ? c.text("查看卡片效果", "Preview card effect") : c.text("裁剪背景图片", "Crop background image"))
                    .font(.system(size: 17, weight: .semibold))
                Spacer(); Text(preview ? "2 / 2" : "1 / 2").foregroundStyle(.secondary).monospacedDigit()
            }
            Picker(c.text("卡片比例", "Card aspect ratio"), selection: $doubleRow) {
                Text(c.text("单额度", "One window")).tag(false)
                Text(c.text("双额度", "Two windows")).tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 260)
            if preview {
                effect.frame(height: 280)
                HStack {
                    Text(c.text("图片透明度", "Image transparency"))
                    AppearancePercentControl(value: Binding(get: { 100 * (1 - composition.safeOpacity) }, set: { composition.opacity = 1 - $0 / 100 }), title: c.text("图片透明度", "Image transparency"))
                }
            } else {
                BackgroundCropCanvas(image: draft.image, composition: $composition, doubleRow: doubleRow,
                    label: c.text("图片裁剪区域，拖动移动，双指缩放；点击后可用方向键微调", "Crop area. Drag or pinch; click then use arrow keys to nudge."))
                    .frame(height: 280).clipShape(RoundedRectangle(cornerRadius: 10))
                HStack {
                    Image(systemName: "minus.magnifyingglass")
                    SettingsAdjustmentSlider(value: Binding(get: { max(minimumZoom, composition.zoom) }, set: { composition.zoom = $0; composition.darkestPixelHex = nil }), range: minimumZoom...4, title: c.text("缩放", "Zoom"))
                        .accessibilityLabel(c.text("缩放", "Zoom"))
                    Image(systemName: "plus.magnifyingglass")
                    Text(String(format: "%.1f×", composition.zoom)).monospacedDigit().frame(width: 38)
                }
            }
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
            .ownedAlert(c.text("背景未更改", "Background unchanged"), isPresented: Binding(get: { model.backgroundDialog != nil }, set: { if !$0 { model.backgroundDialog = nil } })) {
                Button(c.text("确定", "OK")) { model.backgroundDialog = nil }
            } message: { Text(model.backgroundDialog ?? "") }
    }
    private var effect: some View {
        CompanionRootView(model: model, previewDate: Date(timeIntervalSince1970: 1790606580), sampleQuotaCount: doubleRow ? 2 : 1, sampleScale: 3.5,
                          previewBackground: CompanionBackground(image: draft.image, appearances: .standard), previewComposition: composition)
            .frame(width: 525, height: 280)
    }
}
