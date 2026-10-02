import SwiftUI

struct SpeechEditingDraft: Equatable {
    var template: SpeechTemplate
    var rule: QuotaSpeechRule
    var thresholdText: String
    private let original: SpeechTemplate
    private let originalRule: QuotaSpeechRule
    private let originalText: String
    init(template: SpeechTemplate, rule: QuotaSpeechRule) {
        self.template = template; self.rule = rule; original = template; originalRule = rule
        thresholdText = rule.thresholds.map(String.init).joined(separator: ", "); originalText = thresholdText
    }
    var dirty: Bool {
        template.kind != original.kind || !SpeechInlineDocument.sameContent(template.normalizedPieces, original.normalizedPieces)
            || rule != originalRule || thresholdText != originalText
    }
}

struct SpeechTemplateEditor: View {
    @ObservedObject var speech: CompanionSpeech
    let copy: Copybook
    @Binding var draft: SpeechEditingDraft
    @StateObject private var inlineActions = SpeechInlineActions()
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if draft.template.kind == .quota {
                SettingsControlRow(title: copy.text("提醒阈值（%）", "Thresholds (%)")) {
                    TextField("30, 15, 5", text: $draft.thresholdText).textFieldStyle(.roundedBorder)
                }
                SettingsPicker(copy.text("提醒方式", "Delivery"), selection: $draft.rule.delivery,
                               options: QuotaDelivery.allCases.map { SettingsChoice($0, $0.title(copy)) })
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { tokenButtons }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) { tokenButtons }
            }
            SpeechInlineEditor(template: $draft.template, copy: copy, actions: inlineActions).frame(height: 120)
            Text(draft.template.example(copy, language: speech.cloudLanguage)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                .padding(10).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button(copy.text("试听示例", "Preview sample")) { speech.previewTemplate(draft.template, copy: copy) }.disabled(speech.cloudBusy)
                Button(copy.text("恢复默认", "Restore default")) { draft.template = .standard(draft.template.kind, chinese: copy.locale.language.languageCode?.identifier == "zh") }
                Spacer()
                Button(copy.text("取消", "Cancel")) { _ = speech.discardDraft(copy: copy) }
                Button(copy.text("保存", "Save")) { speech.saveDraft(copy: copy) }
            }
        }.font(.system(size: 13))
    }
    private var tokenButtons: some View {
        ForEach(draft.template.availableTokens, id: \.self) { token in
            Button(token.title(copy)) { inlineActions.insert(token) }
                .help(copy.text("在光标处插入", "Insert at cursor") + " · " + token.title(copy))
        }
    }
}
