import AppKit
import Combine
import QuotaCore

@MainActor final class RemindersModel: ObservableObject {
    @Published private(set) var state = ReminderConnection()
    @Published private(set) var availableLists: [ReminderList] = []
    @Published private(set) var usable = false
    @Published private(set) var busy = false
    @Published var error = ""
    private let provider: any ReminderStoreProtocol
    private let persistence: any ReminderPersistence
    private var broken = false
    private var errorLatch = ""
    private var generation = 0
    private var refreshTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    init(directory: URL, provider: (any ReminderStoreProtocol)? = nil, persistence: (any ReminderPersistence)? = nil) {
        self.provider = provider ?? AppleReminderStore()
        self.persistence = persistence ?? ReminderFile(directory: directory)
        do { state = try self.persistence.load() } catch { broken = true; self.error = ReminderFailure.state.localizedDescription }
        self.provider.changed = { [weak self] in self?.scheduleRefresh() }
    }
    var enabled: Bool { state.enabled }
    var visibleItems: [ReminderValue] { enabled ? state.cache.filter { state.selected.contains($0.listID) } : [] }
    var selectedLists: [ReminderList] { enabled ? state.lists.filter { state.selected.contains($0.id) } : [] }
    var writableLists: [ReminderList] { usable ? availableLists.filter { state.selected.contains($0.id) && $0.writable } : [] }
    func canWrite(_ list: String) -> Bool { enabled && usable && !broken && state.selected.contains(list) && availableLists.contains { $0.id == list && $0.writable } }
    func start() {
        guard observers.isEmpty else { return }
        self.provider.changed = { [weak self] in self?.scheduleRefresh() }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        })
        scheduleRefresh()
    }
    func stop() {
        generation += 1
        refreshTask?.cancel(); refreshTask = nil
        provider.changed = nil
        usable = false
        for observer in observers { NotificationCenter.default.removeObserver(observer); NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
    }
    func scheduleRefresh() {
        guard enabled else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }
    private func persist(_ next: ReminderConnection) throws {
        guard !broken else { throw ReminderFailure.state }
        try persistence.save(next); state = next
    }
    func report(_ cause: Error) {
        let message = (cause as? ReminderFailure)?.localizedDescription ?? "提醒事项操作未完成，请检查授权、账户连接及磁盘空间后重试。 / Reminders operation failed. Check access, account connection and disk space."
        if message != errorLatch { errorLatch = message; error = message }
    }
    private func recovered() { errorLatch = "" }
    func setEnabled(_ value: Bool) async {
        guard !busy else { return }
        errorLatch = ""
        busy = true; defer { busy = false }
        do {
            if value {
                guard !broken else { throw ReminderFailure.state }
                if provider.access != .allowed {
                    guard try await provider.authorize() else { throw ReminderFailure.permission }
                }
            }
            generation += 1
            var next = state; next.enabled = value
            try persist(next); usable = false
            if value { await refresh() }
            else { refreshTask?.cancel() }
        } catch { report(error) }
    }
    func select(_ list: String, selected: Bool) async {
        guard !busy, enabled else { return }
        errorLatch = ""
        busy = true; defer { busy = false }
        do {
            var next = state
            if selected { next.selected.insert(list) } else { next.selected.remove(list) }
            if let defaultList = next.defaultList, !next.selected.contains(defaultList) { next.defaultList = nil }
            if next.defaultList == nil { next.defaultList = availableLists.first { next.selected.contains($0.id) && $0.writable }?.id }
            generation += 1; try persist(next); await refresh()
        } catch { report(error) }
    }
    func setDefault(_ list: String?) {
        errorLatch = ""
        do {
            guard list == nil || canWrite(list!) else { throw ReminderFailure.unavailable }
            var next = state; next.defaultList = list; try persist(next)
        } catch { report(error) }
    }
    func refresh(userInitiated: Bool = false) async {
        guard enabled, !broken else { return }
        if userInitiated { errorLatch = "" }
        generation += 1
        let ticket = generation
        do {
            guard provider.access == .allowed else { throw ReminderFailure.permission }
            let lists = try provider.lists()
            availableLists = lists
            let availableIDs = Set(lists.map(\.id))
            let requested = state.selected.intersection(availableIDs)
            let values = try await provider.fetch(lists: requested)
            guard ticket == generation, enabled, !Task.isCancelled else { return }
            guard provider.access == .allowed else { throw ReminderFailure.permission }
            var next = state
            // Missing/unselected lists retain their cached data and associations.
            next.lists = lists + state.lists.filter { !availableIDs.contains($0.id) }
            next.cache.removeAll { requested.contains($0.listID) }
            next.cache.append(contentsOf: values.filter { requested.contains($0.listID) })
            for item in values { _ = identity(for: item, in: &next) }
            try persist(next); usable = true
            if !state.selected.isSubset(of: availableIDs) { report(ReminderFailure.unavailable) }
            else { recovered() }
        } catch {
            guard ticket == generation, enabled, !Task.isCancelled else { return }
            usable = false; report(error)
        }
    }
    private func identity(for item: ReminderValue, in next: inout ReminderConnection) -> String {
        let exact = next.identities.first { $0.value.itemID == item.id }?.key
        let external = item.externalID.flatMap { external -> String? in
            let matches = next.identities.filter { $0.value.externalID == external && $0.value.listID == item.listID }
            let fetched = next.cache.filter { $0.externalID == external && $0.listID == item.listID }
            return matches.count == 1 && fetched.count == 1 ? matches.first?.key : nil
        }
        let key = exact ?? external ?? UUID().uuidString
        next.identities[key] = .init(itemID: item.id, externalID: item.externalID, listID: item.listID)
        return key
    }
    func link(for item: ReminderValue) -> ReminderLink? {
        guard let key = state.identities.first(where: { $0.value.itemID == item.id })?.key else { return nil }
        return state.links[key]
    }
    func setLink(_ item: ReminderValue, link: ReminderLink?) {
        errorLatch = ""
        do {
            var next = state; let key = identity(for: item, in: &next)
            next.links[key] = link; try persist(next)
        } catch { report(error) }
    }
    func reconcileLinks(_ data: SecretaryData) {
        var next = state
        for (key, link) in next.links {
            if let date = SecretaryData.date(link.date), !data.blocks(on: date).contains(where: { $0.id == link.blockID }) { next.links[key] = nil }
        }
        guard next.links != state.links else { return }
        do { try persist(next) } catch { report(error) }
    }
    private func checkWrite(_ list: String) throws {
        guard provider.access == .allowed else { throw ReminderFailure.permission }
        guard canWrite(list) else { throw ReminderFailure.unavailable }
        guard try provider.lists().contains(where: { $0.id == list && $0.writable }) else { throw ReminderFailure.readOnly }
    }
    func create(_ title: String, list: String) async -> Bool {
        guard !busy, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        errorLatch = ""
        busy = true; defer { busy = false }
        do {
            try checkWrite(list)
            _ = try provider.create(title: title, completed: false, list: list, marker: nil)
            await refresh(); return true
        } catch { report(error); return false }
    }
    func mutate(_ shown: ReminderValue, change: ReminderMutation, confirm: (String) async -> Bool) async -> Bool {
        guard !busy else { return false }
        errorLatch = ""
        busy = true; defer { busy = false }
        do {
            try checkWrite(shown.listID)
            guard let latest = try provider.get(shown.id), latest.listID == shown.listID else { throw ReminderFailure.missing }
            let conflict: Bool
            switch change {
            case .title: conflict = latest.title != shown.title
            case .completed: conflict = latest.completed != shown.completed
            case .delete: conflict = latest != shown
            }
            if conflict, !(await confirm("这条提醒事项已在其他地方修改，是否仍按本次操作保存？ / This reminder changed elsewhere. Apply your change?")) { return false }
            try checkWrite(latest.listID)
            try provider.mutate(latest, change: change)
            await refresh(); return true
        } catch { report(error); return false }
    }
    /// Persist intent before external writes. Ambiguous saves never blindly create twice.
    func transfer(_ items: [TodoItem], to list: String, secretary: SecretaryModel) async {
        guard !busy else { return }
        errorLatch = ""
        busy = true; defer { busy = false }
        do {
            try checkWrite(list)
            for item in items {
                guard secretary.data.todos.contains(where: { $0.id == item.id }) else { continue }
                let key = item.id.uuidString
                var next = state
                if next.transfers[key] == nil {
                    next.transfers[key] = .init(marker: "zhaoxi-reminder-transfer://" + UUID().uuidString, listID: list, localBackup: item)
                    try persist(next)
                }
                var receipt = state.transfers[key]!
                guard receipt.listID == list else { throw ReminderFailure.ambiguousTransfer }
                try checkWrite(list)
                let all = try await provider.fetch(lists: [list])
                try checkWrite(list)
                guard secretary.data.todos.first(where: { $0.id == item.id }) == item else { throw ReminderFailure.conflict }
                let matches = all.filter { $0.marker == receipt.marker || $0.id == receipt.itemID }
                guard matches.count <= 1 else { throw ReminderFailure.ambiguousTransfer }
                let remote: ReminderValue
                if let found = matches.first { remote = found }
                else {
                    guard !receipt.attempted else { throw ReminderFailure.ambiguousTransfer }
                    receipt.attempted = true
                    next = state; next.transfers[key] = receipt; try persist(next)
                    remote = try provider.create(title: item.title, completed: item.completed, list: list, marker: receipt.marker)
                }
                receipt.itemID = remote.id
                next = state; next.transfers[key] = receipt
                let stableID = identity(for: remote, in: &next)
                if let date = item.date, let blockID = item.blockID { next.links[stableID] = .init(date: date, blockID: blockID) }
                try persist(next)
                // Remove local only after remote identity and link are durable.
                guard secretary.commit({ $0.todos.removeAll { $0.id == item.id } }) else {
                    secretary.error = ""; throw ReminderFailure.state
                }
                receipt.finished = true; next = state; next.transfers[key] = receipt; try persist(next)
            }
            await refresh()
        } catch { report(error); await refresh() }
    }
}
