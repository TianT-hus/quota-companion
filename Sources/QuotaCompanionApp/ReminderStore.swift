import Foundation
import EventKit
import QuotaCore

enum ReminderAccess { case unknown, allowed, denied }
struct ReminderList: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var title: String
    var account: String
    var writable: Bool
}
struct ReminderValue: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var externalID: String?
    var listID: String
    var title: String
    var completed: Bool
    var due: DateComponents?
    var marker: String?
    var modified: Date?
}
enum ReminderMutation { case title(String), completed(Bool), delete }
enum ReminderFailure: Error, LocalizedError {
    case permission, unavailable, readOnly, missing, conflict, state, ambiguousTransfer
    var errorDescription: String? {
        switch self {
        case .permission: "提醒事项访问未获授权。请在系统设置中允许朝夕访问。 / Reminders access is not authorized."
        case .unavailable: "所选提醒事项清单暂不可用，请刷新后重试。 / The selected list is unavailable."
        case .readOnly: "这个提醒事项清单不允许修改。 / This list is read-only."
        case .missing: "这条提醒事项已删除或移出所选清单，未重新创建。 / The reminder is no longer available."
        case .conflict: "这条提醒事项已再次变化，请重新打开后操作。 / The reminder changed again."
        case .state: "提醒事项连接数据无法保存或读取，操作已停止。 / Cannot read or save connection data."
        case .ambiguousTransfer: "转入结果尚不确定，为避免重复创建，请刷新后检查。 / Transfer result is uncertain; refresh before retrying."
        }
    }
}

@MainActor protocol ReminderStoreProtocol: AnyObject {
    var access: ReminderAccess { get }
    var changed: (() -> Void)? { get set }
    func authorize() async throws -> Bool
    func lists() throws -> [ReminderList]
    func fetch(lists: Set<String>) async throws -> [ReminderValue]
    func get(_ id: String) throws -> ReminderValue?
    func create(title: String, completed: Bool, list: String, marker: String?) throws -> ReminderValue
    func mutate(_ expected: ReminderValue, change: ReminderMutation) throws
}

/// All EK objects stay on the main actor; only value snapshots enter the UI/cache.
@MainActor final class AppleReminderStore: ReminderStoreProtocol {
    private let store = EKEventStore()
    var changed: (() -> Void)?
    nonisolated(unsafe) private var observer: NSObjectProtocol?
    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.changed?() }
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    var access: ReminderAccess {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: .allowed
        case .notDetermined: .unknown
        default: .denied
        }
    }
    func authorize() async throws -> Bool { try await store.requestFullAccessToReminders() }
    private func check() throws { guard access == .allowed else { throw ReminderFailure.permission } }
    func lists() throws -> [ReminderList] {
        try check()
        return store.calendars(for: .reminder).map { .init(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title, writable: $0.allowsContentModifications) }
    }
    func fetch(lists ids: Set<String>) async throws -> [ReminderValue] {
        try check()
        guard !ids.isEmpty else { return [] }
        let calendars = store.calendars(for: .reminder).filter { ids.contains($0.calendarIdentifier) }
        guard Set(calendars.map(\.calendarIdentifier)) == ids else { throw ReminderFailure.unavailable }
        let predicate = store.predicateForReminders(in: calendars)
        return try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                guard let reminders else { continuation.resume(throwing: ReminderFailure.unavailable); return }
                continuation.resume(returning: reminders.map(Self.value))
            }
        }
    }
    func get(_ id: String) throws -> ReminderValue? {
        try check()
        return (store.calendarItem(withIdentifier: id) as? EKReminder).map(Self.value)
    }
    func create(title: String, completed: Bool, list: String, marker: String?) throws -> ReminderValue {
        try check()
        guard let calendar = store.calendar(withIdentifier: list) else { throw ReminderFailure.unavailable }
        guard calendar.allowsContentModifications else { throw ReminderFailure.readOnly }
        let item = EKReminder(eventStore: store)
        item.calendar = calendar; item.title = title; item.isCompleted = completed
        if let marker { item.url = URL(string: marker) }
        try store.save(item, commit: true)
        return Self.value(item)
    }
    func mutate(_ expected: ReminderValue, change: ReminderMutation) throws {
        try check()
        guard let item = store.calendarItem(withIdentifier: expected.id) as? EKReminder else { throw ReminderFailure.missing }
        guard item.calendar.calendarIdentifier == expected.listID else { throw ReminderFailure.conflict }
        guard item.calendar.allowsContentModifications else { throw ReminderFailure.readOnly }
        let latest = Self.value(item)
        switch change {
        case .title(let title):
            guard latest.title == expected.title else { throw ReminderFailure.conflict }; item.title = title
        case .completed(let completed):
            guard latest.completed == expected.completed else { throw ReminderFailure.conflict }; item.isCompleted = completed
        case .delete:
            guard latest == expected else { throw ReminderFailure.conflict }
            try store.remove(item, commit: true); return
        }
        // Preserve due dates, alarms, recurrence, notes, URLs and all untouched fields.
        try store.save(item, commit: true)
    }
    nonisolated private static func value(_ item: EKReminder) -> ReminderValue {
        .init(id: item.calendarItemIdentifier, externalID: item.calendarItemExternalIdentifier,
              listID: item.calendar.calendarIdentifier, title: item.title ?? "", completed: item.isCompleted,
              due: item.dueDateComponents, marker: item.url?.absoluteString, modified: item.lastModifiedDate)
    }
}

struct ReminderLink: Codable, Equatable {
    var date: String
    var blockID: UUID
}
struct ReminderIdentity: Codable {
    var itemID: String
    var externalID: String?
    var listID: String
}
struct ReminderTransfer: Codable {
    var marker: String
    var listID: String
    var itemID: String?
    var finished = false
    var attempted = false
    var localBackup: TodoItem?
}
struct ReminderConnection: Codable {
    var version = 1
    var enabled = false
    var selected: Set<String> = []
    var defaultList: String?
    var lists: [ReminderList] = []
    var cache: [ReminderValue] = []
    var identities: [String: ReminderIdentity] = [:]
    var links: [String: ReminderLink] = [:]
    var transfers: [String: ReminderTransfer] = [:]
}
@MainActor protocol ReminderPersistence {
    func load() throws -> ReminderConnection
    func save(_ value: ReminderConnection) throws
}
struct ReminderFile: ReminderPersistence {
    let directory: URL
    var url: URL { directory.appendingPathComponent("reminders-connection-v1.json") }
    func load() throws -> ReminderConnection {
        guard FileManager.default.fileExists(atPath: url.path) else { return ReminderConnection() }
        let state = try JSONDecoder().decode(ReminderConnection.self, from: Data(contentsOf: url))
        guard state.version == 1 else { throw ReminderFailure.state }; return state
    }
    func save(_ value: ReminderConnection) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
