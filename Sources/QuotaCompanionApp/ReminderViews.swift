import AppKit
import QuotaCore
import SwiftUI

@MainActor enum ReminderDialogs {
    static func confirm(_ message: String, copy: Copybook, action: String? = nil, parent: NSWindow? = nil) async -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: copy.text("取消", "Cancel"))
        alert.addButton(withTitle: action ?? copy.text("继续", "Continue"))
        return alert.runOwnedModal(parent: parent) == .alertSecondButtonReturn
    }
}

struct ReminderErrorPresenter: View {
    @ObservedObject var reminders: RemindersModel
    let copy: Copybook
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .ownedAlert(copy.text("提醒事项操作未完成", "Reminders operation failed"), isPresented: Binding(get: { !reminders.error.isEmpty }, set: { if !$0 { reminders.error = "" } })) {
                Button(copy.text("确定", "OK")) { reminders.error = "" }
            } message: { Text(reminders.error) }
    }
}

struct ReminderSettings: View {
    @ObservedObject var reminders: RemindersModel
    let copy: Copybook
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsToggle(copy.text("联动苹果提醒事项", "Connect Apple Reminders"), isOn: Binding(get: { reminders.enabled }, set: { enabled in
                Task {
                    if enabled {
                        let confirmed = await ReminderDialogs.confirm(copy.text("启用后，朝夕可读取和修改你选择的提醒事项清单。系统将请求提醒事项访问权限；清单内容可能由所属账户同步到其他设备。现有本地待办不会自动上传。", "Allow Zhaoxi to read and edit selected Reminders lists? macOS will request access. Your account may sync these lists to other devices. Local to-dos are not uploaded automatically."), copy: copy, action: copy.text("启用并授权", "Enable and authorize"))
                        guard confirmed else { return }
                    }
                    await reminders.setEnabled(enabled)
                }
            })).toggleStyle(.switch).disabled(reminders.busy).accessibilityIdentifier("reminders.enable")
            SettingsReveal(expanded: reminders.enabled, trigger: copy.text("联动苹果提醒事项", "Connect Apple Reminders"), spacing: 10) {
                HStack {
                    Text(copy.text("联动清单", "Connected lists"))
                    Spacer()
                    Button(copy.text("刷新", "Refresh")) { Task { await reminders.refresh(userInitiated: true) } }.disabled(reminders.busy)
                }
                ForEach(reminders.state.lists) { list in
                    Toggle(isOn: Binding(get: { reminders.state.selected.contains(list.id) }, set: { value in Task { await reminders.select(list.id, selected: value) } })) {
                        HStack {
                            Text(list.title)
                            Spacer()
                            Text(list.account).foregroundStyle(ManagementStyle.secondary)
                            if !list.writable { Image(systemName: "lock").accessibilityLabel(copy.text("只读", "Read-only")) }
                        }
                    }.toggleStyle(.checkbox).disabled(reminders.busy)
                }
                SettingsPicker(copy.text("默认新增清单", "Default list"), selection: Binding(get: { reminders.state.defaultList ?? "" }, set: { reminders.setDefault($0.isEmpty ? nil : $0) }), options: listChoices).disabled(reminders.busy)
            }
        }.task { await reminders.refresh() }
    }
    private var listChoices: [SettingsChoice<String>] {
        var result = [SettingsChoice("", copy.text("本地", "Local"))]
        result += reminders.writableLists.map { SettingsChoice($0.id, $0.title) }
        if let saved = reminders.state.defaultList, !result.contains(where: { $0.value == saved }) {
            result.append(SettingsChoice(saved, copy.text("原清单暂不可用", "Saved list unavailable")))
        }
        return result
    }
}

