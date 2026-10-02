import Foundation

public actor CodexAppServerClient {
    public enum ClientError: LocalizedError, Sendable {
        case cliNotFound
        case notRunning
        case server(String)
        case invalidResponse

        public var errorDescription: String? {
            switch self {
            case .cliNotFound: return "Codex CLI was not found."
            case .notRunning: return "Codex app-server is not running."
            case .server(let message): return "Codex app-server: \(message)"
            case .invalidResponse: return "Codex app-server returned an invalid response."
            }
        }
    }

    private var process: Process?
    private var input: FileHandle?
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var nextID = 1
    private var buffer = Data()
    private var notificationHandler: (@Sendable (Data) -> Void)?
    private let customCLIPath: String?

    public init(customCLIPath: String? = nil) {
        self.customCLIPath = customCLIPath
    }

    deinit {
        process?.terminate()
    }

    public func setNotificationHandler(_ handler: (@Sendable (Data) -> Void)?) {
        notificationHandler = handler
    }

    public func start() async throws {
        if process?.isRunning == true { return }
        guard let path = CodexCLI.locate(customPath: customCLIPath) else { throw ClientError.cliNotFound }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["app-server"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.receive(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { [weak self] _ in
            Task { await self?.handleTermination() }
        }

        try process.run()
        self.process = process
        self.input = stdinPipe.fileHandleForWriting

        _ = try await request(method: "initialize", params: [
            "clientInfo": [
                "name": "quota_companion",
                "title": "Quota Companion",
                "version": "0.1.7",
            ],
        ])
        try sendNotification(method: "initialized", params: [:])
    }

    public func readRateLimits() async throws -> Data {
        try await start()
        return try await request(method: "account/rateLimits/read", params: nil)
    }

    public func stop() {
        input?.closeFile()
        process?.terminate()
        process = nil
        input = nil
        let continuations = pending.values
        pending.removeAll()
        continuations.forEach { $0.resume(throwing: ClientError.notRunning) }
    }

    private func request(method: String, params: [String: Any]?) async throws -> Data {
        guard let input, process?.isRunning == true else { throw ClientError.notRunning }
        let id = nextID
        nextID += 1
        var object: [String: Any] = ["method": method, "id": id]
        if let params { object["params"] = params }
        let payload = try JSONSerialization.data(withJSONObject: object) + Data([0x0A])

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try input.write(contentsOf: payload)
            } catch {
                pending[id] = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func sendNotification(method: String, params: [String: Any]) throws {
        guard let input, process?.isRunning == true else { throw ClientError.notRunning }
        let object: [String: Any] = ["method": method, "params": params]
        let payload = try JSONSerialization.data(withJSONObject: object) + Data([0x0A])
        try input.write(contentsOf: payload)
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let lineEnd = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: lineEnd)
            buffer.removeSubrange(...lineEnd)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }

            if let id = (object["id"] as? NSNumber)?.intValue, let continuation = pending.removeValue(forKey: id) {
                if let error = object["error"] as? [String: Any] {
                    continuation.resume(throwing: ClientError.server(error["message"] as? String ?? "Unknown error"))
                } else {
                    continuation.resume(returning: Data(line))
                }
            } else if object["method"] as? String == "account/rateLimits/updated" {
                notificationHandler?(Data(line))
            }
        }
    }

    private func handleTermination() {
        process = nil
        input = nil
        let continuations = pending.values
        pending.removeAll()
        continuations.forEach { $0.resume(throwing: ClientError.notRunning) }
    }
}
