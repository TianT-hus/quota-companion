import Foundation
import Combine
import QuotaCore

enum APIProvider: String, Codable, CaseIterable, Sendable {
    case bailian, minimax
    var name: String { self == .bailian ? "百炼 / Bailian" : "MiniMax" }
    var endpoint: String { self == .bailian ? BailianSpeechClient.endpoint.absoluteString : "https://api.minimax.cn/v1/t2a_v2" }
    static func identify(_ address: String) -> APIProvider? {
        guard let u = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)), u.scheme == "https", u.user == nil, u.password == nil, u.port == nil, u.query == nil, u.fragment == nil else { return nil }
        if u.host == "dashscope.aliyuncs.com", u.path == "/api/v1/services/aigc/multimodal-generation/generation" { return .bailian }
        if ["api.minimax.cn", "api-bj.minimaxi.com"].contains(u.host ?? ""), u.path == "/v1/t2a_v2" { return .minimax }
        return nil
    }
}
enum SpeechTemplateKind: String, Codable, CaseIterable { case schedule, quota }
enum SpeechToken: String, Codable, CaseIterable {
    case now, start, end, event, quota, percent
    func title(_ c: Copybook) -> String {
        switch self {
        case .now: c.text("当前时间", "Current time")
        case .start: c.text("开始时间", "Start time")
        case .end: c.text("结束时间", "End time")
        case .event: c.text("事项", "Event")
        case .quota: c.text("额度类型", "Quota type")
        case .percent: c.text("实际剩余百分比", "Remaining percent")
        }
    }
}
struct SpeechPiece: Codable, Equatable, Identifiable {
    var id = UUID()
    var token: SpeechToken?
    var text = ""
    static func words(_ s: String) -> Self { .init(text: s) }
    static func value(_ t: SpeechToken) -> Self { .init(token: t) }
}
struct SpeechTemplate: Codable, Equatable {
    var kind: SpeechTemplateKind
    var pieces: [SpeechPiece]
    static func standard(_ kind: SpeechTemplateKind, chinese: Bool) -> Self {
        let p: [SpeechPiece]
        if kind == .schedule {
            p = [.words(chinese ? "现在是" : "It is now "), .value(.now), .words(chinese ? "，" : ". From "), .value(.start), .words(chinese ? "到" : " to "), .value(.end), .words(chinese ? "是" : ", "), .value(.event), .words(chinese ? "时间。" : ".")]
        } else { p = [.value(.quota), .words(chinese ? "当前剩余" : " has "), .value(.percent), .words(chinese ? "。" : " remaining.")] }
        return .init(kind: kind, pieces: p)
    }
    var availableTokens: [SpeechToken] { kind == .schedule ? [.now,.start,.end,.event] : [.quota,.percent] }
    var normalizedPieces: [SpeechPiece] {
        var result: [SpeechPiece] = []
        for piece in pieces {
            if piece.token != nil { result.append(piece) }
            else if !piece.text.isEmpty {
                if result.last?.token == nil, !result.isEmpty { result[result.count-1].text += piece.text }
                else { result.append(piece) }
            }
        }
        return result
    }
    func validate() throws {
        let normalized = normalizedPieces
        guard normalized.contains(where: { $0.token != nil || !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(normalized.compactMap(\.token)).isSubset(of: Set(availableTokens)),
              normalized.count <= 40, normalized.map(\.text).joined().count <= 400 else { throw SpeechConfigError.invalidTemplate }
    }
    func example(_ c: Copybook, language: SpeechLanguage = .chinese) -> String {
        let values: [SpeechToken: String] = [.now: SpokenTime.format(780, language: language), .start: SpokenTime.format(780, language: language), .end: SpokenTime.format(1050, language: language), .event: c.text("整理资料", "Organize documents"), .quota: c.text("5h 额度", "5-hour quota"), .percent: "10%"]
        return pieces.map { $0.token.flatMap { values[$0] } ?? $0.text }.joined()
    }
}
enum QuotaDelivery: String, Codable, CaseIterable {
    case notification, speech, both
    var notification: Bool { self != .speech }
    var spoken: Bool { self != .notification }
    func title(_ c: Copybook) -> String { switch self { case .notification: c.text("系统通知", "Notification"); case .speech: c.text("语音", "Speech"); case .both: c.text("两者", "Both") } }
}
struct QuotaSpeechRule: Codable, Equatable {
    var enabled = true
    var thresholds = [30,15,5]
    var delivery: QuotaDelivery = .notification
    static func parse(_ text: String) throws -> [Int] {
        let fields = text.components(separatedBy: CharacterSet(charactersIn: ",，、 ")) .filter { !$0.isEmpty }
        guard !fields.isEmpty, fields.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) && Int($0).map { (0...100).contains($0) } == true }) else { throw SpeechConfigError.invalidThreshold }
        return Array(Set(fields.compactMap(Int.init))).sorted(by: >)
    }
}
struct SpeechConfiguration: Codable, Equatable {
    var version = 3
    var provider: APIProvider = .bailian
    var endpoints: [String: String] = [:]
    var voices: [String: String] = [:]
    var consented: Set<APIProvider> = []
    var templates: [String: SpeechTemplate] = [:]
    var quota = QuotaSpeechRule()
    var personalVoices: [PersonalVoice]?
    var credentialRevisions: [String: String]?
    var voiceLibrary: [PersonalVoice] { personalVoices ?? [] }
    func credentialRevision(_ provider: APIProvider) -> String { credentialRevisions?[provider.rawValue] ?? "legacy" }
}
enum SpeechConfigError: Error { case invalidTemplate, invalidThreshold, invalidAddress, storage, translationUnavailable, translationTimeout }

