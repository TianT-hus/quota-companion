import SwiftUI
import QuotaCore

struct AppearanceColorControls: View {
    @ObservedObject var model: CompanionModel
    @State private var editing: ColorEditorDraft?
    private var c: Copybook { model.copy }
    var accessibility = CompanionAccessibility()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsControlRow(title: c.text("额度配色", "Quota color"), expanding: true) { palette(.quota) }
            SettingsRowDivider()
            SettingsControlRow(title: c.text("进度条样式", "Progress bar style"), trailing: true) {
                HStack(spacing: 12) {
                    Text(c.text("跟随额度配色", "Match quota color"))
                    SettingsNativeSwitch(title: c.text("跟随额度配色", "Match quota color"), isOn: $model.customAppearance.progressFollowsQuota, highContrast: accessibility.contrast == .increased).frame(width: 40, height: 24)
                }
            }
            SettingsReveal(expanded: !model.customAppearance.progressFollowsQuota, trigger: c.text("跟随额度配色", "Match quota color")) {
                SettingsRowDivider()
                SettingsControlRow(title: c.text("进度条配色", "Progress bar color"), expanding: true) { palette(.progress) }
            }
            SettingsRowDivider()
            SettingsControlRow(title: c.text("额度文字显示", "Quota text style"), expanding: true) {
                strip(add: { editing = ColorEditorDraft(target: .text, hex: model.customAppearance.chest?.text ?? model.chestTextStyle.text.hexString, outline: model.customAppearance.chest?.outline ?? model.chestTextStyle.outline.hexString) }) {
                    ForEach(model.customAppearance.textPresets) { preset in
                        AppearanceSwatch(title: preset.name, selected: model.customAppearance.chestPresetID == preset.id) {
                            if model.customAppearance.chestPresetID == preset.id { edit(preset) } else {
                                var value = model.customAppearance; value.selectText(preset); model.saveAppearance(value)
                            }
                        } content: {
                            OutlinedQuotaSample(text: QuotaCore.RGBColor(hexString: preset.text) ?? .init(1,1,1), outline: QuotaCore.RGBColor(hexString: preset.outline) ?? .init(0,0,0)).fixedSize().scaleEffect(0.7)
                        }.contextMenu { Button(c.text("编辑", "Edit")) { edit(preset) } }
                    }
                }
            }
        }.ownedSheet(item: $editing) { draft in
            ColorEditor(copy: c, draft: draft, onSave: save, onCancel: { editing = nil }, onDelete: exists(draft) ? { remove(draft) } : nil, error: $model.appearanceDialog)
                .onAppear { model.colorEditorVisible = true }.onDisappear { model.colorEditorVisible = false }
        }
    }
    private func palette(_ target: ColorTarget) -> some View {
        strip(add: { editing = ColorEditorDraft(target: target, hex: (target == .quota ? model.quotaTint ?? model.palette.color : model.progressTint ?? model.palette.color).hexString) }) {
            ForEach(model.customAppearance.colors) { preset in
                let selected = (target == .quota ? model.customAppearance.quotaPresetID : model.customAppearance.progressPresetID) == preset.id
                AppearanceSwatch(title: "\(preset.name) \(preset.hex)", selected: selected) {
                    if selected { edit(preset, target) } else {
                        var value = model.customAppearance
                        select(preset, target, in: &value); model.saveAppearance(value)
                    }
                } content: {
                    (QuotaCore.RGBColor(hexString: preset.hex) ?? .init(0,0,0)).color
                }.contextMenu { Button(c.text("编辑", "Edit")) { edit(preset, target) } }
                .accessibilityIdentifier("settings.color.\(target).\(preset.id)")
            }
        }
    }
    private func strip<Content: View>(add: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal) { HStack(spacing: 4, content: content).padding(.horizontal, 2) }.scrollIndicators(.hidden).frame(height: 48)
            Button(action: add) {
                Image(systemName: "plus").frame(width: 32, height: 32)
                    .background(.white, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            }.buttonStyle(.plain).frame(width: 40, height: 44, alignment: .trailing).accessibilityLabel(c.text("添加预设", "Add preset"))
        }
    }
    private func edit(_ preset: ColorPreset, _ target: ColorTarget) { editing = .init(target: target, presetID: preset.id, name: preset.name, hex: preset.hex) }
    private func edit(_ preset: TextPreset) { editing = .init(target: .text, presetID: preset.id, name: preset.name, hex: preset.text, outline: preset.outline) }
    private func exists(_ draft: ColorEditorDraft) -> Bool {
        draft.target == .text ? model.customAppearance.textPresets.contains { $0.id == draft.presetID } : model.customAppearance.colors.contains { $0.id == draft.presetID }
    }
    private func select(_ preset: ColorPreset, _ target: ColorTarget, in value: inout CustomAppearance) {
        if target == .quota { value.quotaHex = preset.hex; value.quotaPresetID = preset.id }
        else { value.progressHex = preset.hex; value.progressPresetID = preset.id }
    }
    private func save(_ draft: ColorEditorDraft) {
        var value = model.customAppearance
        if draft.target == .text {
            let preset = TextPreset(id: draft.presetID, name: draft.name, text: draft.hex, outline: draft.outline)
            value.save(preset); value.selectText(preset)
        } else {
            let preset = ColorPreset(id: draft.presetID, name: draft.name, hex: draft.hex)
            value.save(preset); select(preset, draft.target, in: &value)
        }
        if model.saveAppearance(value) { editing = nil }
    }
    private func remove(_ draft: ColorEditorDraft) {
        var value = model.customAppearance
        if draft.target == .text { value.removeText(draft.presetID) } else { value.removeColor(draft.presetID) }
        if model.saveAppearance(value) { editing = nil }
    }
}

struct AppearanceSwatch<Content: View>: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hovering = false
    @FocusState private var focused: Bool
    var accessibility = CompanionAccessibility()
    var body: some View {
        Button(action: action) {
            content().frame(width: 32, height: 32)
                .background(.white, in: RoundedRectangle(cornerRadius: 6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected || focused ? ManagementStyle.selectionBorder : Color.gray.opacity(0.3), lineWidth: focused ? 3 : (selected || accessibility.contrast == .increased ? 2 : 1)))
                .scaleEffect(selected || hovering ? 1.25 : 1)
                .animation(accessibility.reduceMotion ? nil : .easeInOut(duration: 0.12), value: selected || hovering)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }.focused($focused).focusEffectDisabled()
            .accessibilityLabel(title).accessibilityAddTraits(selected ? [.isSelected] : []).help(title)
    }
}
