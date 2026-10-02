import AppKit
import SwiftUI
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor struct ReminderNativeTests {
    @Test func nativeReminderScreenshots() async throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_REMINDER_PREVIEW"] else { return }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = FakeReminderStore()
        provider.items = [
            .init(id: "r1", listID: "work", title: "示例：检查发布清单", completed: false, due: DateComponents(year: 2026, month: 9, day: 25, hour: 10, minute: 0)),
            .init(id: "r2", listID: "work", title: "示例：准备会议资料", completed: false),
            .init(id: "r3", listID: "personal", title: "示例：买咖啡豆", completed: false)
        ]
        let reminders = RemindersModel(directory: root, provider: provider)
        await reminders.setEnabled(true)
        await reminders.select("work", selected: true); await reminders.select("personal", selected: true)
        let secretary = SecretaryModel(directory: root)
        #expect(secretary.commit { $0.todos = [TodoItem(title: "示例：仅保存在本机的草稿")] })
        let copy = Copybook(language: .zhHans)
        let nav = SettingsNavigation()
        let todos = VStack(alignment: .leading, spacing: 16) {
            Text("待办").font(.system(size: 17, weight: .semibold))
            ConnectedTodosView(secretary: secretary, reminders: reminders, navigation: nav, copy: copy)
        }.padding(24).frame(width: 610, height: 620).background(ManagementStyle.background).foregroundStyle(ManagementStyle.ink).environment(\.colorScheme, .light)
        try await render(todos, output: output.appendingPathComponent("todos-native-simulated.png"))
        let settings = VStack(alignment: .leading, spacing: 16) {
            Text("苹果提醒事项").font(.system(size: 17, weight: .semibold))
            ReminderSettings(reminders: reminders, copy: copy)
            Spacer()
        }.padding(24).frame(width: 610, height: 380).background(ManagementStyle.background).foregroundStyle(ManagementStyle.ink).environment(\.colorScheme, .light)
        try await render(settings, output: output.appendingPathComponent("settings-native-simulated.png"))
        secretary.editEvent(on: Date(), minute: 750)
        try await render(ScheduleEventEditor(secretary: secretary, navigation: nav, copy: copy), output: output.appendingPathComponent("time-input-native.png"))
        reminders.stop()
    }
    private func render<V: View>(_ view: V, output: URL) async throws {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(250))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: output)
        window.close()
    }
}