@MainActor final class SpeechConfigurationStore: ObservableObject {
    @Published private(set) var value: SpeechConfiguration
    private let url: URL?
    private var loadFailed = false
    let directory: URL?
    init(directory: URL?, defaults: UserDefaults) {
        self.directory = directory
        url = directory?.appendingPathComponent("speech-settings-v3.json")
        let v2 = directory?.appendingPathComponent("speech-settings-v2.json")
        let legacy = directory?.appendingPathComponent("speech-settings-v1.json")
        let source = [url, v2, legacy].compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
        if let source, FileManager.default.fileExists(atPath: source.path) {
            do {
                value = try JSONDecoder().decode(SpeechConfiguration.self, from: Data(contentsOf: source))
                guard value.version == (source == url ? 3 : (source == v2 ? 2 : 1)) else { throw SpeechConfigError.storage }
                value.version = 3
                guard Set(value.voiceLibrary.map(\.id)).count == value.voiceLibrary.count,
                      value.voiceLibrary.allSatisfy({ PersonalVoice.validName($0.name) && $0.model == PersonalVoice.model(for: $0.provider) }) else { throw SpeechConfigError.storage }
                for template in value.templates.values { try template.validate() }
                guard !value.quota.thresholds.isEmpty, value.quota.thresholds.allSatisfy({ (0...100).contains($0) }) else { throw SpeechConfigError.storage }
            } catch { value = SpeechConfiguration(); value.quota.enabled = false; loadFailed = true }
        } else {
            value = SpeechConfiguration()
            value.quota.delivery = defaults.bool(forKey: "speechEnabled") ? .both : .notification
            if defaults.bool(forKey: "speech.cloud.consent.v1") { value.consented.insert(.bailian) }
        }
    }
    func save(_ candidate: SpeechConfiguration) throws {
        guard !loadFailed else { throw SpeechConfigError.storage }
        guard candidate.version == 3 else { throw SpeechConfigError.storage }
        guard Set(candidate.voiceLibrary.map(\.id)).count == candidate.voiceLibrary.count,
              candidate.voiceLibrary.allSatisfy({ PersonalVoice.validName($0.name) && $0.model == PersonalVoice.model(for: $0.provider) }) else { throw SpeechConfigError.storage }
        for t in candidate.templates.values { try t.validate() }
        guard !candidate.quota.thresholds.isEmpty, candidate.quota.thresholds.allSatisfy({ (0...100).contains($0) }) else { throw SpeechConfigError.invalidThreshold }
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let migration225 = url.deletingLastPathComponent().appendingPathComponent("before-speech-0225")
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: migration225, withIntermediateDirectories: true)
                for name in ["speech-settings-v2.json", "speech-settings-v1.json"] {
                    let old = url.deletingLastPathComponent().appendingPathComponent(name), backup = migration225.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: old.path), !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: old, to: backup) }
                }
            }
            let legacy = url.deletingLastPathComponent().appendingPathComponent("speech-settings-v1.json")
            let migration = url.deletingLastPathComponent().appendingPathComponent("before-speech-0224")
            if !FileManager.default.fileExists(atPath: url.path), FileManager.default.fileExists(atPath: legacy.path) {
                try FileManager.default.createDirectory(at: migration, withIntermediateDirectories: true)
                let backup = migration.appendingPathComponent(legacy.lastPathComponent)
                if !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: legacy, to: backup) }
            }
            let backup = url.deletingLastPathComponent().appendingPathComponent("before-speech-0215")
            let completed = backup.appendingPathComponent("complete")
            if !FileManager.default.fileExists(atPath: completed.path) {
                try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
                for name in ["speech-settings-v1.json", "secretary-v1.json", "threshold-state.json"] {
                    let original = url.deletingLastPathComponent().appendingPathComponent(name)
                    let destination = backup.appendingPathComponent(name)
                    if FileManager.default.fileExists(atPath: original.path), !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.copyItem(at: original, to: destination) }
                }
                try Data("0.2.15".utf8).write(to: completed, options: .atomic)
            }
            try JSONEncoder().encode(candidate).write(to: url, options: .atomic)
        }
        value = candidate
    }
}
