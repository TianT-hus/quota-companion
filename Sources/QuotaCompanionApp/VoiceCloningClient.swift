import Foundation

enum VoiceClonePhase: Sendable { case preparing, uploading, creating, checking, previewing, deleting }
enum VoiceCloneError: Error {
    case invalidAudio, duration, tooLarge, silent, microphone, device, name, consent, unknownResult, notFound, ambiguous, busy, selected, configurationChanged, storage, service(Int), unsafe
    func message(_ c: Copybook) -> String {
        switch self {
        case .invalidAudio: c.text("无法读取音频，请选择有效的 WAV、MP3 或 M4A。", "Choose a decodable WAV, MP3 or M4A file.")
        case .duration: c.text("音频时长不符合此平台要求，请重录或选择其他文件。", "The duration is outside this provider’s limits. Record again or choose another file.")
        case .tooLarge: c.text("音频文件过大，请选择符合平台大小限制的文件。", "The audio exceeds this provider’s file-size limit.")
        case .silent: c.text("音量过低或可听声音不足 3 秒，请靠近麦克风重新录制。此检查不识别人声。", "Audio is too quiet or has less than 3 audible seconds. Move closer and record again. This check does not recognize speech.")
        case .microphone: c.text("未获得麦克风权限。可在系统设置中允许，或直接导入音频。", "Microphone access is unavailable. Allow it in System Settings or import audio instead.")
        case .device: c.text("录音设备不可用或已断开，请重新选择设备并录制。", "The input device is unavailable or disconnected. Select a device and record again.")
        case .name: c.text("名称需为 1～30 个字符，不能全为空白。", "Use a name with 1–30 characters, not only spaces.")
        case .consent: c.text("请先确认声音授权、上传和费用说明。", "Confirm voice authorization, upload and billing first.")
        case .unknownResult: c.text("创建结果待确认。请查询结果，不要再次提交，以免重复创建或计费。", "Creation result is uncertain. Check its status before submitting again to avoid duplicate charges.")
        case .notFound: c.text("暂未查询到该音色。请稍后再查询；确认失败前不会再次创建。", "The voice was not found yet. Check again later; creation will not be repeated automatically.")
        case .ambiguous: c.text("查询到多个可能结果，请在平台控制台核对；不会自动选用或删除。", "Multiple possible results were found. Check the provider console; none will be selected or deleted automatically.")
        case .busy: c.text("已有声音操作正在进行，请完成或取消后再试。", "A voice operation is already running. Finish or cancel it first.")
        case .selected: c.text("请先为所有使用此音色的播报语言选择其他声音，再删除。", "Choose a replacement for every speech language using this voice before deleting it.")
        case .configurationChanged: c.text("平台配置已改变，请主动查询并重新生成试听确认归属。", "Provider configuration changed. Check the voice and generate a new preview to verify access.")
        case .storage: c.text("本地记录未保存，请重试保存；不会重新创建云端音色。", "The local record could not be saved. Retry saving; the cloud voice will not be recreated.")
        case .service(let code): c.text("平台未完成操作（代码 \(code)）。请检查账号认证、余额及音频要求，再主动重试。", "Provider rejected the operation (code \(code)). Check account verification, balance and audio requirements.")
        case .unsafe: c.text("接口或响应不符合安全要求，操作已停止。", "The endpoint or response did not meet security requirements.")
        }
    }
}
protocol VoiceCloningServicing: Sendable {
    func create(_ voice: PersonalVoice, audio: Data, endpoint: String, key: String, phase: @escaping @Sendable (VoiceClonePhase) async -> Void) async throws -> PersonalVoice
    func find(_ voice: PersonalVoice, endpoint: String, key: String) async throws -> PersonalVoice
    func delete(_ voice: PersonalVoice, endpoint: String, key: String) async throws
}

