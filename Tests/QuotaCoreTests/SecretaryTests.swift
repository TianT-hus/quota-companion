import Foundation
import Testing
@testable import QuotaCore

struct SecretaryTests {
    @Test func parserAndValidation() throws {
        let p = ScheduleParser.parse("工作日 09:00–11:00 开发 App\n周末 11:00-12:00 休息\n周一至周五 23:00–24:00 收尾")
        #expect(p.errors.isEmpty && p.rows.count == 3)
        #expect(p.rows[0].days == Set(1...5))
        #expect(p.rows[1].days == [6,7])
        #expect(p.rows[2].block.end == 1440)
        #expect(ScheduleParser.parse("每天 23:00–01:00 过夜\n周三 随时 工作\n周日 24:00–24:01 无效").errors.count == 3)
        #expect(ScheduleParser.days("星期一至星期三") == [1,2,3])
        let a = ScheduleBlock(start: 60,end: 120,title: "A")
        try ScheduleParser.validate([a, ScheduleBlock(start: 120,end: 180,title: "B")])
        #expect(throws: ScheduleError.self) { try ScheduleParser.validate([a,ScheduleBlock(start: 119,end: 180,title: "B")]) }
        #expect(throws: ScheduleError.self) { try ScheduleParser.validate([ScheduleBlock(start: 60,end: 80,title: " ")]) }
    }
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 8*3600)!; return c
    }
    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026,month: 9,day: 16,hour: hour,minute: minute))!
    }
    @Test func boundariesOverridesAndTodos() throws {
        var d = SecretaryData()
        let b = ScheduleBlock(start: 540,end: 660,title: "Example")
        d.week[3] = [b]
        #expect(d.current(at: date(8,59),calendar: calendar) == nil)
        #expect(d.current(at: date(9),calendar: calendar)?.id == b.id)
        #expect(d.current(at: date(11),calendar: calendar) == nil)
        #expect(d.next(at: date(8),calendar: calendar)?.id == b.id)
        let key = SecretaryData.dayKey(date(9),calendar: calendar)
        var item = TodoItem(title: "Example task"); item.date = key; item.blockID = b.id; d.todos = [item]
        #expect(!d.todos[0].completed)
        d.exceptions[key] = []; d.unlinkMissing(on: date(9),calendar: calendar)
        #expect(d.blocks(on: date(9),calendar: calendar).isEmpty)
        #expect(d.todos[0].blockID == nil && d.todos[0].title == item.title)
        d.exceptions.removeValue(forKey: key)
        #expect(d.current(at: date(9),calendar: calendar)?.id == b.id)
        var utc = calendar; utc.timeZone = TimeZone(secondsFromGMT: 0)!
        #expect(d.current(at: date(9),calendar: utc) == nil)
        let token = d.reminderKey(b,date: date(9),calendar: calendar); d.delivered.insert(token)
        #expect(d.delivered.contains(d.reminderKey(b,date: date(10),calendar: calendar)))
    }
    @Test func storeRoundTripAndFailure() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SecretaryStore(directory: folder)
        #expect(try store.load() == SecretaryData())
        var data = SecretaryData(); data.todos = [TodoItem(title: "persist")]; data.delivered = ["sample"]
        try store.save(data); #expect(try store.load() == data)
        let original = try Data(contentsOf: store.url)
        data.version = 999
        #expect(throws: (any Error).self) { try store.save(data) }
        #expect(try Data(contentsOf: store.url) == original)
        let blocked = SecretaryStore(directory: store.url)
        #expect(throws: (any Error).self) { try blocked.save(SecretaryData()) }
    }
    @Test func replacementDoesNotAlterOtherDays() throws {
        let p = ScheduleParser.parse("每天 09:00–10:00 Work")
        let replacement = try ScheduleParser.replacement(p.rows,days: [1,2])
        #expect(Set(replacement.keys) == [1,2])
        #expect(throws: ScheduleError.self) { try ScheduleParser.replacement(p.rows,days: []) }
    }
}
