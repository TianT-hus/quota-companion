import AppKit
import SwiftUI
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor
struct SecretaryNativeTests {
    @Test func persistenceEditingUndoAndReminders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("secretary-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let m = SecretaryModel(directory: root)
        let now = Date(), minute = SecretaryData.minute(now)
        let item = ScheduleBlock(start: max(0, minute-1), end: min(1440,minute+10), title: "Example")
        #expect(m.commit { $0.exceptions[m.dayKey] = [item]; $0.todos = [TodoItem(title: "Example")] })
        let task = try #require(m.data.todos.first)
        m.delete(task); #expect(m.data.todos.isEmpty); m.undoDelete(); #expect(m.data.todos.count == 1)
        let currentKey = m.dayKey
        m.editor = .today; m.setVisible(true); m.refresh(at: now)
        #expect(m.reminder == nil && m.data.delivered.isEmpty)
        m.editor = nil; m.refresh(at: now); #expect(m.reminder?.id == item.id)
        m.dismissReminder(); m.refresh(at: now); #expect(m.reminder == nil)
        let reloaded = SecretaryModel(directory: root)
        reloaded.setVisible(true); reloaded.refresh(at: now)
        #expect(reloaded.reminder == nil && reloaded.data.todos == m.data.todos)
        #expect(reloaded.data.exceptions[currentKey] == [item])
        #expect(!m.saveRows([ScheduleImportRow(days: [1],block: ScheduleBlock(start: 100,end: 10,title: "Bad"))],days: [1],today: false))
        #expect(m.data.exceptions[currentKey] == [item])
        m.stop(); reloaded.stop()
    }
    @Test func schedulePanelStateAndGeometry() async throws {
        _ = NSApplication.shared
        let suite = "secretary-panel-\(UUID())", root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let model = CompanionModel(defaults: defaults,store: SnapshotStore(directory: root))
        let panels = PanelController(model: model,positionDefaults: defaults,monitorsSystem: false)
        panels.show(); defer { panels.close() }
        let frame = panels.nativeWindow.frame
        var maximum = 0.0
        for _ in 0..<100 {
            model.showExpanded(); #expect(model.secretary.page == .summary)
            model.showDay()
            model.updateInteraction { $0.pointer(pet: false,region: false,now: 0); $0.tick(now: 100) }
            #expect(!model.isExpanded && model.secretary.page == .summary)
            #expect(model.detailBaseSize == CompactHoverMetrics.size)
            #expect(panels.nativeWindow.frame == frame)
            maximum = max(maximum, panels.layoutMilliseconds)
            model.collapse(); #expect(!model.isExpanded && model.secretary.page == .summary)
        }
        #expect(maximum < 300)
        print("secretary 100 programmatic cycles maxInternalLayoutMs=\(maximum); not pointer QA")
        for scale in [1.0,1.5,2.0] {
            let screen = CGRect(x: 0,y: 0,width: 1800,height: 1200)
            for p in [CGPoint(x: 0,y: 500),CGPoint(x: 1728,y: 500),CGPoint(x: 850,y: 0),CGPoint(x: 850,y: 1100)] {
                let l = PetPanelLayout(pet: CGRect(origin: p,size: CGSize(width: 72,height: 80)),windowCount: 2,screen: screen,scale: scale,detailSize: CGSize(width: 340,height: 420))
                #expect(screen.contains(l.detail) && l.pet.origin == p)
            }
        }
        try await Task.sleep(for: .milliseconds(350)); #expect(!panels.detailWindow.isVisible)
    }
    @Test func nativePreviews() async throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_SECRETARY_PREVIEW"] else { return }
        _ = NSApplication.shared
        let out = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: out,withIntermediateDirectories: true)
        let suite = "secretary-preview-\(UUID())", root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let model = CompanionModel(defaults: defaults,store: SnapshotStore(directory: root))
        model.language = .zhHans; model.chestTextStyle = .goldInk
        if let character = ProcessInfo.processInfo.environment["QUOTA_APPROVED_CHARACTER"] {
            for _ in 0..<200 { if !model.characterLibrary.isBusy { break }; try await Task.sleep(for: .milliseconds(10)) }
            model.characterLibrary.importPackage(URL(fileURLWithPath: character),copy: model.copy)
            for _ in 0..<200 { if !model.characterLibrary.isBusy { break }; try await Task.sleep(for: .milliseconds(10)) }
        }
        let date = Calendar.current.date(from: DateComponents(year: 2026,month: 9,day: 16,hour: 15,minute: 15))!
        let parsed = ScheduleParser.parse("工作日 09:00–11:00 开发 App\n工作日 11:00–12:00 处理事务\n工作日 12:00–14:00 午餐与休息\n工作日 14:00–16:00 开发 App\n工作日 16:00–17:00 处理事务\n工作日 17:00–18:00 整理与收尾")
        model.secretary.refresh(at: date)
        #expect(model.secretary.saveRows(parsed.rows,days: Set(1...5),today: false))
        #expect(model.secretary.commit { $0.todos = [TodoItem(title: "整理发布说明"),TodoItem(title: "确认手机端设计"),TodoItem(title: "回复合作消息")] })
        func demo() -> QuotaSnapshot { QuotaSnapshot(state: .live, source: .demo, observedAt: date, windows: QuotaSnapshot.demo().windows) }
        model.snapshot = demo()
        for name in ["pet-only","summary-single","summary-double","day","todos","empty"] {
            if name == "day" || name == "todos" {
                let navigation = SettingsNavigation()
                navigation.page = name == "day" ? .day : .todos; navigation.visible = true
                try await render(SettingsView(model: model, navigation: navigation), size: CGSize(width: 780, height: 620), to: out.appendingPathComponent(name+".png"))
                continue
            }
            model.secretary.page = name == "day" ? .day : name == "todos" ? .todos : .summary
            if name == "summary-single" { model.snapshot.windows = Array(model.snapshot.windows.prefix(1)) }
            if name == "summary-double" { model.snapshot = demo() }
            if name == "empty" { _ = model.secretary.commit { $0.week = [:]; $0.exceptions = [:] }; model.snapshot = .unavailable() }
            let size = model.detailBaseSize
            let combined = HStack(spacing: -36) {
                PetRootView(model: model).frame(width: 72,height: 80).zIndex(1)
                if name != "pet-only" { CompanionRootView(model: model,previewDate: date).frame(width: size.width,height: size.height) }
            }.padding(20).background(Color(red: 0.86,green: 0.90,blue: 0.94))
            let dims = CGSize(width: name == "pet-only" ? 112 : size.width+76,height: max(80,size.height)+40)
            try await render(combined,size: dims,to: out.appendingPathComponent(name+".png"))
        }
        model.secretary.page = .day
        _ = model.secretary.saveRows(parsed.rows,days: Set(1...5),today: false)
        try await render(ScheduleEditor(secretary: model.secretary,mode: .week,copy: model.copy).background(Color.white),size: CGSize(width: 640,height: 480),to: out.appendingPathComponent("review.png"))
    }
    private func render<V: View>(_ content: V,size: CGSize,to url: URL) async throws {
        let host = NSHostingView(rootView: content), panel = NSPanel(contentRect: CGRect(origin: CGPoint(x: 100,y: 100),size: size),styleMask: .borderless,backing: .buffered,defer: false)
        host.sizingOptions = []; host.frame = CGRect(origin: .zero,size: size)
        panel.isReleasedWhenClosed = false; panel.contentView = host; panel.orderFrontRegardless()
        defer { panel.close() }
        try await Task.sleep(for: .milliseconds(100)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds,to: bitmap)
        try #require(bitmap.representation(using: .png,properties: [:])).write(to: url)
    }
}
