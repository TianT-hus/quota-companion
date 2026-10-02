import AppKit
import SwiftUI
import QuotaCore

struct ScheduleCategoryManager: View {
    @ObservedObject var secretary: SecretaryModel
    let copy: Copybook
    @Environment(\.ownedDismiss) private var dismiss
    @State private var editing: ScheduleCategory?
    @State private var removing: ScheduleCategory?
    @State private var confirm = false
    @State private var error = ""
    @State private var showError = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(copy.text("日程分类", "Schedule categories")).font(.system(size: 17, weight: .semibold))
            Text(copy.text("勾选只改变日历显示，不影响提醒。", "Visibility only filters the calendar, not reminders.")).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 12) {
                    HStack {
                        Toggle(copy.text("未分类", "Uncategorized"), isOn: Binding(get: { !secretary.calendarHideUncategorized }, set: { secretary.calendarHideUncategorized = !$0 })).toggleStyle(.checkbox)
                        Spacer()
                    }
                    ForEach(secretary.data.categories) { category in
                        HStack(spacing: 10) {
                            Toggle(category.name, isOn: Binding(get: { !secretary.calendarHiddenCategories.contains(category.id) }, set: {
                                if $0 { secretary.calendarHiddenCategories.remove(category.id) } else { secretary.calendarHiddenCategories.insert(category.id) }
                            })).toggleStyle(.checkbox)
                            Spacer()
                            RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: ScheduleEventPalette.color(category.colorHex))).frame(width: 20, height: 20).accessibilityHidden(true)
                            Button { editing = category } label: { Image(systemName: "pencil") }.accessibilityLabel(copy.text("编辑", "Edit") + " " + category.name)
                            Button { removing = category; confirm = true } label: { Image(systemName: "trash") }.accessibilityLabel(copy.text("删除", "Delete") + " " + category.name)
                        }
                    }
                }.padding(2)
            }.frame(height: min(250, CGFloat(secretary.data.categories.count + 1) * 36))
            if secretary.data.categories.isEmpty {
                Text(copy.text("从常用分类开始，或创建自己的分类。", "Start with a suggestion, or create your own category.")).foregroundStyle(.secondary)
                HStack {
                    suggestion("工作", "Work", "266ED4")
                    suggestion("日常", "Daily", "63A987")
                    suggestion("锻炼", "Exercise", "E39B45")
                    suggestion("休息", "Rest", "AC8AD2")
                }
            }
            HStack {
                Button(copy.text("新建分类", "New category")) { editing = .init(name: "", colorHex: "266ED4") }
                Spacer()
                Button(copy.text("完成", "Done")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 450).font(.system(size: 13)).environment(\.colorScheme, .light)
            .ownedSheet(item: $editing) { category in ScheduleCategoryEditor(secretary: secretary, copy: copy, original: category) }
            .ownedAlert(copy.text("删除分类？", "Delete category?"), isPresented: $confirm) {
                Button(copy.text("取消", "Cancel"), role: .cancel) {}
                Button(copy.text("删除分类", "Delete category"), role: .destructive) {
                    guard let category = removing else { return }
                    do { try secretary.changeCategory { try $0.deleteCategory(category.id) }; secretary.calendarHiddenCategories.remove(category.id) }
                    catch { self.error = error.localizedDescription; showError = true }
                }
            } message: { Text(copy.text("日程不会删除，将转为未分类并保留当前颜色。", "Events will remain, uncategorized, with their current color.")) }
            .ownedAlert(copy.text("无法保存", "Could not save"), isPresented: $showError) { Button(copy.text("确定", "OK")) {} } message: { Text(error) }
    }
    private func suggestion(_ zh: String, _ en: String, _ hex: String) -> some View {
        Button(copy.text(zh, en)) { editing = .init(name: copy.text(zh, en), colorHex: hex) }
    }
}

struct ScheduleCategoryEditor: View {
    @ObservedObject var secretary: SecretaryModel
    let copy: Copybook
    let original: ScheduleCategory
    @Environment(\.ownedDismiss) private var dismiss
    @State private var name: String
    @State private var hex: String
    @State private var colorDraft: ColorEditorDraft?
    @State private var discard = false
    @State private var showError = false
    @State private var error = ""
    init(secretary: SecretaryModel, copy: Copybook, original: ScheduleCategory) {
        self.secretary = secretary; self.copy = copy; self.original = original
        _name = State(initialValue: original.name); _hex = State(initialValue: original.colorHex)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(copy.text("编辑分类", "Edit category")).font(.system(size: 17, weight: .semibold))
            TextField(copy.text("分类名称", "Category name"), text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Text(copy.text("分类颜色", "Category color")); Spacer()
                Button { colorDraft = .init(target: .schedule, hex: "#" + hex) } label: {
                    RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: ScheduleEventPalette.color(hex))).frame(width: 34, height: 28)
                }.buttonStyle(.plain).accessibilityLabel(copy.text("修改分类颜色", "Change category color"))
            }
            HStack {
                Spacer()
                Button(copy.text("取消", "Cancel")) {
                    if name != original.name || hex != original.colorHex { discard = true } else { dismiss() }
                }.keyboardShortcut(.cancelAction)
                Button(copy.text("保存", "Save")) {
                    do { try secretary.changeCategory { try $0.saveCategory(.init(id: original.id, name: name, colorHex: hex)) }; dismiss() }
                    catch { self.error = error.localizedDescription; showError = true }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 360).font(.system(size: 13)).interactiveDismissDisabled()
            .ownedSheet(item: $colorDraft) { draft in
                ColorEditor(copy: copy, draft: draft, onSave: { value in hex = String(value.hex.dropFirst()); colorDraft = nil }, onCancel: { colorDraft = nil })
            }
            .ownedAlert(copy.text("放弃未保存的修改？", "Discard changes?"), isPresented: $discard) {
                Button(copy.text("继续编辑", "Keep editing"), role: .cancel) {}
                Button(copy.text("放弃修改", "Discard"), role: .destructive) { dismiss() }
            }
            .ownedAlert(copy.text("无法保存", "Could not save"), isPresented: $showError) { Button(copy.text("确定", "OK")) {} } message: { Text(error) }
    }
}
