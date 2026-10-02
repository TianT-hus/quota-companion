import Foundation
import Security
import QuotaCore

enum SpeechSource: String, CaseIterable { case local, bailian }
enum SpeechLanguage: String, CaseIterable {
    case chinese = "Chinese", english = "English", japanese = "Japanese"
    var code: String { switch self { case .chinese: "zh-Hans"; case .english: "en"; case .japanese: "ja" } }
    var title: String { switch self { case .chinese: "中文"; case .english: "English"; case .japanese: "日本語" } }
    var sample: String { switch self {
    case .chinese: "现在是十三点到十七点三十分，工作。"
    case .english: "From thirteen hundred to seventeen thirty, work."
    case .japanese: "十三時から十七時三十分まで、仕事です。"
    } }
    func announcement(_ block: ScheduleBlock) -> String {
        switch self {
        case .chinese: CompanionSpeech.announcement(block, chinese: true)
        case .english: "From \(ScheduleBlock.time(block.start)) to \(ScheduleBlock.time(block.end)), \(block.title)."
        case .japanese: "\(block.start / 60)時\(block.start % 60)分から\(block.end / 60)時\(block.end % 60)分まで、\(block.title)。"
        }
    }
}

struct BailianVoice: Identifiable {
    let id: String
    let title: String
    let languages: Set<SpeechLanguage>
    // Official Qwen3-TTS-Flash system voices; no cloning or external voice packages.
    static let catalog: [BailianVoice] = [
        .init(id: "Cherry", title: "芊悦 · Cherry", languages: Set(SpeechLanguage.allCases)),
        .init(id: "Ethan", title: "晨煦 · Ethan", languages: Set(SpeechLanguage.allCases)),
        .init(id: "Chelsie", title: "千雪 · Chelsie", languages: Set(SpeechLanguage.allCases)),
        .init(id: "Ono Anna", title: "小野杏 · Ono Anna", languages: Set(SpeechLanguage.allCases))
    ]
    static func available(_ language: SpeechLanguage) -> [BailianVoice] { catalog.filter { $0.languages.contains(language) } }
}

enum CloudSpeechError: Error { case missingKey, keychain, keychainPermission, invalidText, authorization, quota, network, timeout, response, audio }
extension CloudSpeechError {
    func message(_ c: Copybook) -> String {
        switch self {
        case .missingKey: c.text("请先保存所选平台的 API Key。", "Save an API key for the selected provider first.")
        case .keychain: c.text("无法访问钥匙串，密钥未更改。", "Keychain unavailable. The saved key was not changed.")
        case .keychainPermission: c.text("需要钥匙串授权，请主动点击 API 状态灯后在系统窗口中授权。密钥未丢失或更改。", "Keychain permission required. Click the API status light to authorize in the system dialog. The key was not removed or changed.")
        case .invalidText: c.text("播报文本为空或超过所选服务限制（百炼 600 字符，MiniMax 少于 10000 字符）。", "Speech is empty or exceeds the service limit (Bailian: 600 characters; MiniMax: fewer than 10000).")
        case .authorization: c.text("API 鉴权失败，请检查密钥和地域。", "API authentication failed. Check the key and region.")
        case .quota: c.text("API 额度不足或请求受限，请检查账户。", "API quota or rate limit reached. Check your account.")
        case .timeout: c.text("云端语音超过 10 秒未完成，本次不播报。", "Cloud speech timed out after 10 seconds. This alert will not be spoken.")
        case .network: c.text("云端语音连接失败，本次仅保留视觉提醒。", "Cloud connection failed. Only the visual alert remains.")
        case .response: c.text("API 返回了无法使用的音频结果。", "The API returned an unusable audio response.")
        case .audio: c.text("音频无法播放。", "Could not play the audio.")
        }
    }
}

