import Foundation
import Testing
@testable import QuotaCore

@Test func snapshotStorePersistsOnlySanitizedQuotaModel() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = SnapshotStore(directory: directory)
    let snapshot = QuotaSnapshot(state: .live, source: .appServer, observedAt: Date(timeIntervalSince1970: 100), windows: [
        QuotaWindow(kind: .primary, usedPercent: 30, windowDurationMinutes: 300, resetsAt: Date(timeIntervalSince1970: 200)),
    ])
    try store.save(snapshot: snapshot)
    #expect(store.loadSnapshot() == snapshot)

    let text = try String(contentsOf: store.snapshotURL, encoding: .utf8)
    #expect(!text.localizedCaseInsensitiveContains("token"))
    #expect(!text.localizedCaseInsensitiveContains("email"))
    #expect(!text.localizedCaseInsensitiveContains("account"))
}
