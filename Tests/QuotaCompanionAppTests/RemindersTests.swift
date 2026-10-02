import Foundation
import Testing
import QuotaCore
@testable import QuotaCompanionApp

@MainActor final class MemoryReminderPersistence: ReminderPersistence {
    var value = ReminderConnection()
    var fails = false
    func load() throws -> ReminderConnection { value }
    func save(_ value: ReminderConnection) throws {
        if fails { throw ReminderFailure.state }
        self.value = value
    }
}
@MainActor final class FakeReminderStore: ReminderStoreProtocol {
    var access: ReminderAccess = .allowed
    var changed: (() -> Void)?
    var authorizeCount = 0
    var fetches: [Set<String>] = []
    var calendarList: [ReminderList] = [
        .init(id: "work", title: "示例：工作", account: "测试账户", writable: true),
        .init(id: "personal", title: "示例：生活", account: "测试账户", writable: true),
        .init(id: "readonly", title: "示例：只读", account: "测试账户", writable: false)
    ]
    var items: [ReminderValue] = []
    var fetchFails = false
    var createCount = 0
    var throwAfterCreate = false
    var createsBeforeFailure: Int?
    var mutateCount = 0
    var onFetch: (() async -> Void)?
    var afterMutation: (() -> Void)?
    func authorize() async throws -> Bool { authorizeCount += 1; return access == .allowed }
    func lists() throws -> [ReminderList] { calendarList }
    func fetch(lists: Set<String>) async throws -> [ReminderValue] {
        fetches.append(lists)
        if fetchFails { throw ReminderFailure.unavailable }
        let snapshot = items.filter { lists.contains($0.listID) }
        if let onFetch { await onFetch() }
        return snapshot
    }
    func get(_ id: String) throws -> ReminderValue? { items.first { $0.id == id } }
    func create(title: String, completed: Bool, list: String, marker: String?) throws -> ReminderValue {
        if let limit = createsBeforeFailure, createCount >= limit { throw ReminderFailure.unavailable }
        createCount += 1
        let item = ReminderValue(id: UUID().uuidString, externalID: nil, listID: list, title: title, completed: completed, marker: marker)
        items.append(item)
        if throwAfterCreate { throw ReminderFailure.unavailable }
        return item
    }
    func mutate(_ expected: ReminderValue, change: ReminderMutation) throws {
        guard let i = items.firstIndex(where: { $0.id == expected.id }) else { throw ReminderFailure.missing }
        mutateCount += 1
        switch change {
        case .title(let title): items[i].title = title
        case .completed(let completed): items[i].completed = completed
        case .delete: items.remove(at: i)
        }
        afterMutation?()
    }
}

