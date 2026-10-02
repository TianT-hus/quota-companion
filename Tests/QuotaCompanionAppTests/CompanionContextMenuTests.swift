import AppKit
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor
struct CompanionContextMenuTests {
    @Test func nativeActionsAndBalancedTracking() async throws {
        _ = NSApplication.shared
        let suite = "context-menu-test-\(UUID())"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let model = CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
        model.language = .zhHans
        let controller = CompanionContextMenu(model: model)
        let menu = controller.prepare()
        #expect(menu.items.map(\.title) == ["今日安排", "", "刷新额度", "设置"])
        #expect(menu.items[1].isSeparatorItem)
        #expect(model.secretary.page == .summary && model.interaction.holds == 0)
        var closed = 0, opened = 0
        controller.willOpen = { opened += 1 }
        controller.didClose = { closed += 1 }
        for _ in 0..<100 {
            controller.menuWillOpen(menu); controller.menuWillOpen(menu)
            #expect(model.interaction.holds == 1)
            controller.menuDidClose(menu); controller.menuDidClose(menu)
            #expect(model.interaction.holds == 0)
        }
        #expect(closed == 100 && opened == 100)
        model.isConnecting = true
        #expect(!controller.prepare().items[2].isEnabled)
        #expect(menu.items[2].title == "正在刷新…")
        model.isConnecting = false; model.language = .english
        #expect(controller.prepare().items.map(\.title) == ["Today's schedule", "", "Refresh quota", "Settings"])
        let day = menu.items[0]
        #expect(NSApp.sendAction(try #require(day.action), to: day.target, from: day))
        try await Task.sleep(for: .milliseconds(20))
        #expect(model.secretary.page == .summary && !model.isExpanded)
        model.collapse()
        #expect(model.secretary.page == .summary)
        model.snapshot = .demo(); model.snapshot.state = .stale
        #expect(CompanionContextMenu.statusDescription(model, now: .now).contains("Offline"))
        model.snapshot = .unavailable()
        #expect(CompanionContextMenu.statusDescription(model, now: .now).contains("No quota data"))
    }
}
