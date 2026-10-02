import Foundation

public struct ScheduleSavedScope: Codable, Equatable, Sendable {
    /// nil denotes an explicit single-date save; nonempty weekdays a recurring save.
    public var weekdays: Set<Int>?
    public init(weekdays: Set<Int>?) { self.weekdays = weekdays }
}

public struct ScheduleAdjustment: Equatable, Sendable {
    public let context: String
    public let before: ScheduleBlock
    public let after: [ScheduleBlock]
}
public struct ScheduleResolution: Sendable {
    public let baseline: SecretaryData
    public let result: SecretaryData
    public let adjustments: [ScheduleAdjustment]
}
extension SecretaryData {
    public func editingScope(for id: UUID, on date: Date) -> ScheduleSavedScope {
        if let saved = savedScopes[Self.dayKey(date)]?[id.uuidString] {
            // A subsequent recurring edit may change the actual weekday set.
            if saved.weekdays != nil {
                let actual = repeatingDays(for: id)
                return ScheduleSavedScope(weekdays: actual.isEmpty ? nil : actual)
            }
            return saved
        }
        let repeating = repeatingDays(for: id)
        return ScheduleSavedScope(weekdays: !isDateSpecific(id, on: date) && !repeating.isEmpty ? repeating : nil)
    }
    public func isDateSpecific(_ id: UUID, on date: Date) -> Bool {
        let key = Self.dayKey(date)
        return exceptions[key] != nil || dayEdits[key]?.upserts.contains(where: { $0.id == id }) == true
    }
    /// Pure proposal: no writes and no changes to the receiver until confirmed.
    public func resolving(_ block: ScheduleBlock, on date: Date, weekdays: Set<Int>? = nil, delete: Bool = false) throws -> ScheduleResolution {
        if !delete { try ScheduleParser.validate([block]) }
        var draft = self
        var changes: [ScheduleAdjustment] = []
        func subtract(_ old: ScheduleBlock, _ priority: ScheduleBlock, context: String) -> [ScheduleBlock] {
            guard old.start < priority.end && priority.start < old.end else { return [old] }
            var parts: [ScheduleBlock] = []
            if old.start < priority.start { var left = old; left.end = priority.start; parts.append(left) }
            if old.end > priority.end {
                var right = old; right.start = priority.end
                if !parts.isEmpty { right.id = UUID(); right.sourceID = old.sourceID ?? old.id }
                parts.append(right)
            }
            changes.append(ScheduleAdjustment(context: context, before: old, after: parts))
            return parts
        }
        if let days = weekdays {
            guard !days.isEmpty, days.isSubset(of: Set(1...7)) else { throw ScheduleError.invalid }
            let currentKey = Self.dayKey(date)
            let currentDay = (Calendar.current.component(.weekday, from: date) + 5) % 7 + 1
            // Promotion only replaces this occurrence's stale date override.
            // Never erase other items or another date's explicit arrangement.
            if var edit = draft.dayEdits[currentKey] {
                edit.upserts.removeAll { $0.id == block.id }
                edit.removed.remove(block.id)
                draft.dayEdits[currentKey] = edit
            }
            if let exception = draft.exceptions[currentKey] {
                var values = exception.filter { $0.id != block.id }
                if !delete && days.contains(currentDay) {
                    values = values.flatMap { subtract($0, block, context: currentKey) }
                    values.append(block)
                }
                draft.exceptions[currentKey] = values.sorted { $0.start < $1.start }
            }
            for day in 1...7 {
                var values = (draft.week[day] ?? []).filter { $0.id != block.id }
                if !delete && days.contains(day) {
                    values = values.flatMap { subtract($0, block, context: "weekday:\(day)") }
                    values.append(block)
                }
                if draft.week[day] != nil || !values.isEmpty { draft.week[day] = values.sorted { $0.start < $1.start } }
            }
            // Explicit date edits win over changed templates; whole-day exceptions stay authoritative.
            for key in draft.dayEdits.keys.sorted() where draft.exceptions[key] == nil {
                guard let dayDate = Self.date(key), var edit = draft.dayEdits[key] else { continue }
                let day = (Calendar.current.component(.weekday, from: dayDate) + 5) % 7 + 1
                let excluded = Set(edit.upserts.map(\.id)).union(edit.removed)
                for template in draft.week[day] ?? [] where !excluded.contains(template.id) {
                    var parts = [template]
                    for explicit in edit.upserts { parts = parts.flatMap { subtract($0, explicit, context: key) } }
                    if parts != [template] {
                        edit.removed.insert(template.id)
                        if parts.contains(where: { $0.id == template.id }) { edit.removed.remove(template.id) }
                        edit.upserts.append(contentsOf: parts)
                    }
                }
                draft.dayEdits[key] = edit
            }
        } else {
            let key = Self.dayKey(date)
            var edit = draft.dayEdits[key] ?? ScheduleDayEdits()
            let current = blocks(on: date).filter { $0.id != block.id }
            let resolved = delete ? current : current.flatMap { subtract($0, block, context: key) }
            let changedIDs = Set(changes.map { $0.before.id }).union([block.id])
            edit.upserts.removeAll { changedIDs.contains($0.id) }
            edit.removed.formUnion(changedIDs)
            let currentIDs = Set(current.map(\.id))
            let replacements = resolved.filter { changedIDs.contains($0.id) || !currentIDs.contains($0.id) } + (delete ? [] : [block])
            edit.upserts.append(contentsOf: replacements)
            edit.removed.subtract(replacements.map(\.id))
            draft.dayEdits[key] = edit
        }
        let key = Self.dayKey(date)
        if delete { draft.savedScopes[key]?[block.id.uuidString] = nil }
        else { draft.savedScopes[key, default: [:]][block.id.uuidString] = ScheduleSavedScope(weekdays: weekdays) }
        draft.version = 4
        try draft.validate()
        draft.reconcileTodoLinks()
        return ScheduleResolution(baseline: self, result: draft, adjustments: changes)
    }
}