struct ConnectedTodosView: View {
    @ObservedObject var secretary: SecretaryModel
    @ObservedObject var reminders: RemindersModel
    @ObservedObject var navigation: SettingsNavigation
    let copy: Copybook
    @State private var source = ""
    @State private var completedExpanded = false
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var transferList = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if navigation.editingTodo == nil && navigation.editingReminder == nil {
                    Picker(copy.text("新增到", "Add to"), selection: $source) {
                        Text(copy.text("本地", "Local")).tag("")
                        ForEach(reminders.writableLists) { Text($0.title).tag($0.id) }
                    }.labelsHidden().frame(maxWidth: 145)
                }
                TextField(copy.text("添加待办", "Add a to-do"), text: $navigation.todoTitle).textFieldStyle(.roundedBorder).onSubmit { save() }
                Button(navigation.editingTodo == nil && navigation.editingReminder == nil ? copy.text("添加", "Add") : copy.text("保存", "Save"), action: save)
                    .disabled(navigation.todoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if navigation.editingTodo != nil || navigation.editingReminder != nil {
                    Button(copy.text("取消", "Cancel")) { if discardDraft() { navigation.clearTodoDraft() } }
                }
            }.disabled(reminders.busy)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(copy.text("本地", "Local")).fontWeight(.semibold)
                        Spacer()
                        if !secretary.data.todos.isEmpty && !reminders.writableLists.isEmpty {
                            Button(selecting ? copy.text("取消选择", "Cancel selection") : copy.text("转入提醒事项", "Move to Reminders")) {
                                guard discardDraft() else { return }
                                navigation.clearTodoDraft()
                                selecting.toggle(); selected = []; transferList = reminders.state.defaultList ?? reminders.writableLists.first?.id ?? ""
                            }.disabled(reminders.busy)
                        }
                    }
                    ForEach(secretary.data.todos.filter { !$0.completed }) { localRow($0) }
                    ForEach(reminders.selectedLists) { list in
                        Divider()
                        HStack {
                            Text(list.title).fontWeight(.semibold)
                            Spacer()
                            if !reminders.usable || !reminders.availableLists.contains(where: { $0.id == list.id }) {
                                Image(systemName: "icloud.slash").help(copy.text("暂不可用 · 显示缓存", "Unavailable · cached data"))
                            }
                        }
                        ForEach(reminders.visibleItems.filter { $0.listID == list.id && !$0.completed }) { remoteRow($0) }
                    }
                    DisclosureGroup(copy.text("已完成", "Completed"), isExpanded: $completedExpanded) {
                        ForEach(secretary.data.todos.filter(\.completed)) { localRow($0) }
                        ForEach(reminders.visibleItems.filter(\.completed)) { remoteRow($0) }
                    }
                }.padding(.vertical, 4)
            }
            if selecting {
                HStack {
                    Picker(copy.text("转入", "Move to"), selection: $transferList) {
                        if !reminders.writableLists.contains(where: { $0.id == transferList }) {
                            Text(copy.text("请选择可写清单", "Select a writable list")).tag(transferList)
                        }
                        ForEach(reminders.writableLists) { Text($0.title).tag($0.id) }
                    }
                    Button(copy.text("转入所选 \(selected.count) 项", "Move \(selected.count) items")) { transfer() }
                        .disabled(selected.isEmpty || !reminders.canWrite(transferList))
                }.disabled(reminders.busy)
            }
            if secretary.deleted != nil { Button(copy.text("撤销删除", "Undo deletion"), action: secretary.undoDelete) }
        }
        .task {
            reminders.start(); await reminders.refresh()
            source = reminders.state.defaultList.flatMap { id in reminders.canWrite(id) ? id : nil } ?? ""
        }
        .onChange(of: reminders.writableLists) { _, lists in
            if !lists.contains(where: { $0.id == source }) { source = "" }
        }
    }
    private func localRow(_ item: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top) {
                if selecting {
                    Toggle(copy.text("选择", "Select"), isOn: Binding(get: { selected.contains(item.id) }, set: { if $0 { selected.insert(item.id) } else { selected.remove(item.id) } })).labelsHidden()
                }
                Toggle(item.title, isOn: Binding(get: { item.completed }, set: { value in
                    secretary.commit { data in if let i = data.todos.firstIndex(where: { $0.id == item.id }) { data.todos[i].completed = value } }
                })).toggleStyle(.checkbox).strikethrough(item.completed)
                Spacer(minLength: 0)
                Button { if discardDraft() { navigation.clearTodoDraft(); navigation.editingTodo = item.id; navigation.originalTodoTitle = item.title; navigation.todoTitle = item.title } } label: { Image(systemName: "pencil") }.accessibilityLabel(copy.text("编辑待办", "Edit to-do"))
                Button { secretary.delete(item) } label: { Image(systemName: "trash") }.accessibilityLabel(copy.text("删除待办", "Delete to-do"))
            }
            association(date: item.date, block: item.blockID) { block in
                secretary.commit { data in if let i = data.todos.firstIndex(where: { $0.id == item.id }) { data.todos[i].date = block == nil ? nil : secretary.dayKey; data.todos[i].blockID = block?.id } }
            }
        }.font(.system(size: 12)).buttonStyle(.plain).disabled(reminders.busy)
    }
    private func remoteRow(_ item: ReminderValue) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top) {
                Toggle(item.title, isOn: Binding(get: { item.completed }, set: { value in
                    Task { _ = await reminders.mutate(item, change: .completed(value), confirm: confirmConflict) }
                })).toggleStyle(.checkbox).strikethrough(item.completed).disabled(!reminders.canWrite(item.listID))
                Spacer(minLength: 0)
                Button {
                    if discardDraft() { navigation.clearTodoDraft(); navigation.editingReminder = item; navigation.originalTodoTitle = item.title; navigation.todoTitle = item.title }
                } label: { Image(systemName: "pencil") }.accessibilityLabel(copy.text("编辑提醒事项", "Edit reminder")).disabled(!reminders.canWrite(item.listID))
                Button {
                    Task {
                        guard await ReminderDialogs.confirm(copy.text("删除“\(item.title)”？这也会从苹果提醒事项及其同步设备中删除，不提供朝夕内撤销。", "Delete “\(item.title)” from Apple Reminders and synced devices? This cannot be undone in Zhaoxi."), copy: copy, action: copy.text("删除", "Delete")) else { return }
                        _ = await reminders.mutate(item, change: .delete, confirm: confirmConflict)
                    }
                } label: { Image(systemName: "trash") }.accessibilityLabel(copy.text("删除提醒事项", "Delete reminder")).disabled(!reminders.canWrite(item.listID))
            }
            if let due = item.due, let date = (due.calendar ?? Calendar.current).date(from: due) {
                Text(date.formatted(due.hour == nil ? .dateTime.year().month().day().locale(copy.locale) : .dateTime.year().month().day().hour().minute().locale(copy.locale)))
                    .font(.system(size: 10)).foregroundStyle(ManagementStyle.secondary)
            }
            let link = reminders.link(for: item)
            association(date: link?.date, block: link?.blockID) { block in
                reminders.setLink(item, link: block.map { .init(date: secretary.dayKey, blockID: $0.id) })
            }
        }.font(.system(size: 12)).buttonStyle(.plain).disabled(reminders.busy)
    }
    private func association(date: String?, block: UUID?, set: @escaping (ScheduleBlock?) -> Void) -> some View {
        Menu {
            Button(copy.text("未安排", "Unscheduled")) { set(nil) }
            ForEach(secretary.blocks) { item in Button(item.timeLabel + " " + item.title) { set(item) } }
        } label: {
            if let date, let block {
                let item = secretary.data.blocks(on: SecretaryData.date(date) ?? .now).first { $0.id == block }
                Text(date + (item.map { " " + $0.timeLabel } ?? ""))
            } else { Text(copy.text("安排时间", "Schedule")) }
        }.menuStyle(.borderlessButton).font(.system(size: 10)).fixedSize().padding(.leading, 18)
    }
    private func discardDraft() -> Bool {
        guard navigation.hasTodoDraft else { return true }
        let alert = NSAlert(); alert.messageText = copy.text("放弃未保存的待办修改？", "Discard unsaved to-do changes?")
        alert.addButton(withTitle: copy.text("继续编辑", "Keep editing")); alert.addButton(withTitle: copy.text("放弃修改", "Discard changes"))
        return alert.runOwnedModal() == .alertSecondButtonReturn
    }
    private func confirmConflict(_ message: String) async -> Bool { await ReminderDialogs.confirm(message, copy: copy, action: copy.text("覆盖并保存", "Apply change")) }
    private func save() {
        guard !reminders.busy else { return }
        let title = navigation.todoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if let item = navigation.editingReminder {
            Task { if await reminders.mutate(item, change: .title(title), confirm: confirmConflict) { navigation.clearTodoDraft() } }
        } else if navigation.editingTodo == nil && !source.isEmpty {
            Task { if await reminders.create(title, list: source) { navigation.clearTodoDraft() } }
        } else if secretary.commit({ data in
            if let id = navigation.editingTodo, let i = data.todos.firstIndex(where: { $0.id == id }) { data.todos[i].title = title }
            else { data.todos.append(TodoItem(title: title)) }
        }) { navigation.clearTodoDraft() }
    }
    private func transfer() {
        guard discardDraft() else { return }
        navigation.clearTodoDraft()
        let items = secretary.data.todos.filter { selected.contains($0.id) }
        let list = transferList
        Task {
            guard await ReminderDialogs.confirm(copy.text("将所选 \(items.count) 项转入苹果提醒事项？成功转入的项目不再作为独立本地待办显示，日程关联会保留。", "Move \(items.count) selected items to Apple Reminders? Successful items leave Local; schedule links are retained."), copy: copy, action: copy.text("转入", "Move")) else { return }
            await reminders.transfer(items, to: list, secretary: secretary)
            selected = selected.intersection(Set(secretary.data.todos.map(\.id)))
            if selected.isEmpty { selecting = false }
        }
    }
}
