import AppKit
import SwiftUI
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor
struct Calendar226Tests {
    @Test func filteringCannotRemoveCurrentOrConflict() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = SecretaryModel(directory: root)
        let date = SecretaryData.date("2026-09-28")!
        let category = ScheduleCategory(name: "工作", colorHex: "266ED4")
        var block = ScheduleBlock(start: 540, end: 600, title: "Work"); block.categoryID = category.id
        #expect(model.commit { try $0.saveCategory(category); $0.week[1] = [block] })
        model.calendarHiddenCategories = [category.id]
        #expect(model.calendarBlocks(on: date).isEmpty)
        #expect(model.data.current(at: date.addingTimeInterval(550 * 60))?.id == block.id)
        #expect(try model.data.resolving(ScheduleBlock(start: 570,end: 590,title: "Conflict"),on: date).adjustments.count == 1)
        let saved = model.data
        let url = root.appendingPathComponent("secretary-v2.json")
        try FileManager.default.removeItem(at: url); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try model.changeCategory { try $0.deleteCategory(category.id) } }
        #expect(model.data == saved)
    }
    @Test func weekOccurrencesAndStickyGeometry() throws {
        let grid = WeekTimelineView(frame: NSRect(x: 0,y: 0,width: 550,height: 400))
        let dates = ScheduleWeek.dates(containing: SecretaryData.date("2026-09-28")!)
        let block = ScheduleBlock(start: 540,end: 600,title: "Repeated",colorHex: "A8C9F2")
        grid.grid.dates = dates; grid.header.dates = dates
        grid.grid.setBlocks(Array(repeating: [block], count: 7))
        let window = NSWindow(contentRect: grid.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = grid
        defer { window.close() }
        grid.pendingMinute = 540; grid.layoutSubtreeIfNeeded()
        #expect(grid.grid.columnWidth >= 88)
        #expect(grid.grid.occurrences.count == 7)
        #expect(Set(grid.grid.occurrences.map(\.id)).count == 7)
        // The sticky axis must not erase sibling grid/header content during native drawing.
        grid.displayIfNeeded()
        let bitmap = try #require(grid.bitmapImageRepForCachingDisplay(in: grid.bounds))
        grid.cacheDisplay(in: grid.bounds, to: bitmap)
        var coloredSamples = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                if let color = bitmap.colorAt(x: x,y: y)?.usingColorSpace(.sRGB), color.blueComponent > color.redComponent + 0.08, color.redComponent > 0.4 { coloredSamples += 1 }
            }
        }
        #expect(coloredSamples > 500)
        var opened: Date?
        grid.grid.onOpen = { date, _, _ in opened = date }
        let fourth = grid.grid.occurrences[3]
        let button = try #require(grid.grid.subviews.compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == fourth.id })
        button.performClick(nil); #expect(opened == dates[3])
        grid.scroll.contentView.scroll(to: NSPoint(x: 80, y: 600)); grid.scroll.reflectScrolledClipView(grid.scroll.contentView)
        #expect(grid.header.offset == grid.scroll.contentView.bounds.minX)
        #expect(grid.axis.offset == grid.scroll.contentView.bounds.minY)
        #expect(grid.axis.frame.minX == 0 && grid.header.frame.minY == 0)
    }
    @Test func nativePreviewArtifacts() async throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_CALENDAR_0226_PREVIEW"] else { return }
        _ = NSApplication.shared
        let out = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let suite = "calendar226-\(UUID())", root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let model = CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
        model.language = .zhHans
        let date = SecretaryData.date("2026-09-28")!, category = ScheduleCategory(name: "工作", colorHex: "A8C9F2")
        var block = ScheduleBlock(start: 540, end: 660,title: "示例：整理本周工作资料并完成发布检查"); block.categoryID = category.id
        #expect(model.secretary.commit { data in
            data.reminders = false; try data.saveCategory(category)
            for day in 1...7 { data.week[day] = [block, ScheduleBlock(start: 780,end: 840,title: "示例：阅读与休息",colorHex: "E5D8EE")] }
        })
        model.secretary.calendarPosition.browse(date)
        let controller = SettingsWindowController(model: model)
        defer { model.secretary.editor = nil; controller.window?.close() }
        controller.show(page: .day, activate: false)
        let window = try #require(controller.window)
        for language in [AppLanguage.zhHans, .english] {
            model.language = language
            for width in [780.0, 1100.0] {
                window.setContentSize(NSSize(width: width,height: 620))
                try await Task.sleep(for: .milliseconds(200))
                try capture(window.contentView!.superview ?? window.contentView!, to: out.appendingPathComponent("\(language.rawValue)-day-\(Int(width)).png"))
            }
        }
        model.language = .zhHans
        model.snapshot = .demo()
        for scale in [1.0, 1.9, 2.5] {
            for count in [1, 2] {
                let effective = max(2,scale)
                let view = NSHostingView(rootView: CompanionRootView(model: model, previewDate: date.addingTimeInterval(600 * 60), sampleQuotaCount: nil, sampleScale: scale))
                model.companionSize = CompanionSize(sliderPercent: (scale - 1) / 1.5 * 100)
                model.snapshot.windows = count == 1 ? Array(QuotaSnapshot.demo().windows.prefix(1)) : QuotaSnapshot.demo().windows
                model.detailDirection = .left
                let win = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 150 * effective,height: 80 * effective), styleMask: [.borderless], backing: .buffered, defer: false)
                win.isReleasedWhenClosed = false; win.contentView = view; win.orderFront(nil)
                try await Task.sleep(for: .milliseconds(150))
                try capture(view, to: out.appendingPathComponent("detail-\(scale)-\(count).png")); win.close()
            }
        }
    }
    private func capture(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        func inspect(_ node: NSView) {
            if let week = node as? WeekTimelineView {
                print("week geometry", week.frame, "scroll", week.scroll.frame, "grid", week.grid.frame, "clip", week.scroll.contentView.bounds, "header", week.header.frame, "dates", week.grid.dates.count, "items", week.grid.occurrences.count)
                #expect(week.grid.dates.count == 7 && week.grid.frame.width >= 616)
                #expect(week.scroll.frame.width > 0 && week.header.frame.width > 0)
            }
            node.subviews.forEach(inspect)
        }
        inspect(view)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}