@Suite(.serialized) @MainActor struct RemindersTests {
    func fixture() -> (RemindersModel, FakeReminderStore, MemoryReminderPersistence) {
        let provider = FakeReminderStore(), persistence = MemoryReminderPersistence()
        let model = RemindersModel(directory: .temporaryDirectory, provider: provider, persistence: persistence)
        return (model, provider, persistence)
    }
    func connected() async -> (RemindersModel, FakeReminderStore, MemoryReminderPersistence) {
        let (model, provider, persistence) = fixture()
        await model.setEnabled(true); await model.select("work", selected: true)
        return (model, provider, persistence)
    }
    @Test func offByDefaultAndAuthorizationDenial() async {
        let (model, store, _) = fixture()
        await model.refresh()
        #expect(!model.enabled && store.fetches.isEmpty && store.authorizeCount == 0)
        store.access = .denied; await model.setEnabled(true)
        #expect(!model.enabled && store.authorizeCount == 1 && !model.error.isEmpty)
    }
    @Test func selectedListsOnlyAndDefaultSurvivesRestart() async {
        let (model, store, persistence) = await connected()
        #expect(store.fetches.last == ["work"])
        #expect(model.state.defaultList == "work")
        store.items = [.init(id: "1", listID: "work", title: "Task", completed: false), .init(id: "2", listID: "personal", title: "Private", completed: false)]
        await model.refresh()
        #expect(model.visibleItems.map(\.id) == ["1"])
        await model.setEnabled(false)
        #expect(store.items.count == 2 && model.state.cache.count == 1 && model.visibleItems.isEmpty)
        let reopened = RemindersModel(directory: .temporaryDirectory, provider: store, persistence: persistence)
        #expect(!reopened.enabled && reopened.state.selected == ["work"] && reopened.state.defaultList == "work")
    }
    @Test func permissionsAndMissingListsPreserveCacheAndLinks() async {
        let (model, store, _) = await connected()
        let item = ReminderValue(id: "1", listID: "work", title: "Task", completed: false)
        store.items = [item]; await model.refresh()
        let link = ReminderLink(date: "2026-09-24", blockID: UUID())
        model.setLink(item, link: link)
        store.access = .denied; await model.refresh()
        #expect(!model.usable && model.visibleItems == [item] && model.link(for: item) == link)
        model.error = ""; await model.refresh(); #expect(model.error.isEmpty) // One modal per failure episode.
        store.access = .allowed; store.calendarList.removeAll { $0.id == "work" }; await model.refresh()
        #expect(!model.canWrite("work") && model.visibleItems == [item] && model.link(for: item) == link)
        store.fetchFails = true; await model.refresh(); #expect(!model.usable && model.state.cache == [item])
    }
    @Test func selectedListDeselectDoesNotDelete() async {
        let (model, store, _) = await connected()
        store.items = [.init(id: "1", listID: "work", title: "Task", completed: false)]
        await model.refresh(); await model.select("work", selected: false)
        #expect(store.items.count == 1 && model.state.cache.count == 1 && model.visibleItems.isEmpty && model.state.defaultList == nil)
    }
    @Test func twoWayFieldsConflictsAndDeletion() async {
        let (model, store, _) = await connected()
        #expect(await model.create("Task", list: "work"))
        let shown = model.visibleItems[0]
        store.items[0].due = DateComponents(year: 2026, month: 9, day: 25, hour: 9)
        store.items[0].title = "Remote title"
        var confirmations = 0
        #expect(!(await model.mutate(shown, change: .title("Local title"), confirm: { _ in confirmations += 1; return false })))
        #expect(confirmations == 1 && store.items[0].title == "Remote title")
        #expect(await model.mutate(shown, change: .title("Local title"), confirm: { _ in true }))
        #expect(store.items[0].title == "Local title" && store.items[0].due?.hour == 9)
        #expect(await model.mutate(model.visibleItems[0], change: .completed(true), confirm: { _ in false }))
        #expect(model.visibleItems[0].completed)
        #expect(await model.mutate(model.visibleItems[0], change: .completed(false), confirm: { _ in false }))
        #expect(!model.visibleItems[0].completed)
        let current = model.visibleItems[0]
        #expect(await model.mutate(current, change: .delete, confirm: { _ in true }))
        #expect(model.visibleItems.isEmpty)
        #expect(!(await model.mutate(current, change: .title("Recreate?"), confirm: { _ in true })))
        #expect(store.createCount == 1)
    }
    @Test func readOnlyAndPersistenceFailureDoNotWrite() async {
        let (model, store, persistence) = await connected()
        await model.select("readonly", selected: true)
        #expect(!(await model.create("Blocked", list: "readonly")) && store.createCount == 0)
        persistence.fails = true
        await model.select("personal", selected: true)
        #expect(!model.state.selected.contains("personal"))
        await model.setEnabled(false); #expect(model.enabled)
    }
    @Test func externalIdentifierRemapPreservesAssociationWithoutGuessingTitles() async {
        let (model, store, _) = await connected()
        var item = ReminderValue(id: "old", externalID: "stable", listID: "work", title: "Same", completed: false)
        store.items = [item]; await model.refresh()
        let link = ReminderLink(date: "2026-09-24", blockID: UUID()); model.setLink(item, link: link)
        item.id = "new"; store.items = [item]; await model.refresh()
        #expect(model.link(for: item) == link)
        let unrelated = ReminderValue(id: "other", listID: "work", title: "Same", completed: false)
        store.items.append(unrelated); await model.refresh(); #expect(model.link(for: unrelated) == nil)
    }
    @Test func migrationRetryAfterUncertainSaveDoesNotDuplicateAndPreservesLink() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let secretary = SecretaryModel(directory: root)
        var item = TodoItem(title: "Example"); item.date = "2026-09-24"; item.blockID = UUID()
        #expect(secretary.commit { $0.todos = [item] })
        let (model, store, persistence) = await connected()
        store.throwAfterCreate = true
        await model.transfer([item], to: "work", secretary: secretary)
        #expect(secretary.data.todos.count == 1 && store.createCount == 1)
        store.throwAfterCreate = false
        let reopened = RemindersModel(directory: .temporaryDirectory, provider: store, persistence: persistence)
        await reopened.refresh(); await reopened.transfer([item], to: "work", secretary: secretary)
        #expect(store.createCount == 1 && secretary.data.todos.isEmpty)
        #expect(reopened.link(for: store.items[0])?.blockID == item.blockID)
        #expect(reopened.state.transfers[item.id.uuidString]?.finished == true)
    }
    @Test func migrationPartialFailureLeavesFailedItemsLocalAndStopsBlindRetry() async {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let secretary = SecretaryModel(directory: root)
        let items = [TodoItem(title: "One"), TodoItem(title: "Two")]
        #expect(secretary.commit { $0.todos = items })
        let (model, store, _) = await connected(); store.createsBeforeFailure = 1
        await model.transfer(items, to: "work", secretary: secretary)
        #expect(store.items.count == 1 && secretary.data.todos == [items[1]])
        store.createsBeforeFailure = nil
        await model.transfer(items, to: "work", secretary: secretary)
        #expect(store.createCount == 1 && secretary.data.todos == [items[1]])
    }
    @Test func fileRoundTripDoesNotTouchScheduleAndRejectsCorruption() throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = ReminderFile(directory: root)
        var state = ReminderConnection(); state.enabled = true; state.selected = ["work"]
        try file.save(state); #expect(try file.load().selected == ["work"])
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("secretary-v2.json").path))
        state.version = 99; try file.save(state); #expect(throws: (any Error).self) { try file.load() }
    }
    @Test func disableDuringFetchRejectsLateSnapshot() async {
        let (model, store, _) = await connected()
        store.items = [.init(id: "1", listID: "work", title: "Late", completed: false)]
        store.onFetch = { await model.setEnabled(false) }
        await model.refresh()
        #expect(!model.enabled && model.state.cache.isEmpty && !model.usable)
    }
    @Test func recurrenceCompletionRefetchAndExternalDeletionDoNotRecreate() async {
        let (model, store, _) = await connected()
        let current = ReminderValue(id: "first", listID: "work", title: "Repeating example", completed: false)
        store.items = [current]; await model.refresh()
        store.afterMutation = { store.items.append(.init(id: "next", listID: "work", title: "Repeating example", completed: false)) }
        #expect(await model.mutate(current, change: .completed(true), confirm: { _ in false }))
        #expect(model.visibleItems.contains { $0.id == "next" && !$0.completed })
        store.items = []; await model.refresh()
        #expect(model.visibleItems.isEmpty && store.createCount == 0)
        store.afterMutation = nil
    }
    @Test func linkOnlyChangesLocalStateAndReconcilesOnlyDeletedSchedule() async {
        let (model, store, _) = await connected()
        let item = ReminderValue(id: "one", listID: "work", title: "Example", completed: false, due: DateComponents(year: 2026, month: 10, day: 1))
        store.items = [item]; await model.refresh()
        let date = SecretaryData.date("2026-09-24")!
        let event = ScheduleBlock(start: 540, end: 600, title: "Slot")
        var data = SecretaryData(); data.exceptions["2026-09-24"] = [event]
        model.setLink(item, link: .init(date: "2026-09-24", blockID: event.id))
        model.reconcileLinks(data)
        #expect(model.link(for: item)?.blockID == event.id && store.items == [item] && store.mutateCount == 0)
        data.exceptions["2026-09-24"] = []; model.reconcileLinks(data)
        #expect(model.link(for: item) == nil && store.items == [item])
        #expect(data.blocks(on: date).isEmpty)
    }
}
