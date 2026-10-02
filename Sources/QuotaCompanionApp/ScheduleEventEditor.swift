import AppKit
import SwiftUI
import QuotaCore

struct ScheduleEventEditor: View {
    @ObservedObject var secretary: SecretaryModel
    @ObservedObject var navigation: SettingsNavigation
    let copy: Copybook
    @Environment(\.ownedDismiss) private var dismiss
    @State private var title: String
    @State private var startHour: String
    @State private var startMinute: String
    @State private var endHour: String
    @State private var endMinute: String
    @State private var focus = 0
    @State private var message = ""
    @State private var showError = false
    @State private var invalidFocus = 0
    @State private var proposal: ScheduleResolution?
    @State private var proposalDescription = ""
    @State private var colorHex: String?
    @State private var categoryID: UUID?
    @State private var colorDraft: ColorEditorDraft?
    @State private var weekly = false
    @State private var daily = false
    @State private var days: Set<Int>
    @State private var discard = false
    @State private var confirm = false
    @State private var deleting = false
    private let original: ScheduleBlock
    private let originalDays: Set<Int>
    private let originalWeekly: Bool
    init(secretary: SecretaryModel, navigation: SettingsNavigation, copy: Copybook, initialWeekly: Bool = false) {
        self.secretary = secretary; self.navigation = navigation; self.copy = copy
        let b = secretary.eventBlock
        original = b; _title = State(initialValue: b.title)
        _startHour = State(initialValue: String(format: "%02d", b.start / 60)); _startMinute = State(initialValue: String(format: "%02d", b.start % 60))
        _endHour = State(initialValue: String(format: "%02d", b.end / 60)); _endMinute = State(initialValue: String(format: "%02d", b.end % 60))
        _colorHex = State(initialValue: b.colorHex)
        _categoryID = State(initialValue: b.categoryID)
        let restored = secretary.data.editingScope(for: b.id, on: secretary.eventDate)
        let repeating = restored.weekdays ?? []
        let selected = repeating.isEmpty ? Set([(Calendar.current.component(.weekday, from: secretary.eventDate) + 5) % 7 + 1]) : repeating
        originalDays = selected; _days = State(initialValue: selected)
        let repeats = initialWeekly || (!secretary.eventIsNew && restored.weekdays != nil)
        originalWeekly = repeats
        _weekly = State(initialValue: repeats)
        _daily = State(initialValue: selected.count == 7)
    }
    private var selectedDays: Set<Int> { daily ? Set(1...7) : days }
    private var start: Int? { SegmentedScheduleTime.value(startHour, startMinute, end: false) }
    private var end: Int? { SegmentedScheduleTime.value(endHour, endMinute, end: true) }
    private var dirty: Bool { categoryID != original.categoryID || title != original.title || start != original.start || end != original.end || colorHex != original.colorHex || weekly != originalWeekly || selectedDays != originalDays }
    private var valid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && start != nil && end != nil && start! < end! && (!weekly || !selectedDays.isEmpty)
    }
    private func dayName(_ day: Int) -> String { copy.text(["周一","周二","周三","周四","周五","周六","周日"][day-1], ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"][day-1]) }
    private var scopeDescription: String {
        if weekly {
            let affected = selectedDays.union(secretary.data.repeatingDays(for: original.id)).sorted().map(dayName).joined(separator: "、")
            return copy.text("影响整个重复计划：", "Entire recurring plan: ") + affected
        }
        return SecretaryData.dayKey(secretary.eventDate) + copy.text("，其他日期不变。", "; other dates remain unchanged.")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(secretary.eventIsNew ? copy.text("新增日程", "New event") : copy.text("编辑日程", "Edit event")).font(.system(size: 17, weight: .semibold))
            SettingsPicker(copy.text("分类", "Category"), selection: $categoryID, options:
                [SettingsChoice<UUID?>(nil, copy.text("未分类", "Uncategorized"))] + secretary.data.categories.map { SettingsChoice<UUID?>($0.id, $0.name) })
            ImmediateScheduleTitleField(text: $title, placeholder: copy.text("事项名称", "Event name"), requestFocus: focus == 5)
                .frame(height: 20).padding(8).background(.white, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.gray.opacity(0.2)))
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                GridRow { Text(copy.text("开始时间", "Start")); SegmentedScheduleTime(hour: $startHour, minute: $startMinute, label: copy.text("开始时间", "Start time"), focus: focus, hourFocus: 1) }
                GridRow { Text(copy.text("结束时间", "End")); SegmentedScheduleTime(hour: $endHour, minute: $endMinute, label: copy.text("结束时间", "End time"), focus: focus, hourFocus: 3, endTime: true) }
                GridRow {
                    Text(copy.text("修改范围", "Scope"))
                    Picker("", selection: $weekly) {
                        Text(Calendar.current.isDateInToday(secretary.eventDate) ? copy.text("仅今天", "Only today") : copy.text("仅所选当天", "Only selected day")).tag(false)
                        Text(copy.text("每周重复计划", "Weekly repeating plan")).tag(true)
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .trailing)
                }
            }.textFieldStyle(.roundedBorder)
            if categoryID == nil { HStack(spacing: 9) {
                Text(copy.text("填充颜色", "Fill color"))
                ForEach(ScheduleEventPalette.presets, id: \.hex) { preset in
                    Button { colorHex = preset.hex } label: {
                        Circle().fill(Color(nsColor: ScheduleEventPalette.color(preset.hex))).frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder((colorHex ?? "F2F2F2") == preset.hex ? Color.primary : .clear, lineWidth: 1.5))
                    }.buttonStyle(.plain).accessibilityLabel(copy.text(preset.zh, preset.en))
                        .accessibilityAddTraits((colorHex ?? "F2F2F2") == preset.hex ? .isSelected : [])
                }
                Button { colorDraft = .init(target: .schedule, hex: "#" + (colorHex ?? "F2F2F2")) } label: {
                    RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: ScheduleEventPalette.color(colorHex)))
                        .frame(width: 42, height: 22).overlay(RoundedRectangle(cornerRadius: 7).stroke(.gray.opacity(0.4)))
                }.buttonStyle(.plain).accessibilityLabel(copy.text("自定义填充色", "Custom fill color"))
            } }
            if weekly {
                Picker(copy.text("重复", "Repeat"), selection: $daily) {
                    Text(copy.text("每天", "Every day")).tag(true)
                    Text(copy.text("自定义星期", "Custom weekdays")).tag(false)
                }.pickerStyle(.segmented)
                if !daily {
                    HStack(spacing: 5) {
                        ForEach(1...7, id: \.self) { day in
                            ScheduleWeekdayButton(title: dayName(day), isOn: Binding(get: { days.contains(day) }, set: { if $0 { days.insert(day) } else { days.remove(day) } })).frame(width: 50, height: 24)
                        }
                    }
                }
            }
            HStack {
                if !secretary.eventIsNew {
                    Button(copy.text("删除事项", "Delete event")) { deleting = true; prepare() }
                }
                Spacer()
                Button(copy.text("取消", "Cancel"), action: cancel).keyboardShortcut(.cancelAction)
                Button(copy.text("保存", "Save")) { deleting = false; prepare() }.keyboardShortcut(.defaultAction)
            }
        }.font(.system(size: 13)).foregroundStyle(ManagementStyle.ink).transaction { $0.animation = nil; $0.disablesAnimations = true }
            .padding(24).frame(width: 460).background(ManagementStyle.background).environment(\.colorScheme, .light).interactiveDismissDisabled()
            .ownedSheet(item: $colorDraft) { draft in
                ColorEditor(copy: copy, draft: draft, onSave: { result in
                    colorHex = String(result.hex.dropFirst()); colorDraft = nil
                }, onCancel: { colorDraft = nil })
            }
            .ownedAlert(copy.text("放弃未保存的修改？", "Discard unsaved changes?"), isPresented: $discard) {
                Button(copy.text("继续编辑", "Keep editing"), role: .cancel) { navigation.closeAfterEditor = false }
                Button(copy.text("放弃修改", "Discard"), role: .destructive) { dismiss() }
            }
            .ownedAlert(deleting ? copy.text("确认删除事项？", "Delete event?") : copy.text("确认保存日程？", "Save schedule changes?"), isPresented: $confirm) {
                Button(copy.text("取消", "Cancel"), role: .cancel) {}
                Button(deleting ? copy.text("删除", "Delete") : (proposal?.adjustments.isEmpty == false ? copy.text("覆盖并保存", "Overwrite and save") : copy.text("保存", "Save"))) { save() }
            } message: { Text(proposalDescription) }
            .ownedAlert(copy.text("无法保存", "Could not save"), isPresented: $showError) {
                Button(copy.text("确定", "OK")) { focus = invalidFocus }
            } message: { Text(message) }
            .onChange(of: navigation.closeEditorRequest) { _, _ in cancel() }
    }
    private func cancel() { if dirty { discard = true } else { dismiss() } }
    private func prepare(forceConfirmation: Bool = false) {
        focus = 0
        guard deleting || valid else {
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { message = copy.text("请输入事项名称。", "Enter an event name."); invalidFocus = 5 }
            else if start == nil { message = copy.text("开始时间应为 00:00–23:59。", "Start time must be 00:00–23:59."); invalidFocus = SegmentedScheduleTime.value(startHour, "00", end: false) == nil ? 1 : 2 }
            else if end == nil || end! <= start! { message = copy.text("结束时间须晚于开始，最晚为 24:00。", "End must follow start, up to 24:00."); invalidFocus = SegmentedScheduleTime.value(endHour, "00", end: true) == nil || end != nil ? 3 : 4 }
            else { message = copy.text("请选择至少一个重复星期。", "Select at least one weekday."); invalidFocus = 0 }
            showError = true; return
        }
        var block = original
        if !deleting { block.start = start!; block.end = end!; block.title = title.trimmingCharacters(in: .whitespacesAndNewlines); block.colorHex = colorHex; block.categoryID = categoryID }
        do {
            let result = try secretary.data.resolving(block, on: secretary.eventDate, weekdays: weekly ? selectedDays : nil, delete: deleting)
            proposal = result
            let changes = result.adjustments.map { change in
                let context = change.context.hasPrefix("weekday:") ? dayName(Int(change.context.dropFirst(8))!) : change.context
                let after = change.after.isEmpty ? copy.text("删除", "Deleted") : change.after.map(\.timeLabel).joined(separator: "、")
                return "\(context) · \(change.before.title)：\(change.before.timeLabel) → \(after)"
            }
            let currentDay = (Calendar.current.component(.weekday, from: secretary.eventDate) + 5) % 7 + 1
            let absent = weekly && !deleting && !selectedDays.contains(currentDay) ? [copy.text("未选择当前日期对应的星期；保存后这条事项将不再出现在当天。", "This weekday is not selected; the event will no longer appear on this date.")] : []
            proposalDescription = ([scopeDescription] + (weekly ? [copy.text("重复星期统一采用本次输入时间；更新当天这条事项的旧记录，其他单日调整保留。", "Selected weekdays use the entered times. This occurrence is updated; other date overrides remain.")] : []) + absent + changes).joined(separator: "\n\n")
            if forceConfirmation || weekly || deleting || !changes.isEmpty { confirm = true } else { save() }
        } catch { message = error.localizedDescription; showError = true }
    }
    private func save() {
        guard let proposal else { return }
        guard secretary.data == proposal.baseline else { prepare(forceConfirmation: true); return }
        do { try secretary.commitEvent(proposal); dismiss() }
        catch { message = error.localizedDescription; invalidFocus = 0; showError = true }
    }
}
