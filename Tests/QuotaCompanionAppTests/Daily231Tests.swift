import AppKit
import QuotaCore
import Testing
@testable import QuotaCompanionApp

@Suite(.serialized) @MainActor struct Daily231Tests {
    @Test func arrowsMoveOneDayAcrossYearAndStopFollowing() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 13)))
        var position = TimelinePosition(date: date)
        position.shiftDay(1, calendar: calendar)
        #expect(calendar.component(.day, from: position.date) == 1)
        #expect(calendar.component(.year, from: position.date) == 2027)
        #expect(!position.following)
        position.shiftDay(-1, calendar: calendar)
        #expect(position.date == date)
        position.resume(date); #expect(position.following)
    }

    @Test func pageOnlyCreatesDailyCanvasAndPreservesSchedule() async throws {
        let name = "daily231-\(UUID())", root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: root) }
        let model = CompanionModel(defaults: defaults, store: SnapshotStore(directory: root))
        let date = try #require(SecretaryData.date("2026-10-02"))
        let category = ScheduleCategory(name: "工作", colorHex: "A8C9F2")
        var event = ScheduleBlock(start: 540, end: 660, title: "示例：整理工作资料")
        event.categoryID = category.id
        #expect(model.secretary.commit { data in
            data.reminders = false
            try data.saveCategory(category)
            for day in 1...7 { data.week[day] = [event] }
        })
        let before = model.secretary.data
        let stored = try Data(contentsOf: root.appendingPathComponent("secretary-v2.json"))
        let controller = SettingsWindowController(model: model)
        defer { controller.window?.close() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for language in [AppLanguage.zhHans, .english] {
            model.language = language
            model.secretary.calendarPosition.browse(date)
            controller.show(page: .day, activate: false)
            try await Task.sleep(for: .milliseconds(180))
            let window = try #require(controller.window), view = try #require(window.contentView)
            let children = descendants(view)
            #expect(children.filter { $0 is CalendarScrollView }.count == 1)
            #expect(!children.contains { $0 is WeekTimelineView || $0 is NSSegmentedControl })
            #expect(model.secretary.calendarPosition.date == date)
            #expect(model.secretary.data == before)
            #expect(try Data(contentsOf: root.appendingPathComponent("secretary-v2.json")) == stored)
            if let path = ProcessInfo.processInfo.environment["QUOTA_DAILY231_PREVIEW"] {
                let folder = URL(fileURLWithPath: path)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let frame = view.superview ?? view
                frame.layoutSubtreeIfNeeded(); frame.displayIfNeeded()
                let bitmap = try #require(frame.bitmapImageRepForCachingDisplay(in: frame.bounds))
                frame.cacheDisplay(in: frame.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("\(language.rawValue)-daily.png"))
            }
            controller.navigate(to: .general); controller.navigate(to: .day)
            #expect(model.secretary.calendarPosition.date == date)
        }
    }
}