struct VoiceCloningClient: VoiceCloningServicing {
    static let bailian = URL(string: "https://dashscope.aliyuncs.com/api/v1/services/audio/tts/customization")!
    static func url(_ provider: APIProvider, endpoint: String, path: String) throws -> URL {
        guard APIProvider.identify(endpoint) == provider else { throw VoiceCloneError.unsafe }
        if provider == .bailian { return bailian }
        guard let host = URL(string: endpoint)?.host, let url = URL(string: "https://\(host)/v1/\(path)") else { throw VoiceCloneError.unsafe }
        return url
    }
    static func request(url: URL, key: String, body: [String: Any]) throws -> URLRequest {
        guard !key.isEmpty else { throw CloudSpeechError.missingKey }
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"; request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body); return request
    }
    static func qwenBody(_ voice: PersonalVoice, audio: Data) -> [String: Any] {
        ["model": "qwen-voice-enrollment", "input": ["action": "create", "target_model": voice.model, "preferred_name": voice.operationName, "audio": ["data": "data:audio/wav;base64," + audio.base64EncodedString()]]]
    }
    private func send(_ request: URLRequest) async throws -> Data {
        // Preview/QA bundles may only use an injected mock service.
        guard Bundle.main.object(forInfoDictionaryKey: "QuotaSecretaryPreview") as? Bool != true else { throw VoiceCloneError.unsafe }
        try Task.checkCancellation()
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.timeoutIntervalForResource = 180
        let session = URLSession(configuration: config, delegate: NoSpeechRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try BailianSpeechClient.check(response)
        guard data.count <= 4 * 1024 * 1024 else { throw VoiceCloneError.unsafe }
        return data
    }
    static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CloudSpeechError.response }
        if let status = value["base_resp"] as? [String: Any], let code = status["status_code"] as? Int, code != 0 { throw VoiceCloneError.service(code) }
        if value["code"] != nil { throw CloudSpeechError.response }
        return value
    }
    func create(_ voice: PersonalVoice, audio: Data, endpoint: String, key: String, phase: @escaping @Sendable (VoiceClonePhase) async -> Void) async throws -> PersonalVoice {
        var result = voice
        if voice.provider == .bailian {
            await phase(.creating)
            let data = try await send(Self.request(url: Self.url(.bailian, endpoint: endpoint, path: ""), key: key, body: Self.qwenBody(voice, audio: audio)))
            let object = try Self.object(data)
            guard let output = object["output"] as? [String: Any], let id = output["voice"] as? String, !id.isEmpty,
                  output["target_model"] as? String == voice.model else { throw CloudSpeechError.response }
            result.remoteID = id
            if output["fallback_mode"] as? Bool == true { result.warning = "fallback" }
        } else {
            await phase(.uploading)
            let boundary = "zhaoxi-" + UUID().uuidString
            var request = try Self.request(url: Self.url(.minimax, endpoint: endpoint, path: "files/upload"), key: key, body: [:])
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"purpose\"\r\n\r\nvoice_clone\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"sample.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8)
            body.append(audio); body.append(Data("\r\n--\(boundary)--\r\n".utf8)); request.httpBody = body
            let uploaded = try Self.object(await send(request))
            guard let file = uploaded["file"] as? [String: Any], let raw = file["file_id"], let id = Int64(String(describing: raw)) else { throw CloudSpeechError.response }
            try Task.checkCancellation(); await phase(.creating)
            let created = try Self.object(await send(Self.request(url: Self.url(.minimax, endpoint: endpoint, path: "voice_clone"), key: key, body: ["file_id": id, "voice_id": voice.operationName, "need_noise_reduction": false, "need_volume_normalization": false])))
            guard created["input_sensitive"] as? Bool != true else { throw VoiceCloneError.service(2038) }
            result.remoteID = voice.operationName
        }
        result.state = .created; return result
    }
    func find(_ voice: PersonalVoice, endpoint: String, key: String) async throws -> PersonalVoice {
        var matches: [String] = []
        if voice.provider == .bailian {
            for page in 0..<100 {
                let data = try await send(Self.request(url: Self.url(.bailian, endpoint: endpoint, path: ""), key: key, body: ["model": "qwen-voice-enrollment", "input": ["action": "list", "page_index": page, "page_size": 100]]))
                guard let output = try Self.object(data)["output"] as? [String: Any], let rows = output["voice_list"] as? [[String: Any]] else { throw CloudSpeechError.response }
                for row in rows {
                    if let id = row["voice"] as? String, row["target_model"] as? String == voice.model,
                       (voice.remoteID.map { $0 == id } ?? id.contains("-\(voice.operationName)-")) { matches.append(id) }
                }
                if rows.count < 100 || (page + 1) * 100 >= (output["total_count"] as? Int ?? Int.max) { break }
            }
        } else {
            let data = try await send(Self.request(url: Self.url(.minimax, endpoint: endpoint, path: "get_voice"), key: key, body: ["voice_type": "voice_cloning"]))
            guard let rows = try Self.object(data)["voice_cloning"] as? [[String: Any]] else { throw CloudSpeechError.response }
            matches = rows.compactMap { $0["voice_id"] as? String }.filter { $0 == voice.remoteID }
        }
        guard matches.count == 1 else { throw matches.isEmpty ? VoiceCloneError.notFound : VoiceCloneError.ambiguous }
        var result = voice; result.remoteID = matches[0]; result.state = .created; return result
    }
    func delete(_ voice: PersonalVoice, endpoint: String, key: String) async throws {
        guard let id = voice.remoteID, voice.state != .pending else { throw VoiceCloneError.unknownResult }
        let body: [String: Any] = voice.provider == .bailian
            ? ["model": "qwen-voice-enrollment", "input": ["action": "delete", "voice": id]]
            : ["voice_type": "voice_cloning", "voice_id": id]
        _ = try Self.object(await send(Self.request(url: Self.url(voice.provider, endpoint: endpoint, path: "delete_voice"), key: key, body: body)))
    }
}
