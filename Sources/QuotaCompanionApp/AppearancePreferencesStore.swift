import Foundation
import QuotaCore

/// Independent atomic appearance snapshot; old preferences remain available for rollback.
@MainActor final class AppearancePreferencesStore {
    let url: URL
    var write: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    private var unreadable = false
    private let previousURL: URL
    init(directory: URL) {
        url = directory.appendingPathComponent("appearance-v3.json")
        previousURL = directory.appendingPathComponent("appearance-v2.json")
    }
    func load() -> CustomAppearance? {
        let source = FileManager.default.fileExists(atPath: url.path) ? url : previousURL
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        do {
            let value = try JSONDecoder().decode(CustomAppearance.self, from: Data(contentsOf: source))
            guard value.version == (source == url ? 3 : 2) else { throw CocoaError(.fileReadCorruptFile) }
            return value
        } catch { unreadable = true; return nil }
    }
    func save(_ value: CustomAppearance, legacy: Data?) throws {
        guard !unreadable else { throw CocoaError(.fileReadCorruptFile) }
        let data = try JSONEncoder().encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let backup = url.deletingLastPathComponent().appendingPathComponent("appearance-before-v3.json")
        if !FileManager.default.fileExists(atPath: backup.path) {
            let previous = FileManager.default.fileExists(atPath: previousURL.path) ? try Data(contentsOf: previousURL) : legacy
            if let previous { try write(previous, backup) }
        }
        try write(data, url)
    }
}
