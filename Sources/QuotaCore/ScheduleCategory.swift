import Foundation

public struct ScheduleCategory: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id; self.name = name.trimmingCharacters(in: .whitespacesAndNewlines); self.colorHex = colorHex.uppercased()
    }
}
public enum ScheduleCategoryError: Error, LocalizedError {
    case name, duplicate, color, reference
    public var errorDescription: String? {
        switch self {
        case .name: "分类名称须为 1–30 个字符，且不能仅含空白。 / Use 1–30 characters."
        case .duplicate: "分类名称已存在。 / Category name already exists."
        case .color: "请选择有效的六位颜色。 / Choose a six-digit color."
        case .reference: "分类记录不完整，已停止保存。 / Invalid category reference; not saved."
        }
    }
}
extension SecretaryData {
    public func validateCategories() throws {
        guard Set(categories.map(\.id)).count == categories.count else { throw ScheduleCategoryError.reference }
        var names = Set<String>()
        for category in categories {
            let name = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 30, name == category.name else { throw ScheduleCategoryError.name }
            guard names.insert(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))).inserted else { throw ScheduleCategoryError.duplicate }
            guard category.colorHex.count == 6, category.colorHex.allSatisfy({ $0.isHexDigit }) else { throw ScheduleCategoryError.color }
        }
        let ids = Set(categories.map(\.id))
        for block in Array(week.values).flatMap({ $0 }) + Array(exceptions.values).flatMap({ $0 }) + dayEdits.values.flatMap(\.upserts) {
            if let id = block.categoryID, !ids.contains(id) { throw ScheduleCategoryError.reference }
        }
    }
    public func colorHex(for block: ScheduleBlock) -> String? {
        categories.first { $0.id == block.categoryID }?.colorHex ?? block.colorHex
    }
    public mutating func saveCategory(_ value: ScheduleCategory) throws {
        var draft = self
        if let index = draft.categories.firstIndex(where: { $0.id == value.id }) { draft.categories[index] = value }
        else { draft.categories.append(value) }
        try draft.validate(); self = draft
    }
    public mutating func deleteCategory(_ id: UUID) throws {
        guard let category = categories.first(where: { $0.id == id }) else { return }
        var draft = self
        func unlink(_ blocks: [ScheduleBlock]) -> [ScheduleBlock] {
            blocks.map { item in
                var block = item
                if block.categoryID == id { block.categoryID = nil; block.colorHex = category.colorHex }
                return block
            }
        }
        draft.week = draft.week.mapValues(unlink)
        draft.exceptions = draft.exceptions.mapValues(unlink)
        for key in Array(draft.dayEdits.keys) {
            var edit = draft.dayEdits[key]!
            edit.upserts = unlink(edit.upserts); draft.dayEdits[key] = edit
        }
        draft.categories.removeAll { $0.id == id }
        try draft.validate(); self = draft
    }
}

public enum ScheduleWeek {
    public static func dates(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let day = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: day) + 5) % 7
        guard let monday = calendar.date(byAdding: .day, value: -offset, to: day) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }
}
