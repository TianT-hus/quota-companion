import Foundation
import Testing
@testable import QuotaCore

struct ScheduleScopeTests {
    let today = SecretaryData.date("2026-09-24")!
    @Test func promoteAndDemotePersistScope() throws {
        var data = SecretaryData()
        let task = ScheduleBlock(start: 540, end: 600, title: "Task")
        data = try data.resolving(task, on: today).result
        #expect(data.editingScope(for: task.id, on: today).weekdays == nil)
        let snapshot = data
        var revised = task; revised.title = "Recurring"; revised.end = 610
        let proposed = try data.resolving(revised, on: today, weekdays: [1,4])
        #expect(data == snapshot) // Cancel does not commit scope memory.
        data = proposed.result
        #expect(data.editingScope(for: task.id, on: today).weekdays == [1,4])
        #expect(data.blocks(on: today) == [revised])
        #expect(data.dayEdits[SecretaryData.dayKey(today)]?.upserts.isEmpty == true)
        data = try JSONDecoder().decode(SecretaryData.self, from: JSONEncoder().encode(data))
        #expect(data.editingScope(for: task.id, on: today).weekdays == [1,4])
        data = try data.resolving(task, on: today).result
        #expect(data.editingScope(for: task.id, on: today).weekdays == nil)
        #expect(data.week[1] == [revised] && data.week[4] == [revised])
        #expect(data.editingScope(for: task.id, on: today.addingTimeInterval(7*86400)).weekdays == [1,4])
    }
    @Test func promotionOnlyTouchesCurrentOccurrence() throws {
        var data = SecretaryData()
        let task = ScheduleBlock(start: 540,end: 600,title: "Task")
        let other = ScheduleBlock(start: 700,end: 720,title: "Other")
        let next = today.addingTimeInterval(7*86400)
        data.exceptions[SecretaryData.dayKey(today)] = [task, other]
        data.exceptions[SecretaryData.dayKey(next)] = [task, other]
        var todo = TodoItem(title: "Linked"); todo.date = SecretaryData.dayKey(today); todo.blockID = task.id; data.todos = [todo]
        data.delivered.insert(data.reminderKey(task, date: today))
        var changed = task; changed.title = "Changed"
        let p = try data.resolving(changed, on: today, weekdays: [1,4])
        #expect(p.result.blocks(on: today) == [changed,other])
        #expect(p.result.blocks(on: next) == [task,other])
        #expect(p.result.editingScope(for: task.id, on: today).weekdays == [1,4])
        #expect(p.result.todos == data.todos && p.result.delivered == data.delivered)
        let omitted = try data.resolving(changed, on: today, weekdays: [1])
        #expect(omitted.result.blocks(on: today) == [other])
        #expect(omitted.result.todos[0].blockID == nil)
    }
    @Test func legacyFallbackAndBackup() throws {
        var legacy = SecretaryData()
        let task = ScheduleBlock(start: 540,end: 600,title: "Task")
        legacy.week[4] = [task]
        #expect(legacy.editingScope(for: task.id, on: today).weekdays == [4])
        try legacy.change(task, on: today)
        #expect(legacy.editingScope(for: task.id, on: today).weekdays == nil)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SecretaryStore(directory: root); try store.save(legacy)
        let updated = try legacy.resolving(task, on: today, weekdays: Set(1...7)).result
        try store.save(updated)
        #expect(try store.load().editingScope(for: task.id, on: today).weekdays == Set(1...7))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("secretary-before-scope-v4.json").path))
        #expect(throws: (any Error).self) { try updated.resolving(task, on: today, weekdays: []) }
        #expect(try store.load() == updated)
    }
}
