import Foundation

public struct SnapshotStore: Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.directory = base.appendingPathComponent("QuotaCompanion", isDirectory: true)
        }
    }

    public var snapshotURL: URL { directory.appendingPathComponent("quota-snapshot.json") }
    public var thresholdURL: URL { directory.appendingPathComponent("threshold-state.json") }
    public var socketURL: URL { directory.appendingPathComponent("quota.sock") }

    public func loadSnapshot() -> QuotaSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? Self.decoder.decode(QuotaSnapshot.self, from: data)
    }

    public func save(snapshot: QuotaSnapshot) throws {
        try prepareDirectory()
        let sanitized = QuotaSnapshot(
            state: snapshot.state,
            source: snapshot.source,
            observedAt: snapshot.observedAt,
            windows: snapshot.windows
        )
        try Self.encoder.encode(sanitized).write(to: snapshotURL, options: [.atomic])
    }

    public func loadThresholdTracker() -> ThresholdTracker {
        guard let data = try? Data(contentsOf: thresholdURL),
              let value = try? Self.decoder.decode(ThresholdTracker.self, from: data) else { return ThresholdTracker() }
        return value
    }

    public func save(thresholdTracker: ThresholdTracker) throws {
        try prepareDirectory()
        try Self.encoder.encode(thresholdTracker).write(to: thresholdURL, options: [.atomic])
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
