import Foundation
import Testing
@testable import QuotaCore

struct ScheduleResolutionTests {
    let date = SecretaryData.date("2026-09-24")!
    @Test func splitAndReminderIdentity() throws {
        var d = SecretaryData()
        let old = ScheduleBlock(start: 540, end: 720, title: "Old", colorHex: "DDEEDB")
        d.week[4] = [old]
        var todo = TodoItem(title: "Linked"); todo.date = SecretaryData.dayKey(date); todo.blockID = old.id; d.todos = [todo]
        let incoming = ScheduleBlock(start: 600, end: 660, title: "New")
        let proposal = try d.resolving(incoming, on: date)
        #expect(d.blocks(on: date) == [old])
        let blocks = proposal.result.blocks(on: date)
        #expect(blocks.map(\.start) == [540,600,660])
        #expect(blocks.map(\.end) == [600,660,720])
        #expect(blocks[0].id == old.id && blocks[2].id != old.id)
        #expect(blocks[2].sourceID == old.id && blocks[2].colorHex == old.colorHex)
        #expect(proposal.result.reminderKey(blocks[2], date: date) == d.reminderKey(old, date: date))
        #expect(proposal.result.todos[0].blockID == old.id)
        #expect(try JSONDecoder().decode(SecretaryData.self, from: JSONEncoder().encode(proposal.result)) == proposal.result)
    }
    @Test func trimDeleteAdjacentAndSelf() throws {
        var d = SecretaryData()
        let a = ScheduleBlock(start: 540, end: 600, title: "A")
        let b = ScheduleBlock(start: 600, end: 660, title: "B")
        d.week[4] = [a,b]
        let n = ScheduleBlock(start: 570, end: 630, title: "New")
        let p = try d.resolving(n, on: date)
        #expect(p.adjustments.count == 2)
        #expect(p.result.blocks(on: date).map(\.timeLabel) == ["09:00–09:30","09:30–10:30","10:30–11:00"])
        #expect(try d.resolving(a, on: date, weekdays: [4]).adjustments.isEmpty)
        #expect(try d.resolving(ScheduleBlock(start: 660,end: 700,title: "Adjacent"), on: date).adjustments.isEmpty)
        let all = try d.resolving(ScheduleBlock(start: 0,end: 1440,title: "All"), on: date)
        #expect(all.result.blocks(on: date).count == 1)
        #expect(all.result.week[4] == [a,b])
    }
    @Test func weeklyRespectsExplicitDateAndLegacy() throws {
        var d = SecretaryData()
        let template = ScheduleBlock(start: 540,end: 600,title: "Template")
        d.week[4] = [template]
        let explicit = ScheduleBlock(start: 630,end: 660,title: "Date override")
        try d.change(explicit, on: date)
        let other = date.addingTimeInterval(7*86400)
        d.exceptions[SecretaryData.dayKey(other)] = [explicit]
        var changed = template; changed.end = 720
        let p = try d.resolving(changed, on: date, weekdays: [4,5])
        #expect(p.result.blocks(on: date).map(\.timeLabel) == ["09:00–10:30","10:30–11:00","11:00–12:00"])
        #expect(p.result.blocks(on: other) == [explicit])
        #expect(p.result.repeatingDays(for: template.id) == [4,5])
        #expect(p.result.isDateSpecific(explicit.id, on: date))
    }
    @Test func migrationBackupAndInvalidRollback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SecretaryStore(directory: root)
        var d = SecretaryData(); try store.save(d)
        d = try d.resolving(ScheduleBlock(start: 0,end: 1440,title: "All"), on: date).result
        try store.save(d)
        #expect(try store.load() == d)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("secretary-before-overlap-v3.json").path))
        #expect(throws: (any Error).self) { try d.resolving(ScheduleBlock(start: 20,end: 10,title: "Invalid"), on: date) }
        #expect(try store.load() == d)
    }
}
