import Foundation

struct MiniMaxSpeechClient: CloudSpeechSynthesizing {
    var endpoint = APIProvider.minimax.endpoint
    static func voices(_ language: SpeechLanguage) -> [BailianVoice] {
        let values: [(String,String)]
        switch language {
        case .chinese: values = [("Chinese (Mandarin)_Warm_Bestie", "温暖闺蜜 · Warm Bestie"), ("Chinese (Mandarin)_Gentleman", "温润男声 · Gentleman")]
        case .english: values = [("English_CalmWoman", "Calm Woman"), ("English_Trustworth_Man", "Trustworthy Man")]
        case .japanese: values = [("Japanese_KindLady", "Kind Lady"), ("Japanese_GentleButler", "Gentle Butler")]
        }
        return values.map { .init(id: $0.0, title: $0.1, languages: [language]) }
    }
    static func request(endpoint: String, text: String, language: SpeechLanguage, voice: String, key: String) throws -> URLRequest {
        try request(endpoint: endpoint, text: text, language: language, descriptor: .init(provider: .minimax, id: voice, model: "speech-2.8-turbo"), key: key)
    }
    static func request(endpoint: String, text: String, language: SpeechLanguage, descriptor: SpeechVoiceDescriptor, key: String) throws -> URLRequest {
        guard APIProvider.identify(endpoint) == .minimax, let url = URL(string: endpoint), descriptor.provider == .minimax,
              descriptor.model == "speech-2.8-turbo", !descriptor.id.isEmpty,
              descriptor.personal || voices(language).contains(where: { $0.id == descriptor.id }) else { throw SpeechConfigError.invalidAddress }
        guard !text.isEmpty, text.count < 10000 else { throw CloudSpeechError.invalidText }
        guard !key.isEmpty else { throw CloudSpeechError.missingKey }
        var request = URLRequest(url: url, timeoutInterval: 10); request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": descriptor.model, "text": text, "stream": false, "language_boost": language.rawValue, "output_format": "hex", "voice_setting": ["voice_id": descriptor.id, "speed": 1, "vol": 1], "audio_setting": ["format": "mp3", "sample_rate": 32000]])
        return request
    }
    static func decode(_ data: Data) throws -> Data {
        struct Response: Decodable {
            struct Status: Decodable { let status_code: Int }
            struct Audio: Decodable { let audio: String }
            let base_resp: Status; let data: Audio?
        }
        let result = try JSONDecoder().decode(Response.self, from: data)
        if [1004,2049].contains(result.base_resp.status_code) { throw CloudSpeechError.authorization }
        if [1002,1008].contains(result.base_resp.status_code) { throw CloudSpeechError.quota }
        guard result.base_resp.status_code == 0, let hex = result.data?.audio, !hex.isEmpty, hex.count % 2 == 0, hex.count <= 40 * 1024 * 1024 else { throw CloudSpeechError.response }
        var audio = Data(); audio.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let end = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<end], radix: 16) else { throw CloudSpeechError.response }
            audio.append(byte); index = end
        }
        return audio
    }
    func synthesize(text: String, language: SpeechLanguage, voice: String, key: String) async throws -> Data {
        try await synthesize(text: text, language: language, descriptor: .init(provider: .minimax, id: voice, model: "speech-2.8-turbo"), key: key)
    }
    func synthesize(text: String, language: SpeechLanguage, descriptor: SpeechVoiceDescriptor, key: String) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 10; configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration, delegate: NoSpeechRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data,response) = try await session.data(for: Self.request(endpoint: endpoint, text: text, language: language, descriptor: descriptor, key: key))
        try BailianSpeechClient.check(response); try Task.checkCancellation()
        return try Self.decode(data)
    }
}
