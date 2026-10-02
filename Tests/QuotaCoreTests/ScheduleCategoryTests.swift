import Foundation
import Testing
@testable import QuotaCore

struct ScheduleCategoryTests {
    @Test func migrationAndCorruptionProtection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SecretaryStore(directory: root)
        var old = SecretaryData(); old.week[1] = [ScheduleBlock(start: 540, end: 600, title: "Old", colorHex: "ABCDEF")]
        let bytes = try JSONEncoder().encode(old); try bytes.write(to: store.legacyURL)
        #expect(try store.load() == old)
        var migrated = old
        try migrated.saveCategory(.init(name: "工作", colorHex: "266ED4"))
        try store.save(migrated)
        #expect(try store.load() == migrated)
        #expect(try Data(contentsOf: store.legacyURL) == bytes)
        #expect(try Data(contentsOf: root.appendingPathComponent("before-schedule-0226/secretary-v1.json")) == bytes)
        try Data("broken".utf8).write(to: store.url)
        #expect(throws: (any Error).self) { try store.load() }
        #expect(throws: (any Error).self) { try store.save(old) }
        #expect(try String(contentsOf: store.url, encoding: .utf8) == "broken")
    }
    @Test func deletionPreservesOccurrencesAndColor() throws {
        var data = SecretaryData()
        let category = ScheduleCategory(name: "工作", colorHex: "266ED4")
        try data.saveCategory(category)
        var block = ScheduleBlock(start: 540, end: 720, title: "Work"); block.categoryID = category.id
        data.week[1] = [block]; data.exceptions["2026-09-29"] = [block]
        var edit = ScheduleDayEdits(); edit.upserts = [block]; data.dayEdits["2026-09-30"] = edit
        let date = SecretaryData.date("2026-09-28")!
        var todo = TodoItem(title: "Linked"); todo.date = "2026-09-28"; todo.blockID = block.id; data.todos = [todo]
        let reminderKey = data.reminderKey(block, date: date)
        try data.saveCategory(.init(id: category.id, name: "事业", colorHex: "55AA44"))
        #expect(data.colorHex(for: block) == "55AA44")
        let split = try data.resolving(ScheduleBlock(start: 600, end: 660, title: "Break"), on: date).result
        #expect(split.blocks(on: date).filter { $0.title == "Work" }.allSatisfy { $0.categoryID == category.id })
        try data.deleteCategory(category.id)
        #expect(data.categories.isEmpty)
        for day in ["2026-09-28", "2026-09-29", "2026-09-30"] {
            let item = try #require(data.blocks(on: SecretaryData.date(day)!).first)
            #expect(item.categoryID == nil && item.colorHex == "55AA44" && item.id == block.id)
        }
        #expect(data.todos == [todo]); #expect(data.reminderKey(block, date: date) == reminderKey)
    }
    @Test func invalidCategoryIsTransactional() throws {
        var data = SecretaryData(); try data.saveCategory(.init(name: " Work ", colorHex: "266ED4"))
        let saved = data
        for name in [" ", String(repeating: "字", count: 31), "work"] {
            #expect(throws: (any Error).self) { try data.saveCategory(.init(name: name, colorHex: "266ED4")) }
            #expect(data == saved)
        }
        try data.saveCategory(.init(name: "🏋️健康", colorHex: "AAEE33"))
        #expect(data.categories.count == 2)
    }
    @Test func weekUsesCalendarDaysAcrossBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for key in ["2026-01-01", "2026-03-08", "2026-11-01", "2026-09-27"] {
            let date = SecretaryData.date(key, calendar: calendar)!
            let week = ScheduleWeek.dates(containing: date, calendar: calendar)
            #expect(week.count == 7 && Set(week).count == 7)
            #expect(calendar.component(.weekday, from: week[0]) == 2)
            #expect(calendar.component(.weekday, from: week[6]) == 1)
            #expect(week.contains(date))
        }
    }
}
