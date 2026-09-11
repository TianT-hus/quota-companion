import SwiftUI
import QuotaCore

struct AppearanceColorControls: View {
    @ObservedObject var model: CompanionModel
    @State private var editing: ColorEditorDraft?
    private var c: Copybook { model.copy }
    private var chinese: Bool { c.locale.language.languageCode?.identifier == "zh" }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(c.text("额度配色", "Quota color")).fontWeight(.medium)
            palette(target: .quota)
            Text(c.text("低额度仍使用黄／橙／红告警色。", "Low quotas keep yellow, orange and red warning colors.")).font(.system(size: 12)).foregroundStyle(.secondary)
            Divider()
            Toggle(c.text("进度条跟随额度配色", "Match the progress bar to the quota color"), isOn: $model.customAppearance.progressFollowsQuota)
                .toggleStyle(.switch).controlSize(.small)
            if !model.customAppearance.progressFollowsQuota { palette(target: .progress) }
            Divider()
            Text(c.text("胸前文字", "Chest text")).fontWeight(.medium)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74, maximum: 90))], alignment: .leading, spacing: 8) {
                ForEach(ChestTextStyle.allCases, id: \.self) { style in
                    swatch(title: styleName(style), selected: model.customAppearance.chest == nil && model.chestTextStyle == style, action: { model.chestTextStyle = style }) {
                        OutlinedQuotaSample(text: style.text, outline: style.outline)
                    }.accessibilityIdentifier("settings.text.\(style.rawValue)")
                }
                ForEach(model.customAppearance.textPresets) { preset in
                    swatch(title: preset.name, selected: model.customAppearance.chest?.id == preset.id, action: { model.customAppearance.chest = preset }) {
                        OutlinedQuotaSample(text: QuotaCore.RGBColor(hexString: preset.text) ?? QuotaCore.RGBColor(1,1,1), outline: QuotaCore.RGBColor(hexString: preset.outline) ?? QuotaCore.RGBColor(0,0,0))
                    }.contextMenu {
                        Button(c.text("编辑", "Edit")) { editing = ColorEditorDraft(target: .text, presetID: preset.id, name: preset.name, hex: preset.text, outline: preset.outline) }
                        Button(c.text("删除预设", "Delete preset")) { model.customAppearance.removeText(preset.id) }
                    }
                }
                addButton { editing = ColorEditorDraft(target: .text, hex: model.customAppearance.chest?.text ?? model.chestTextStyle.text.hexString, outline: model.customAppearance.chest?.outline ?? model.chestTextStyle.outline.hexString) }
            }
            if !model.customAppearance.colors.isEmpty || !model.customAppearance.textPresets.isEmpty {
                DisclosureGroup(c.text("管理自定义预设", "Manage custom presets")) { management.padding(.top, 8) }
            }
        }.sheet(item: $editing) { draft in
            ColorEditor(copy: c, draft: draft, onSave: save, onCancel: { editing = nil })
        }
    }
    private func palette(target: ColorTarget) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74, maximum: 90))], alignment: .leading, spacing: 8) {
            ForEach(CompanionPalette.allCases, id: \.self) { p in
                swatch(title: p.title(chinese: chinese), selected: target == .quota ? (model.quotaTint == nil && model.palette == p) : model.customAppearance.progressHex == p.color.hexString, action: {
                    if target == .quota { model.palette = p }
                    else { model.customAppearance.progressHex = p.color.hexString; model.customAppearance.progressPresetID = nil }
                }) { Circle().fill(p.color.color).frame(width: 24, height: 24) }
                    .accessibilityIdentifier("settings.\(target == .quota ? "palette" : "progress").\(p.rawValue)")
            }
            ForEach(model.customAppearance.colors) { preset in
                swatch(title: preset.name, selected: target == .quota ? model.customAppearance.quotaPresetID == preset.id : model.customAppearance.progressPresetID == preset.id, action: { select(preset, target: target) }) {
                    Circle().fill((QuotaCore.RGBColor(hexString: preset.hex) ?? QuotaCore.RGBColor(0,0,0)).color).frame(width: 24, height: 24)
                }.contextMenu {
                    Button(c.text("编辑", "Edit")) { editing = ColorEditorDraft(target: target, presetID: preset.id, name: preset.name, hex: preset.hex) }
                    Button(c.text("删除预设", "Delete preset")) { model.customAppearance.removeColor(preset.id) }
                }
            }
            addButton { editing = ColorEditorDraft(target: target, hex: (target == .quota ? model.quotaTint ?? model.palette.color : model.progressTint ?? model.palette.color).hexString) }
        }
    }
    private var management: some View {
        VStack(spacing: 8) {
            ForEach(model.customAppearance.colors) { preset in
                HStack {
                    Circle().fill((QuotaCore.RGBColor(hexString: preset.hex) ?? QuotaCore.RGBColor(0,0,0)).color).frame(width: 14, height: 14)
                    Text(preset.name).lineLimit(1); Spacer()
                    Button(c.text("编辑", "Edit")) { editing = ColorEditorDraft(target: .quota, presetID: preset.id, name: preset.name, hex: preset.hex) }
                    Button(c.text("删除", "Delete")) { model.customAppearance.removeColor(preset.id) }
                }
            }
            ForEach(model.customAppearance.textPresets) { preset in
                HStack {
                    Text(preset.name).lineLimit(1); Spacer()
                    Button(c.text("编辑", "Edit")) { editing = ColorEditorDraft(target: .text, presetID: preset.id, name: preset.name, hex: preset.text, outline: preset.outline) }
                    Button(c.text("删除", "Delete")) { model.customAppearance.removeText(preset.id) }
                }
            }
        }
    }
    private func swatch<Content: View>(title: String, selected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            VStack(spacing: 5) { content().frame(height: 24); Text(title).font(.system(size: 12)).lineLimit(1) }
                .padding(.vertical, 8).frame(maxWidth: .infinity)
                .background(selected ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Color.accentColor : .gray.opacity(0.25), lineWidth: selected ? 2 : 1))
                .overlay(alignment: .topTrailing) { if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(Color.accentColor).padding(3) } }
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
    private func addButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus").font(.system(size: 19, weight: .medium)).frame(maxWidth: .infinity).frame(height: 55)
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4,3])))
        }.buttonStyle(.plain).foregroundStyle(Color.accentColor).accessibilityLabel(c.text("添加预设", "Add preset"))
    }
    private func select(_ preset: ColorPreset, target: ColorTarget) {
        if target == .quota { model.customAppearance.quotaHex = preset.hex; model.customAppearance.quotaPresetID = preset.id }
        else { model.customAppearance.progressHex = preset.hex; model.customAppearance.progressPresetID = preset.id }
    }
    private func save(_ draft: ColorEditorDraft) {
        if draft.target == .text {
            let preset = TextPreset(id: draft.presetID, name: draft.name, text: draft.hex, outline: draft.outline)
            model.customAppearance.save(preset); model.customAppearance.chest = preset
        } else {
            let preset = ColorPreset(id: draft.presetID, name: draft.name, hex: draft.hex)
            model.customAppearance.save(preset); select(preset, target: draft.target)
        }
        editing = nil
    }
    private func styleName(_ style: ChestTextStyle) -> String {
        switch style { case .whiteInk: c.text("白色", "White"); case .goldInk: c.text("暖金", "Gold"); case .inkWhite: c.text("深色", "Dark") }
    }
}
