import AppKit
import Combine
import QuotaCore

enum SecretaryPage: String { case summary, day, todos }
enum ScheduleEditMode: String, Identifiable { case paste, week, today, event; var id: String { rawValue } }

@MainActor final class SecretaryModel: ObservableObject {
    @Published private(set) var data = SecretaryData()
    @Published var page: SecretaryPage = .summary
    @Published var calendarHiddenCategories: Set<UUID> = []
    @Published var calendarHideUncategorized = false
    @Published var calendarPosition = TimelinePosition(date: Date())
    func calendarBlocks(on date: Date) -> [ScheduleBlock] {
        data.blocks(on: date).filter { block in
            block.categoryID.map { !calendarHiddenCategories.contains($0) } ?? !calendarHideUncategorized
        }.map { block in var result = block; result.colorHex = data.colorHex(for: block); return result }
    }
    func changeCategory(_ change: (inout SecretaryData) throws -> Void) throws {
        guard !readFailed else { throw CocoaError(.fileReadCorruptFile) }
        var draft = data; try change(&draft); try store.save(draft); data = draft
    }
    @Published var editor: ScheduleEditMode?
    var eventDate = Date()
    var eventBlock = ScheduleBlock(start: 540, end: 600, title: "")
    var eventIsNew = false
    func editEvent(on date: Date, block: ScheduleBlock? = nil, minute: Int = 540) {
        eventDate = date; eventIsNew = block == nil
        let start = min(1439, max(0, minute))
        eventBlock = block ?? ScheduleBlock(start: start, end: min(1440, start + 60), title: "")
        error = ""; editor = .event
    }
    @Published var error = ""
    @Published private(set) var now = Date()
    @Published private(set) var reminder: ScheduleBlock?
    @Published private(set) var deleted: TodoItem?
    private let store: SecretaryStore
    private var boundary: Timer?
    private var dismissTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var readFailed = false
    private var visible = false
    private var started = false
    var onReminder: ((ScheduleBlock, Date) -> Void)?
    init(directory: URL) {
        store = SecretaryStore(directory: directory)
        do { data = try store.load() } catch { readFailed = true; self.error = "日程文件无法读取，已停止写入以保护原文件。 / Cannot read schedule; writes disabled." }
    }
    var blocks: [ScheduleBlock] { data.blocks(on: now) }
    var current: ScheduleBlock? { data.current(at: now) }
    var next: ScheduleBlock? { data.next(at: now) }
    var dayKey: String { SecretaryData.dayKey(now) }
    var hasPlan: Bool { !data.week.isEmpty || !data.exceptions.isEmpty || !data.dayEdits.isEmpty }
    func commitEvent(_ resolution: ScheduleResolution) throws {
        guard !readFailed else { throw CocoaError(.fileReadCorruptFile) }
        guard data == resolution.baseline else { throw CocoaError(.fileWriteFileExists) }
        try store.save(resolution.result)
        data = resolution.result
        if started { refresh() }
    }
    @discardableResult func commit(_ change: (inout SecretaryData) throws -> Void) -> Bool {
        guard !readFailed else { return false }
        do {
            var draft = data; try change(&draft); draft.version = max(2, draft.version); try store.save(draft)
            data = draft; error = ""; if started { refresh() }; return true
        } catch { self.error = "保存失败：\(error.localizedDescription) / Not saved."; return false }
    }
    func setVisible(_ value: Bool) {
        guard visible != value else { return }; visible = value
        if !value { reminder = nil; dismissTimer?.invalidate() }
        if started { refresh() }
    }
    func start() {
        guard !started else { return }; started = true
        for name in [NSNotification.Name.NSSystemTimeZoneDidChange, NSNotification.Name.NSSystemClockDidChange, .NSCalendarDayChanged] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        refresh()
    }
    func stop() {
        boundary?.invalidate(); dismissTimer?.invalidate(); started = false
        for observer in observers { NotificationCenter.default.removeObserver(observer); NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }
    func refresh(at date: Date = .now) {
        now = date
        // Persist before showing so a restart cannot replay the same reminder.
        if visible, editor == nil, data.reminders, let item = current {
            let key = data.reminderKey(item, date: date)
            if !data.delivered.contains(key), !readFailed {
                var draft = data
                draft.delivered = draft.delivered.filter { $0 >= String(dayKey.prefix(4)) }
                draft.delivered.insert(key)
                do {
                    try store.save(draft); data = draft; reminder = item
                    onReminder?(item, date)
                    dismissTimer?.invalidate()
                    dismissTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
                        Task { @MainActor in self?.dismissReminder() }
                    }
                } catch { self.error = "提醒记录保存失败，本次未弹出。 / Could not save reminder state." }
            }
        }
        boundary?.invalidate()
        guard started else { return }
        let calendar = Calendar.current
        var dates = blocks.flatMap { [$0.start, $0.end] }.compactMap { minute in
            calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: date)
        }.filter { $0 > date }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) { dates.append(tomorrow) }
        let deadline = dates.min() ?? date.addingTimeInterval(3600)
        boundary = Timer.scheduledTimer(withTimeInterval: max(1, deadline.timeIntervalSince(date)), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func dismissReminder() { reminder = nil; dismissTimer?.invalidate() }
    func delete(_ item: TodoItem) { if commit({ $0.todos.removeAll { $0.id == item.id } }) { deleted = item } }
    func undoDelete() {
        guard let item = deleted else { return }
        if commit({ $0.todos.append(item) }) { deleted = nil }
    }
    func saveRows(_ rows: [ScheduleImportRow], days: Set<Int>, today: Bool) -> Bool {
        let date = now
        return commit { draft in
            if today {
                let blocks = rows.map(\.block); try ScheduleParser.validate(blocks)
                draft.exceptions[SecretaryData.dayKey(date)] = blocks
                draft.dayEdits.removeValue(forKey: SecretaryData.dayKey(date))
            } else {
                let replacement = try ScheduleParser.replacement(rows, days: days)
                for (day, blocks) in replacement { draft.week[day] = blocks }
            }
            // Remove invalid links for every referenced date, including future template occurrences.
            let calendar = Calendar.current
            for key in Set(draft.todos.compactMap(\.date)) {
                let p = key.split(separator: "-").compactMap { Int($0) }
                if p.count == 3, let d = calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) { draft.unlinkMissing(on: d) }
            }
        }
    }
    func restoreToday() {
        let date = now
        _ = commit { $0.restoreWeekly(on: date) }
    }
}