@MainActor protocol SpeechCredentials {
    func read() throws -> String
    func save(_ value: String) throws
}
struct KeychainSpeechCredentials: SpeechCredentials {
    var provider: APIProvider = .bailian
    nonisolated private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "dev.quota-companion.\(provider.rawValue)", kSecAttrAccount as String: provider == .bailian ? "beijing-api-key" : "china-api-key",
        kSecAttrSynchronizable as String: false] }
    func read() throws -> String {
        try read(allowInteraction: true)
    }
    nonisolated func read(allowInteraction: Bool) throws -> String {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        if !allowInteraction { q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { throw CloudSpeechError.missingKey }
        if [errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled].contains(status) { throw CloudSpeechError.keychainPermission }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { throw CloudSpeechError.keychain }
        return key
    }
    nonisolated func presence() -> CredentialPresence {
        var q = query; q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        let status = SecItemCopyMatching(q as CFDictionary, nil)
        if status == errSecSuccess { return .saved }
        if status == errSecItemNotFound { return .missing }
        return .unknown
    }
    func save(_ value: String) throws {
        let attributes = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = Data(value.utf8)
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CloudSpeechError.keychain }
    }
}

protocol CloudSpeechSynthesizing: Sendable {
    func synthesize(text: String, language: SpeechLanguage, voice: String, key: String) async throws -> Data
    func synthesize(text: String, language: SpeechLanguage, descriptor: SpeechVoiceDescriptor, key: String) async throws -> Data
}
extension CloudSpeechSynthesizing {
    func synthesize(text: String, language: SpeechLanguage, descriptor: SpeechVoiceDescriptor, key: String) async throws -> Data {
        try await synthesize(text: text, language: language, voice: descriptor.id, key: key)
    }
}

final class NoSpeechRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct BailianSpeechClient: CloudSpeechSynthesizing {
    static let endpoint = URL(string: "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation")!
    static func request(text: String, language: SpeechLanguage, voice: String, key: String) throws -> URLRequest {
        try request(text: text, language: language, descriptor: .init(provider: .bailian, id: voice, model: "qwen3-tts-flash"), key: key)
    }
    static func request(text: String, language: SpeechLanguage, descriptor: SpeechVoiceDescriptor, key: String) throws -> URLRequest {
        guard !text.isEmpty, text.count <= 600 else { throw CloudSpeechError.invalidText }
        guard !key.isEmpty else { throw CloudSpeechError.missingKey }
        guard descriptor.provider == .bailian, !descriptor.id.isEmpty,
              descriptor.personal ? descriptor.model == PersonalVoice.model(for: .bailian) : (descriptor.model == "qwen3-tts-flash" && BailianVoice.available(language).contains(where: { $0.id == descriptor.id })) else { throw CloudSpeechError.response }
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": descriptor.model, "input": ["text": text, "voice": descriptor.id, "language_type": language.rawValue]])
        return request
    }
    static func audioURL(_ value: String) throws -> URL {
        guard var url = URLComponents(string: value), ["http", "https"].contains(url.scheme ?? ""),
              url.host == "dashscope-result-bj.oss-cn-beijing.aliyuncs.com", url.user == nil, url.password == nil, url.port == nil else { throw CloudSpeechError.response }
        // The official response example uses HTTP. Always fetch its signed OSS URL over TLS.
        url.scheme = "https"
        guard let result = url.url else { throw CloudSpeechError.response }; return result
    }
    func synthesize(text: String, language: SpeechLanguage, voice: String, key: String) async throws -> Data {
        try await synthesize(text: text, language: language, descriptor: .init(provider: .bailian, id: voice, model: "qwen3-tts-flash"), key: key)
    }
    func synthesize(text: String, language: SpeechLanguage, descriptor: SpeechVoiceDescriptor, key: String) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 10
        let session = URLSession(configuration: config, delegate: NoSpeechRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: Self.request(text: text, language: language, descriptor: descriptor, key: key))
        try Self.check(response)
        struct Result: Decodable {
            struct Output: Decodable { struct Audio: Decodable { let url: String }; let audio: Audio }
            let output: Output
        }
        guard let result = try? JSONDecoder().decode(Result.self, from: data) else { throw CloudSpeechError.response }
        try Task.checkCancellation()
        // Separate request: credentials are never forwarded to the audio host.
        let (audio, audioResponse) = try await session.data(from: Self.audioURL(result.output.audio.url))
        try Self.check(audioResponse)
        guard !audio.isEmpty, audio.count <= 20 * 1024 * 1024 else { throw CloudSpeechError.response }
        return audio
    }
    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw CloudSpeechError.response }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw CloudSpeechError.authorization
        case 402, 429: throw CloudSpeechError.quota
        default: throw CloudSpeechError.response
        }
    }
}
