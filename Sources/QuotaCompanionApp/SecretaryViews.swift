import AppKit
import QuotaCore
import SwiftUI

struct SecretarySummary: View {
    @ObservedObject var model: CompanionModel
    @ObservedObject var secretary: SecretaryModel
    let now: Date
    var renderScale: CGFloat = 1
    var sharedTextSize: CGFloat? = nil
    var sample: ScheduleBlock? = nil
    @Environment(\.displayScale) private var displayScale
    private func pt(_ value: CGFloat) -> CGFloat { (value * renderScale * displayScale).rounded() / displayScale }
    private var current: ScheduleBlock? { sample ?? secretary.data.current(at: now) }
    private var next: ScheduleBlock? { secretary.data.next(at: now) }
    private var emptyTitle: String {
        !secretary.hasPlan ? model.copy.text("添加时间表", "Add a schedule") : next == nil && !secretary.data.blocks(on: now).isEmpty ? model.copy.text("今日安排已结束", "Schedule finished") : model.copy.text("当前自由时间", "Free time now")
    }
    private var fullDescription: String {
        [current.map { $0.timeLabel + " " + $0.title } ?? emptyTitle]
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }
    var body: some View {
            VStack(alignment: .leading, spacing: pt(1)) {
                HStack(alignment: .top, spacing: pt(3)) {
                    Image(systemName: "clock").font(.system(size: pt(7), weight: .regular))
                        .padding(.top, pt(1))
                    if let item = current {
                        VStack(alignment: .leading, spacing: 0) {
                            HoverText(text: item.timeLabel, size: HoverTypography.secondarySize(scale: renderScale)).frame(height: pt(10))
                            Text(item.title).font(Font(HoverTypography.font(max(13, pt(7)))))
                                .lineLimit(2).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HoverText(text: emptyTitle, size: max(13, pt(7))).frame(height: pt(12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.frame(height: pt(CompactHoverMetrics.scheduleHeight), alignment: .center)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .accessibilityElement(children: .ignore).accessibilityIdentifier("secretary.summary")
            .help(fullDescription).accessibilityLabel(fullDescription)
    }
}

struct SecretaryPanel: View {
    @ObservedObject var model: CompanionModel
    @ObservedObject var secretary: SecretaryModel
    @ObservedObject var navigation: SettingsNavigation
    @State private var now = Date()
    @State private var completedExpanded = false
    private var c: Copybook { model.copy }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if navigation.page != .day { HStack {
                Text(navigation.page.title(c)).font(.system(size: 17, weight: .semibold))
                Text(now.formatted(.dateTime.weekday(.wide).locale(c.locale))).font(.system(size: 12))
                Spacer()
            } }
            if navigation.page == .day { CalendarDayView(secretary: secretary, copy: c) }
            else { ConnectedTodosView(secretary: secretary, reminders: model.reminders, navigation: navigation, copy: c) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
            .onReceive(secretary.$now) { now = $0 }
            .ownedSheet(item: $secretary.editor, onDismiss: { secretary.refresh() }) { mode in
                if mode == .event { ScheduleEventEditor(secretary: secretary, navigation: navigation, copy: c) }
                else { ScheduleEditor(secretary: secretary, mode: mode, copy: c, navigation: navigation) }
            }
    }
    private var day: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(secretary.data.exceptions[secretary.dayKey] == nil ? c.text("每周计划", "Weekly plan") : c.text("今天已单独调整", "Adjusted for today")).font(.system(size: 12))
                Spacer()
                Button { secretary.editor = .week } label: { Image(systemName: "square.and.pencil").frame(width: 24,height: 24) }.buttonStyle(.plain).help(c.text("编辑每周计划", "Edit weekly plan"))
            }
            ScrollView {
                VStack(spacing: 4) {
                    if secretary.blocks.isEmpty { Text(c.text("今天暂无安排", "No schedule today")).padding(.vertical, 40) }
                    ForEach(secretary.data.blocks(on: now)) { block in
                        let active = secretary.data.current(at: now)?.id == block.id
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(active ? ManagementStyle.ink : Color.gray.opacity(0.4)).frame(width: 7, height: 7).padding(.top, 4)
                            Text(block.timeLabel).font(.system(size: 12)).monospacedDigit().frame(width: 96, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(block.title).font(.system(size: 13, weight: active ? .semibold : .regular)).fixedSize(horizontal: false, vertical: true)
                                if active { Text(c.text("进行中 · 还剩 \(block.end - SecretaryData.minute(now)) 分钟", "Now · \(block.end - SecretaryData.minute(now)) min left")).font(.system(size: 12)).foregroundStyle(ManagementStyle.secondary) }
                            }; Spacer(minLength: 0)
                        }.padding(.vertical, 9).padding(.horizontal, 5)
                            .background(active ? ManagementStyle.hover : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .opacity(block.end <= SecretaryData.minute(now) ? 0.55 : 1)
                    }
                }
            }
            HStack {
                Button(c.text("粘贴时间表", "Paste schedule")) { secretary.editor = .paste }
                Spacer(minLength: 0)
                Button(c.text("调整今天", "Edit today")) { secretary.editor = .today }
            }.font(.system(size: 12))
        }
    }
    private var todos: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(c.text("添加待办", "Add a to-do"), text: $navigation.todoTitle).textFieldStyle(.roundedBorder).onSubmit(saveTodo)
                Button(navigation.editingTodo == nil ? c.text("添加", "Add") : c.text("保存", "Save"), action: saveTodo).disabled(navigation.todoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if navigation.editingTodo != nil { Button(c.text("取消", "Cancel")) { cancelTodo() } }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(secretary.data.todos.filter { !$0.completed }) { todoRow($0) }
                    DisclosureGroup(c.text("已完成", "Completed"), isExpanded: $completedExpanded) {
                        ForEach(secretary.data.todos.filter(\.completed)) { todoRow($0) }
                    }
                }
            }
            if secretary.deleted != nil { Button(c.text("撤销删除", "Undo deletion"), action: secretary.undoDelete) }
        }
    }
    private func todoRow(_ item: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Toggle(item.title, isOn: Binding(get: { item.completed }, set: { value in
                    secretary.commit { d in if let i = d.todos.firstIndex(where: { $0.id == item.id }) { d.todos[i].completed = value } }
                })).toggleStyle(.checkbox).strikethrough(item.completed).font(.system(size: 12))
                Spacer(minLength: 0)
                Button {
                    guard confirmTodoChange() else { return }
                    navigation.editingTodo = item.id; navigation.originalTodoTitle = item.title; navigation.todoTitle = item.title
                } label: { Image(systemName: "pencil").frame(width: 20,height: 24) }.buttonStyle(.plain).accessibilityLabel(c.text("编辑待办", "Edit to-do"))
                Button { secretary.delete(item) } label: { Image(systemName: "trash").frame(width: 20,height: 24) }.buttonStyle(.plain).accessibilityLabel(c.text("删除待办", "Delete to-do"))
            }
            Menu {
                Button(c.text("未安排", "Unscheduled")) { link(item, block: nil) }
                ForEach(secretary.blocks) { b in Button(b.timeLabel + " " + b.title) { link(item, block: b) } }
            } label: {
                Text(linkLabel(item)).font(.system(size: 10)).foregroundStyle(ManagementStyle.secondary)
            }.menuStyle(.borderlessButton).fixedSize().padding(.leading, 18)
        }
    }
    private func linkLabel(_ item: TodoItem) -> String {
        guard let date = item.date, let id = item.blockID else { return c.text("安排时间", "Schedule") }
        if date < secretary.dayKey { return c.text("已过去 · ", "Past · ") + date }
        guard let block = secretary.blocks.first(where: { $0.id == id }), date == secretary.dayKey else { return date }
        return (block.end <= SecretaryData.minute(now) ? c.text("已过去 · ", "Past · ") : c.text("今天 ", "Today ")) + ScheduleBlock.time(block.start)
    }
    private func link(_ item: TodoItem, block: ScheduleBlock?) {
        secretary.commit { d in
            if let i = d.todos.firstIndex(where: { $0.id == item.id }) { d.todos[i].blockID = block?.id; d.todos[i].date = block == nil ? nil : secretary.dayKey }
        }
    }
    private func saveTodo() {
        let title = navigation.todoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if secretary.commit({ d in
            if let id = navigation.editingTodo, let i = d.todos.firstIndex(where: { $0.id == id }) { d.todos[i].title = title }
            else { d.todos.append(TodoItem(title: title)) }
        }) { navigation.clearTodoDraft() }
    }
    private func confirmTodoChange() -> Bool {
        guard navigation.hasTodoDraft else { return true }
        let alert = NSAlert(); alert.messageText = c.text("放弃未保存的待办修改？", "Discard unsaved to-do changes?")
        alert.addButton(withTitle: c.text("继续编辑", "Keep editing")); alert.addButton(withTitle: c.text("放弃修改", "Discard changes"))
        return alert.runOwnedModal() == .alertSecondButtonReturn
    }
    private func cancelTodo() { if confirmTodoChange() { navigation.clearTodoDraft() } }
}

