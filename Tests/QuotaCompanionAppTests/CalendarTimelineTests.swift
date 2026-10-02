import AppKit
import SwiftUI
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor
struct CalendarTimelineTests {
    @Test func segmentedTimeValidation() {
        #expect(SegmentedScheduleTime.value("9", "5", end: false) == 545)
        #expect(SegmentedScheduleTime.value("24", "00", end: true) == 1440)
        #expect(SegmentedScheduleTime.value("24", "01", end: true) == nil)
        #expect(SegmentedScheduleTime.value("24", "00", end: false) == nil)
        for invalid in ["", "-1", "1x", "123", " 1"] {
            #expect(SegmentedScheduleTime.value(invalid, "00", end: false) == nil)
        }
        #expect(SegmentedScheduleTime.value("23", "60", end: true) == nil)
    }
    @Test func proposalStalenessAndWriteFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = SecretaryModel(directory: root)
        let event = ScheduleBlock(start: 540,end: 600,title: "Draft")
        let stale = try model.data.resolving(event, on: Date())
        #expect(model.commit { $0.reminders = false })
        #expect(throws: (any Error).self) { try model.commitEvent(stale) }
        let fresh = try model.data.resolving(event, on: Date())
        try model.commitEvent(fresh)
        let before = model.data
        let deletion = try model.data.resolving(event, on: Date(), delete: true)
        try FileManager.default.removeItem(at: root.appendingPathComponent("secretary-v2.json"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("secretary-v2.json"), withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try model.commitEvent(deletion) }
        #expect(model.data == before && model.error.isEmpty)
    }
    @Test func followingMidnightAndManualPause() {
        let midnight = SecretaryData.date("2026-09-25")!
        var state = TimelinePosition(date: midnight.addingTimeInterval(-60))
        state.tick(midnight)
        #expect(state.date == midnight && state.following)
        state.browse(midnight.addingTimeInterval(-86400))
        state.tick(midnight.addingTimeInterval(600))
        #expect(state.date == midnight.addingTimeInterval(-86400) && !state.following)
        state.resume(midnight); #expect(state.following && state.date == midnight)
    }
    @Test func nativeScrollCenterAndShortEvents() throws {
        _ = NSApplication.shared
        let view = CalendarScrollView(frame: NSRect(x: 0, y: 0, width: 530, height: 450))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.close() }
        let tiny = ScheduleBlock(start: 600, end: 601, title: "One minute")
        view.canvas.blocks = [tiny]
        for minute in [0,1,720,1439,1440] {
            view.pendingMinute = minute; view.needsLayout = true; view.layoutSubtreeIfNeeded()
            let line = view.canvas.padding + CGFloat(minute) * 1.2
            #expect(abs(line - view.contentView.bounds.midY) < 1)
        }
        #expect(abs(view.canvas.eventRect(tiny).height - 1.2) < 0.01)
        var manual = false; view.onBrowse = { manual = true }
        view.contentView.scroll(to: NSPoint(x: 0,y: 500))
        #expect(!manual)
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: view)
        #expect(manual)
        let button = try #require(view.canvas.subviews.first as? NSButton)
        #expect(button.accessibilityLabel()?.contains("One minute") == true)
        var selected: UUID?
        view.canvas.onOpen = { block, _ in selected = block?.id }
        button.performClick(nil); #expect(selected == tiny.id)
    }
    @Test func draftAndWriteFailureKeepOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = SecretaryModel(directory: root)
        let a = ScheduleBlock(start: 540,end: 600,title: "Original")
        #expect(model.commit { try $0.change(a, on: Date()) })
        model.editEvent(on: Date(), block: a)
        #expect(model.editor == .event && model.data.blocks(on: Date()).first == a)
        model.editor = nil // Canceling a draft never commits it.
        try FileManager.default.removeItem(at: root.appendingPathComponent("secretary-v2.json"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("secretary-v2.json"), withIntermediateDirectories: true)
        #expect(!model.commit { try $0.change(a, on: Date(), delete: true) })
        #expect(model.data.blocks(on: Date()).first == a && !model.error.isEmpty)
    }
    @Test func nativeCalendarPreviews() async throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_CALENDAR_PREVIEW"] else { return }
        _ = NSApplication.shared
        let out = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let suite = "calendar-preview-\(UUID())"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
        let model = CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
        model.language = .zhHans
        let m = min(1320, max(180, SecretaryData.minute(Date())))
        let items = [ScheduleBlock(start: m-100,end: m-40,title: "示例：整理资料",colorHex: "DDEEDB"),
                     ScheduleBlock(start: m-30,end: m-20,title: "示例：喝水休息"),
                     ScheduleBlock(start: m-10,end: m+80,title: "示例：设计与开发",colorHex: "D8E8FA"),
                     ScheduleBlock(start: m+90,end: m+91,title: "示例：一分钟事项"),
                     ScheduleBlock(start: m+100,end: m+120,title: "示例：阅读",colorHex: "E8DDF5")]
        #expect(model.secretary.commit { $0.reminders = false; for d in 1...7 { $0.week[d] = items } })
        let controller = SettingsWindowController(model: model)
        defer { model.secretary.editor = nil; controller.window?.close() }
        for language in [AppLanguage.zhHans, .english] {
            model.language = language
            controller.show(page: .day, activate: false)
            try await Task.sleep(for: .milliseconds(350))
            try snapshot(try #require(controller.window?.contentView), to: out.appendingPathComponent("\(language.rawValue)-today.png"))
            func findScroll(_ view: NSView) -> CalendarScrollView? {
                if let scroll = view as? CalendarScrollView { return scroll }
                return view.subviews.compactMap(findScroll).first
            }
            let content = try #require(controller.window?.contentView)
            let scroll = try #require(findScroll(content))
            NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, scroll.contentView.bounds.minY - 120)))
            try await Task.sleep(for: .milliseconds(100))
            try snapshot(try #require(controller.window?.contentView), to: out.appendingPathComponent("\(language.rawValue)-paused.png"))
            for weekly in [false, true] {
                model.secretary.editEvent(on: Date(), block: items[2])
                // Render the actual editor component in an isolated native window.
                let editor = ScheduleEventEditor(secretary: model.secretary, navigation: controller.navigation, copy: model.copy, initialWeekly: weekly)
                let host = NSHostingView(rootView: editor)
                let size = host.fittingSize
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = host
                window.orderFront(nil)
                try await Task.sleep(for: .milliseconds(150))
                try snapshot(host, to: out.appendingPathComponent("\(language.rawValue)-editor-\(weekly ? "weekly" : "day").png"))
                window.close(); model.secretary.editor = nil
            }
        }
        let canvas = CalendarScrollView(frame: NSRect(x: 0,y: 0,width: 530,height: 450))
        canvas.canvas.blocks = items; canvas.pendingMinute = items[0].start
        let win = NSWindow(contentRect: canvas.frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false; win.contentView = canvas
        defer { win.close() }
        try snapshot(canvas, to: out.appendingPathComponent("other-date-no-now-line.png"))
    }
    private func snapshot(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}
