import Foundation

enum PersonalVoiceState: String, Codable { case pending, created, verified, deleted }
struct PersonalVoice: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var provider: APIProvider
    var remoteID: String?
    var model: String
    var name: String
    var createdAt = Date()
    var state: PersonalVoiceState = .pending
    var credentialRevision: String
    var operationName: String
    var warning: String?
    var deletionPending: Bool?
    static func model(for provider: APIProvider) -> String { provider == .bailian ? "qwen3-tts-vc-2026-01-22" : "speech-2.8-turbo" }
    init(provider: APIProvider, name: String, revision: String) {
        self.provider = provider; self.name = name; credentialRevision = revision
        model = Self.model(for: provider)
        operationName = "zx" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(14)
        if provider == .minimax { remoteID = operationName }
    }
    static func validName(_ value: String) -> Bool { let s = value.trimmingCharacters(in: .whitespacesAndNewlines); return !s.isEmpty && s.count <= 30 }
    var selectionID: String { "personal:" + id.uuidString }
    var descriptor: SpeechVoiceDescriptor? {
        guard let remoteID, !remoteID.isEmpty else { return nil }
        return .init(provider: provider, id: remoteID, model: model, personal: true)
    }
}
struct SpeechVoiceDescriptor: Equatable, Sendable {
    var provider: APIProvider
    var id: String
    var model: String
    var personal = false
}

/// Contains metadata only, never samples, API keys or user announcement text.
/// Written before a remote mutation, so an uncertain result cannot trigger a duplicate create.
@MainActor final class VoiceRecoveryStore {
    private let url: URL?
    private(set) var entries: [PersonalVoice] = []
    private(set) var unreadable = false
    init(directory: URL?) {
        url = directory?.appendingPathComponent("voice-operations-v1.json")
        if let url, FileManager.default.fileExists(atPath: url.path) {
            do {
                let decoded = try JSONDecoder().decode([PersonalVoice].self, from: Data(contentsOf: url))
                guard Set(decoded.map(\.id)).count == decoded.count else { throw SpeechConfigError.storage }
                entries = decoded
            }
            catch { unreadable = true }
        }
    }
    func put(_ entry: PersonalVoice) throws {
        guard !unreadable else { throw SpeechConfigError.storage }
        var next = entries; next.removeAll { $0.id == entry.id }; next.append(entry)
        try write(next); entries = next
    }
    func remove(_ id: UUID) throws {
        guard !unreadable else { throw SpeechConfigError.storage }
        let next = entries.filter { $0.id != id }; try write(next); entries = next
    }
    private func write(_ entries: [PersonalVoice]) throws {
        guard let url else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }
}