struct ScheduleEditor: View {
    @ObservedObject var secretary: SecretaryModel
    let mode: ScheduleEditMode
    let copy: Copybook
    @ObservedObject var navigation: SettingsNavigation = SettingsNavigation()
    @Environment(\.ownedDismiss) private var dismiss
    @State private var text = ""
    @State private var rows: [ScheduleImportRow] = []
    @State private var selectedDays: Set<Int> = []
    @State private var parsingErrors: [String] = []
    @State private var reviewed = false
    @State private var invalidTimes: Set<String> = []
    @State private var initialRows: [ScheduleImportRow] = []
    @State private var initialDays: Set<Int> = []
    @State private var showDiscard = false
    private var dirty: Bool { !text.isEmpty || rows != initialRows || selectedDays != initialDays || !invalidTimes.isEmpty }
    private let days = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode == .today ? copy.text("调整今天", "Edit today") : copy.text("每周时间表", "Weekly schedule")).font(.title3.bold())
            if !reviewed {
                Text(copy.text("每行：工作日 09:00–11:00 开发 App\n支持每天、周末、周一至周五；仅在本机识别。", "One line: 工作日 09:00–11:00 Develop App\nUse 每天 / 周末 / 周一至周五. Parsed locally.")).font(.callout)
                TextEditor(text: $text).frame(height: 170).border(.gray.opacity(0.2))
                ForEach(parsingErrors, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(ManagementStyle.ink) }
                Button(copy.text("识别并核对", "Parse and review")) {
                    let parsed = ScheduleParser.parse(text); parsingErrors = parsed.errors
                    if parsed.errors.isEmpty && !parsed.rows.isEmpty { rows = parsed.rows; selectedDays = Set(rows.flatMap(\.days)); reviewed = true }
                    else if parsed.rows.isEmpty && parsed.errors.isEmpty { parsingErrors = [copy.text("请先粘贴时间表。", "Paste a schedule first.")] }
                }
            } else {
                if mode != .today {
                    Text(copy.text("将替换以下星期的模板，其他星期和单日调整不变：", "Replace selected weekdays only; date overrides remain:")).font(.caption)
                    HStack { ForEach(1...7, id: \.self) { day in Toggle(dayName(day), isOn: Binding(get: { selectedDays.contains(day) }, set: { if $0 { selectedDays.insert(day) } else { selectedDays.remove(day) } })).toggleStyle(.button) } }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach($rows) { $row in
                            VStack(alignment: .leading, spacing: 5) {
                                if mode != .today {
                                    HStack { ForEach(1...7, id: \.self) { day in
                                        Toggle(dayName(day), isOn: Binding(get: { row.days.contains(day) }, set: { if $0 { row.days.insert(day) } else { row.days.remove(day) } })).toggleStyle(.checkbox).font(.caption)
                                    } }
                                }
                                HStack {
                                    timeField(row: $row, end: false); Text("–"); timeField(row: $row, end: true)
                                    TextField(copy.text("事项", "Activity"), text: $row.block.title)
                                    Button { invalidTimes.remove(row.id.uuidString + "s"); invalidTimes.remove(row.id.uuidString + "e"); rows.removeAll { $0.id == row.id } } label: { Image(systemName: "minus.circle") }
                                }
                            }
                        }
                    }
                }.frame(height: 230)
                Button(copy.text("添加时间段", "Add block")) { rows.append(ScheduleImportRow(days: selectedDays.isEmpty ? [1] : selectedDays, block: ScheduleBlock(start: 540, end: 600, title: ""))) }
                if !invalidTimes.isEmpty { Label(copy.text("时间格式应为 HH:mm，结束可为 24:00。", "Use HH:mm; end may be 24:00."), systemImage: "exclamationmark.triangle").foregroundStyle(ManagementStyle.ink).font(.caption) }
            }
            if !secretary.error.isEmpty { Label(secretary.error, systemImage: "exclamationmark.triangle").foregroundStyle(ManagementStyle.ink).font(.caption) }
            HStack {
                Button(copy.text("取消", "Cancel")) { if dirty { showDiscard = true } else { dismiss() } }.keyboardShortcut(.cancelAction)
                if reviewed && mode == .paste { Button(copy.text("返回文本", "Back to text")) { reviewed = false; invalidTimes.removeAll() } }
                if mode == .today { Button(copy.text("恢复每周模板", "Restore weekly plan")) { secretary.restoreToday(); if secretary.error.isEmpty { dismiss() } } }
                Spacer()
                if reviewed {
                    Button(copy.text("确认保存", "Confirm save")) { if secretary.saveRows(rows, days: selectedDays, today: mode == .today) { dismiss() } }
                        .disabled(!invalidTimes.isEmpty || (mode != .today && selectedDays.isEmpty))
                }
            }
        }.padding(20).frame(width: 600).interactiveDismissDisabled()
        .ownedAlert(copy.text("放弃未保存的日程修改？", "Discard unsaved schedule changes?"), isPresented: $showDiscard) {
            Button(copy.text("继续编辑", "Keep editing"), role: .cancel) { navigation.closeAfterEditor = false }
            Button(copy.text("放弃修改", "Discard changes"), role: .destructive) { dismiss() }
        }.onChange(of: navigation.closeEditorRequest) { _, _ in
            if dirty { showDiscard = true } else { dismiss() }
        }.onAppear {
            if mode == .today { rows = secretary.blocks.map { ScheduleImportRow(days: [], block: $0) }; reviewed = true }
            if mode == .week {
                for day in secretary.data.week.keys.sorted() {
                    for block in secretary.data.week[day] ?? [] {
                        if let i = rows.firstIndex(where: { $0.block == block }) { rows[i].days.insert(day) }
                        else { rows.append(ScheduleImportRow(days: [day], block: block)) }
                    }
                }
                selectedDays = Set(secretary.data.week.keys); reviewed = true
            }
            initialRows = rows; initialDays = selectedDays
        }
    }
    private func dayName(_ day: Int) -> String { copy.text(days[day-1], ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"][day-1]) }
    private func timeField(row: Binding<ScheduleImportRow>, end: Bool) -> some View {
        ScheduleTimeField(value: Binding(get: { end ? row.wrappedValue.block.end : row.wrappedValue.block.start }, set: {
            if end { row.wrappedValue.block.end = $0 } else { row.wrappedValue.block.start = $0 }
        }), end: end, validity: { valid in
            let key = row.wrappedValue.id.uuidString + (end ? "e" : "s")
            if valid { invalidTimes.remove(key) } else { invalidTimes.insert(key) }
        }).frame(width: 58)
    }
}
private struct ScheduleTimeField: View {
    @Binding var value: Int
    let end: Bool
    let validity: (Bool) -> Void
    @State private var text = ""
    var body: some View {
        TextField("HH:mm", text: $text).font(.system(.caption)).monospacedDigit()
            .onAppear { text = ScheduleBlock.time(value) }
            .onChange(of: text) { _, new in
                if let minute = ScheduleParser.minute(new, end: end) { value = minute; validity(true) } else { validity(false) }
            }
    }
}
