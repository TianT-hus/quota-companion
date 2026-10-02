import AppKit
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor
struct ManagementWindowTests {
    @Test func sharedRoutesDraftGuardsAndAnimationPause() async throws {
        _ = NSApplication.shared
        let suite = "management-\(UUID())"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let model = CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
        model.language = .zhHans
        let controller = SettingsWindowController(model: model)
        let original = model.secretary.data
        controller.show(page: .day, activate: false)
        let window = try #require(controller.window)
        defer { model.secretary.editor = nil; window.close() }
        #expect(window.title == "今日安排" && !model.isExpanded)
        #expect(window.contentView?.bounds.size == CGSize(width: 780, height: 620))
        for _ in 0..<100 {
            controller.show(activate: false)
            #expect(window.title == "设置" && controller.window === window)
            controller.show(page: .day, activate: false)
            #expect(controller.navigation.page == .day && controller.window === window)
            model.showExpanded(); model.collapse()
            #expect(controller.navigation.page == .day && window.isVisible)
        }
        #expect(model.secretary.data == original)
        controller.navigate(to: .todos)
        controller.navigation.todoTitle = "Unsaved example"
        controller.confirmDiscard = { false }
        controller.navigate(to: .appearance)
        #expect(controller.navigation.page == .todos && controller.navigation.hasTodoDraft)
        #expect(!controller.windowShouldClose(window))
        #expect(model.managementPausesAnimation)
        controller.confirmDiscard = { true }
        controller.navigate(to: .appearance)
        #expect(controller.navigation.page == .appearance && !controller.navigation.hasTodoDraft)
        model.secretary.editor = .week
        controller.show(page: .day, activate: false)
        #expect(controller.navigation.page == .appearance)
        #expect(!controller.windowShouldClose(window) && model.managementPausesAnimation)
        model.secretary.editor = nil
        controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification))
        #expect(model.managementPausesAnimation)
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        #expect(!model.managementPausesAnimation && window.isVisible)
        controller.show(page: .day, activate: false)
        model.language = .english
        #expect(window.title == "Today's schedule")
        window.close(); #expect(!controller.navigation.visible)
        controller.show(activate: false)
        #expect(controller.window === window && window.title == "Settings")
        #expect(model.secretary.data == original)
    }

    @Test func exclusiveLeaseIsReacquiredAfterRelease() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("instance-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        var first: CompanionInstanceLease? = try #require(CompanionInstanceLease.acquire(directory: root))
        #expect(first != nil)
        #expect(CompanionInstanceLease.acquire(directory: root) == nil)
        first = nil
        let recovered = try #require(CompanionInstanceLease.acquire(directory: root))
        withExtendedLifetime(recovered) { #expect(CompanionInstanceLease.acquire(directory: root) == nil) }
    }

    @Test func nativeManagementPreviews() async throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_026_PREVIEW"] else { return }
        let folder = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suite = "management-preview-\(UUID())"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let model = CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
        model.snapshot = .demo()
        #expect(model.secretary.commit {
            $0.reminders = false
            $0.exceptions[SecretaryData.dayKey(.now)] = [
                ScheduleBlock(start: 540, end: 660, title: "示例：开发 App"),
                ScheduleBlock(start: 660, end: 720, title: "示例：处理事务"),
                ScheduleBlock(start: 780, end: 1050, title: "示例：专注工作"),
                ScheduleBlock(start: 1080, end: 1260, title: "示例：阅读与整理")]
            $0.todos = [TodoItem(title: "示例：整理发布说明"), TodoItem(title: "示例：核对下一周计划")]
        })
        let controller = SettingsWindowController(model: model)
        defer { controller.window?.close() }
        for language in [AppLanguage.zhHans, .english] {
            model.language = language
            for page in SettingsPage.allCases {
                controller.show(page: page, activate: false)
                try await Task.sleep(for: .milliseconds(200))
                let view = try #require(controller.window?.contentView)
                view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
                let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("\(language.rawValue)-\(page.rawValue).png"))
            }
        }
    }
}
