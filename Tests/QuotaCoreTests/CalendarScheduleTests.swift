import Foundation
import Testing
@testable import QuotaCore

struct CalendarScheduleTests {
    @Test func colorCompatibilityScopeAndRollback() throws {
        let original = ScheduleBlock(start: 600, end: 660, title: "Color")
        let decoded = try JSONDecoder().decode(ScheduleBlock.self, from: JSONEncoder().encode(original))
        #expect(decoded.colorHex == nil)
        var d = SecretaryData()
        try d.change(original, on: date, weekdays: [4,5])
        var colored = original; colored.colorHex = "D8E8FA"
        try d.change(colored, on: date)
        #expect(d.blocks(on: date).first?.colorHex == "D8E8FA")
        #expect(d.week[4]?.first?.colorHex == nil)
        try d.change(colored, on: date, weekdays: [4,5])
        #expect(d.week[5]?.first?.colorHex == "D8E8FA")
        let roundtrip = try JSONDecoder().decode(SecretaryData.self, from: JSONEncoder().encode(d))
        #expect(roundtrip == d)
        let before = d; colored.colorHex = "not-a-color"
        #expect(throws: (any Error).self) { try d.change(colored, on: date) }
        #expect(d == before)
    }
    private var date: Date { SecretaryData.date("2026-09-24")! }
    @Test func individualOverrideDoesNotFreezeOtherEvents() throws {
        var d = SecretaryData()
        let a = ScheduleBlock(start: 540, end: 600, title: "Same title")
        let b = ScheduleBlock(start: 660, end: 720, title: "Same title")
        d.week[4] = [a,b]
        var edit = a; edit.title = "Changed today"
        try d.change(edit, on: date)
        var weekly = b; weekly.title = "Changed weekly"
        try d.change(weekly, on: date, weekdays: [4])
        #expect(d.exceptions.isEmpty)
        #expect(d.blocks(on: date).map(\.title) == ["Changed today", "Changed weekly"])
        #expect(d.blocks(on: date).map(\.id) == [a.id,b.id])
        #expect(d.blocks(on: date.addingTimeInterval(7*86400)).first?.title == "Same title")
        d.restoreWeekly(on: date)
        #expect(d.blocks(on: date).first?.title == "Same title")
    }
    @Test func repeatingScopeConflictAndLinks() throws {
        var d = SecretaryData()
        let a = ScheduleBlock(start: 0,end: 10,title: "A")
        let b = ScheduleBlock(start: 10,end: 20,title: "B")
        try d.change(a, on: date, weekdays: [4,5])
        try d.change(b, on: date, weekdays: [4])
        var task = TodoItem(title: "Keep me"); task.date = SecretaryData.dayKey(date); task.blockID = a.id; d.todos = [task]
        let key = d.reminderKey(a, date: date); d.delivered.insert(key)
        var edit = a; edit.title = "Rename"
        try d.change(edit, on: date, weekdays: [4,5,6])
        #expect(d.todos[0].blockID == a.id && d.delivered.contains(d.reminderKey(edit, date: date)))
        let before = d
        edit.end = 11
        #expect(throws: ScheduleConflict.self) { try d.change(edit, on: date, weekdays: [4]) }
        #expect(d == before)
        try d.change(a, on: date, delete: true)
        #expect(d.todos[0].blockID == nil && d.todos[0].title == "Keep me")
        #expect(d.week[4]?.count == 2)
        #expect(d.blocks(on: date).map(\.id) == [b.id])
    }
    @Test func legacyExceptionStaysAndBoundaryValidation() throws {
        var d = SecretaryData()
        let block = ScheduleBlock(start: 1439, end: 1440, title: "End")
        d.exceptions[SecretaryData.dayKey(date)] = [block]
        var edit = block; edit.title = "Weekly"
        try d.change(edit, on: date, weekdays: [4])
        #expect(d.blocks(on: date).first?.title == "End")
        try d.change(edit, on: date)
        #expect(d.blocks(on: date).first?.title == "Weekly")
        #expect(d.exceptions[SecretaryData.dayKey(date)] == [block])
        #expect(throws: (any Error).self) { try d.change(ScheduleBlock(start: 1440, end: 1441, title: "Invalid"), on: date) }
        #expect(throws: (any Error).self) { try d.change(edit, on: date, weekdays: []) }
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
        #expect(d.current(at: noon) == nil)
    }
    @Test func migrationBackupAndPersistence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = SecretaryStore(directory: root)
        var legacy = SecretaryData(); legacy.version = 1
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        json.removeValue(forKey: "dayEdits")
        let bytes = try JSONSerialization.data(withJSONObject: json)
        try bytes.write(to: store.url)
        var loaded = try store.load()
        #expect(loaded.dayEdits.isEmpty)
        try loaded.change(ScheduleBlock(start: 30,end: 60,title: "Persist"), on: date)
        try store.save(loaded)
        #expect(try store.load() == loaded)
        let backup = root.appendingPathComponent("secretary-v1.before-calendar.json")
        #expect(try Data(contentsOf: backup) == bytes)
        try store.save(loaded); #expect(try Data(contentsOf: backup) == bytes)
    }
    @Test func weeklyRemovalRetainsExplicitExceptionsAndUnlinksMissingOccurrences() throws {
        var d = SecretaryData()
        let block = ScheduleBlock(start: 600,end: 660,title: "Weekly")
        try d.change(block, on: date, weekdays: [4,5])
        let friday = Calendar.current.date(byAdding: .day,value: 1,to: date)!
        var todo = TodoItem(title: "Unlink only"); todo.date = SecretaryData.dayKey(friday); todo.blockID = block.id
        d.todos = [todo]
        try d.change(block, on: date, weekdays: [4])
        #expect(d.repeatingDays(for: block.id) == [4])
        #expect(d.todos[0].blockID == nil)
        var local = block; local.title = "Explicit date edit"
        try d.change(local, on: date)
        try d.change(block, on: date, weekdays: [4],delete: true)
        #expect(d.repeatingDays(for: block.id).isEmpty)
        #expect(d.blocks(on: date) == [local])
    }
    @Test func timezoneAndMinuteBoundaries() throws {
        var d = SecretaryData()
        let b = ScheduleBlock(start: 600,end: 601,title: "Minute")
        for day in 1...7 { d.week[day] = [b] }
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let ten = utc.date(from: DateComponents(year: 2026,month: 9,day: 24,hour: 10))!
        #expect(d.current(at: ten, calendar: utc)?.id == b.id)
        #expect(d.current(at: ten.addingTimeInterval(59),calendar: utc)?.id == b.id)
        #expect(d.current(at: ten.addingTimeInterval(60),calendar: utc) == nil)
        var shifted = utc; shifted.timeZone = TimeZone(secondsFromGMT: 8*3600)!
        #expect(d.current(at: ten,calendar: shifted) == nil)
    }
}
