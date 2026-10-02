import Foundation
import Darwin

public struct ScheduleBlock: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var start: Int
    public var end: Int
    public var title: String
    public var colorHex: String?
    public var sourceID: UUID?
    public var categoryID: UUID?
    public init(id: UUID = UUID(), start: Int, end: Int, title: String, colorHex: String? = nil) {
        self.id = id; self.start = start; self.end = end; self.title = title
        self.colorHex = colorHex
    }
    public static func time(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    public var timeLabel: String { "\(Self.time(start))–\(Self.time(end))" }
}
public struct TodoItem: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var title: String
    public var completed = false
    public var date: String?
    public var blockID: UUID?
    public init(title: String) { self.title = title }
}
public struct SecretaryData: Codable, Equatable, Sendable {
    public var version = 2
    /// ISO weekday: Monday 1 ... Sunday 7.
    public var week: [Int: [ScheduleBlock]] = [:]
    public var exceptions: [String: [ScheduleBlock]] = [:]
    public var dayEdits: [String: ScheduleDayEdits] = [:]
    public var savedScopes: [String: [String: ScheduleSavedScope]] = [:]
    public var todos: [TodoItem] = []
    public var delivered: Set<String> = []
    public var reminders = true
    public var categories: [ScheduleCategory] = []
    public init() {}
    enum CodingKeys: String, CodingKey { case version, week, exceptions, dayEdits, savedScopes, todos, delivered, reminders, categories }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        week = try c.decode([Int: [ScheduleBlock]].self, forKey: .week)
        exceptions = try c.decode([String: [ScheduleBlock]].self, forKey: .exceptions)
        dayEdits = try c.decodeIfPresent([String: ScheduleDayEdits].self, forKey: .dayEdits) ?? [:]
        savedScopes = try c.decodeIfPresent([String: [String: ScheduleSavedScope]].self, forKey: .savedScopes) ?? [:]
        todos = try c.decode([TodoItem].self, forKey: .todos)
        delivered = try c.decode(Set<String>.self, forKey: .delivered)
        reminders = try c.decode(Bool.self, forKey: .reminders)
        categories = try c.decodeIfPresent([ScheduleCategory].self, forKey: .categories) ?? []
    }
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public func blocks(on date: Date, calendar: Calendar = .current) -> [ScheduleBlock] {
        let key = Self.dayKey(date, calendar: calendar)
        let base = exceptions[key] ?? week[(calendar.component(.weekday, from: date) + 5) % 7 + 1] ?? []
        let edit = dayEdits[key] ?? ScheduleDayEdits()
        let replaced = Set(edit.upserts.map(\.id)).union(edit.removed)
        return (base.filter { !replaced.contains($0.id) } + edit.upserts).sorted { $0.start < $1.start }
    }
    public static func minute(_ date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
    public func current(at date: Date, calendar: Calendar = .current) -> ScheduleBlock? {
        let m = Self.minute(date, calendar: calendar)
        return blocks(on: date, calendar: calendar).first { $0.start <= m && m < $0.end }
    }
    public func next(at date: Date, calendar: Calendar = .current) -> ScheduleBlock? {
        let m = Self.minute(date, calendar: calendar)
        return blocks(on: date, calendar: calendar).first { $0.start > m }
    }
    public func reminderKey(_ block: ScheduleBlock, date: Date, calendar: Calendar = .current) -> String {
        Self.dayKey(date, calendar: calendar) + ":" + (block.sourceID ?? block.id).uuidString
    }
    public mutating func unlinkMissing(on date: Date, calendar: Calendar = .current) {
        let key = Self.dayKey(date, calendar: calendar), ids = Set(blocks(on: date, calendar: calendar).map(\.id))
        for i in todos.indices where todos[i].date == key && !ids.contains(todos[i].blockID ?? UUID()) {
            todos[i].date = nil; todos[i].blockID = nil
        }
    }
    public func validate() throws {
        try validateCategories()
        guard (1...4).contains(version), week.keys.allSatisfy({ (1...7).contains($0) }) else { throw ScheduleError.invalid }
        for (date, scopes) in savedScopes {
            guard Self.date(date) != nil else { throw ScheduleError.invalid }
            for (id, scope) in scopes {
                guard UUID(uuidString: id) != nil else { throw ScheduleError.invalid }
                if let days = scope.weekdays { guard !days.isEmpty, days.isSubset(of: Set(1...7)) else { throw ScheduleError.invalid } }
            }
        }
        for blocks in Array(week.values) + Array(exceptions.values) { try ScheduleParser.validate(blocks) }
        for (key, edit) in dayEdits {
            guard let date = Self.date(key), Set(edit.upserts.map(\.id)).isDisjoint(with: edit.removed) else { throw ScheduleError.invalid }
            try ScheduleParser.validate(edit.upserts)
            try Self.validateConflict(blocks(on: date), context: key)
        }
        guard Set(todos.map(\.id)).count == todos.count, todos.allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw ScheduleError.invalid }
    }
    public static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, let date = calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2])), dayKey(date, calendar: calendar) == key else { return nil }
        return date
    }
    public func repeatingDays(for id: UUID) -> Set<Int> { Set(week.keys.filter { week[$0]?.contains(where: { $0.id == id }) == true }) }
    /// Transactional single-event operation. Existing whole-day exceptions remain authoritative.
    public mutating func change(_ block: ScheduleBlock, on date: Date, weekdays: Set<Int>? = nil, delete: Bool = false) throws {
        var draft = self
        if let days = weekdays {
            guard !days.isEmpty, days.isSubset(of: Set(1...7)) else { throw ScheduleError.invalid }
            for day in 1...7 {
                var values = draft.week[day] ?? []
                values.removeAll { $0.id == block.id }
                if !delete && days.contains(day) { values.append(block) }
                try Self.validateConflict(values, context: ["周一 / Mon", "周二 / Tue", "周三 / Wed", "周四 / Thu", "周五 / Fri", "周六 / Sat", "周日 / Sun"][day-1])
                if !values.isEmpty || draft.week[day] != nil { draft.week[day] = values }
            }
        } else {
            let key = Self.dayKey(date)
            var edit = draft.dayEdits[key] ?? ScheduleDayEdits()
            edit.upserts.removeAll { $0.id == block.id }
            if delete { edit.removed.insert(block.id) }
            else { edit.removed.remove(block.id); edit.upserts.append(block) }
            draft.dayEdits[key] = edit
            try Self.validateConflict(draft.blocks(on: date), context: key)
        }
        draft.version = max(2, draft.version)
        try draft.validate()
        draft.reconcileTodoLinks()
        self = draft
    }
    public mutating func reconcileTodoLinks() {
        for key in Set(todos.compactMap(\.date)) { if let date = Self.date(key) { unlinkMissing(on: date) } }
    }
    public mutating func restoreWeekly(on date: Date) {
        let key = Self.dayKey(date)
        exceptions.removeValue(forKey: key); dayEdits.removeValue(forKey: key)
        savedScopes.removeValue(forKey: key)
        unlinkMissing(on: date)
    }
    private static func validateConflict(_ blocks: [ScheduleBlock], context: String) throws {
        let sorted = blocks.sorted { $0.start < $1.start }
        for pair in zip(sorted, sorted.dropFirst()) where pair.0.end > pair.1.start {
            throw ScheduleConflict(context: context, first: pair.0, second: pair.1)
        }
        try ScheduleParser.validate(blocks)
    }
}
public struct ScheduleDayEdits: Codable, Equatable, Sendable {
    public var upserts: [ScheduleBlock] = []
    public var removed: Set<UUID> = []
    public init() {}
}
public struct ScheduleConflict: Error, LocalizedError {
    public let context: String
    public let first: ScheduleBlock
    public let second: ScheduleBlock
    public var errorDescription: String? { "\(context)：\(first.timeLabel) \(first.title) ↔ \(second.timeLabel) \(second.title)（时间重叠 / overlap）" }
}
public enum ScheduleError: Error, LocalizedError {
    case invalid, overlap, line(Int)
    public var errorDescription: String? {
        switch self {
        case .invalid: "请检查事项、时间范围和版本；跨午夜请拆成两行。 / Check title and times; split overnight events."
        case .overlap: "同一天的时间段不能重叠。 / Time blocks overlap."
        case .line(let n): "第 \(n) 行无法识别，请使用：工作日 09:00–11:00 开发 App。 / Invalid line \(n)."
        }
    }
}
public struct ScheduleImportRow: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var days: Set<Int>
    public var block: ScheduleBlock
    public init(days: Set<Int>, block: ScheduleBlock) { self.days = days; self.block = block }
}
public struct ScheduleParseResult: Sendable {
    public var rows: [ScheduleImportRow]
    public var errors: [String]
}
public enum ScheduleParser {
    public static func minute(_ text: String, end: Bool = false) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...59).contains(m),
              (0...23).contains(h) || (end && h == 24 && m == 0) else { return nil }
        return h * 60 + m
    }
    public static func days(_ text: String) -> Set<Int>? {
        let s = text.replacingOccurrences(of: "星期", with: "周").replacingOccurrences(of: "周天", with: "周日").replacingOccurrences(of: " ", with: "")
        if s == "每天" { return Set(1...7) }
        if s == "工作日" { return Set(1...5) }
        if s == "周末" { return [6,7] }
        let names = ["周一","周二","周三","周四","周五","周六","周日"]
        if let i = names.firstIndex(of: s) { return [i+1] }
        let p = s.components(separatedBy: CharacterSet(charactersIn: "至到-–—"))
        if p.count == 2, let a = names.firstIndex(of: p[0]), let b = names.firstIndex(of: p[1]), a <= b { return Set((a+1)...(b+1)) }
        return nil
    }
    public static func parse(_ text: String) -> ScheduleParseResult {
        var result = ScheduleParseResult(rows: [], errors: [])
        let regex = try! NSRegularExpression(pattern: #"^(.+?)\s+(\d{1,2}:\d{2})\s*[-–—~至]\s*(\d{1,2}:\d{2})\s+(.+)$"#)
        for (index, line) in text.components(separatedBy: .newlines).enumerated() {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { continue }
            guard let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else {
                result.errors.append(ScheduleError.line(index+1).localizedDescription); continue
            }
            func field(_ i: Int) -> String { String(s[Range(match.range(at: i), in: s)!]) }
            guard let days = days(field(1)), let start = minute(field(2)), let end = minute(field(3), end: true), end > start else {
                result.errors.append(ScheduleError.line(index+1).localizedDescription); continue
            }
            result.rows.append(ScheduleImportRow(days: days, block: ScheduleBlock(start: start, end: end, title: field(4))))
        }
        return result
    }
    public static func validate(_ blocks: [ScheduleBlock]) throws {
        let sorted = blocks.sorted { $0.start < $1.start }
        guard Set(blocks.map(\.id)).count == blocks.count else { throw ScheduleError.invalid }
        for (i,b) in sorted.enumerated() {
            if let hex = b.colorHex {
                guard hex.count == 6, hex.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) else { throw ScheduleError.invalid }
            }
            guard b.start >= 0, b.start < b.end, b.end <= 1440, !b.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ScheduleError.invalid }
            if i > 0 && sorted[i-1].end > b.start { throw ScheduleError.overlap }
        }
    }
    public static func replacement(_ rows: [ScheduleImportRow], days: Set<Int>) throws -> [Int: [ScheduleBlock]] {
        guard !days.isEmpty, days.isSubset(of: Set(1...7)), rows.allSatisfy({ !$0.days.isEmpty && $0.days.isSubset(of: Set(1...7)) }) else { throw ScheduleError.invalid }
        var value: [Int: [ScheduleBlock]] = [:]
        for day in days {
            let blocks = rows.filter { $0.days.contains(day) }.map(\.block).sorted { $0.start < $1.start }
            try validate(blocks); value[day] = blocks
        }
        return value
    }
}
public struct SecretaryStore: Sendable {
    public let url: URL
    public let legacyURL: URL
    public init(directory: URL) {
        url = directory.appendingPathComponent("secretary-v2.json")
        legacyURL = directory.appendingPathComponent("secretary-v1.json")
    }
    public func load() throws -> SecretaryData {
        let source = FileManager.default.fileExists(atPath: url.path) ? url : legacyURL
        guard FileManager.default.fileExists(atPath: source.path) else { return SecretaryData() }
        let data = try JSONDecoder().decode(SecretaryData.self, from: Data(contentsOf: source))
        try data.validate(); return data
    }
    public func save(_ value: SecretaryData) throws {
        try value.validate()
        // Never overwrite a corrupt current file, or silently migrate corrupt legacy data.
        _ = try load()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path), FileManager.default.fileExists(atPath: legacyURL.path) {
            let migration = url.deletingLastPathComponent().appendingPathComponent("before-schedule-0226")
            try FileManager.default.createDirectory(at: migration, withIntermediateDirectories: true)
            let original = migration.appendingPathComponent("secretary-v1.json")
            if !FileManager.default.fileExists(atPath: original.path) {
                try FileManager.default.copyItem(at: legacyURL, to: original)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: original.path)
            }
        }
        let backup = url.deletingLastPathComponent().appendingPathComponent("secretary-v1.before-calendar.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let original = try Data(contentsOf: url)
            let old = try JSONDecoder().decode(SecretaryData.self, from: original)
            if old.version == 1 && !FileManager.default.fileExists(atPath: backup.path) {
                try original.write(to: backup, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
            }
        }
        let v3Backup = url.deletingLastPathComponent().appendingPathComponent("secretary-before-overlap-v3.json")
        if value.version >= 3, FileManager.default.fileExists(atPath: url.path), !FileManager.default.fileExists(atPath: v3Backup.path) {
            let original = try Data(contentsOf: url)
            if try JSONDecoder().decode(SecretaryData.self, from: original).version < 3 {
                try original.write(to: v3Backup, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: v3Backup.path)
            }
        }
        var upgraded = value; upgraded.version = max(2, value.version)
        let scopeBackup = url.deletingLastPathComponent().appendingPathComponent("secretary-before-scope-v4.json")
        if value.version >= 4, FileManager.default.fileExists(atPath: url.path), !FileManager.default.fileExists(atPath: scopeBackup.path) {
            let original = try Data(contentsOf: url)
            if try JSONDecoder().decode(SecretaryData.self, from: original).version < 4 {
                try original.write(to: scopeBackup, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: scopeBackup.path)
            }
        }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".secretary-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try JSONEncoder().encode(upgraded).write(to: temporary, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        guard rename(temporary.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
