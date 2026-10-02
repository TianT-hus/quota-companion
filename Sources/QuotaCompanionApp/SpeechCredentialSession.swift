@preconcurrency import AppKit

enum CredentialPresence {
    case saved, missing, unknown
    func title(_ c: Copybook) -> String {
        switch self {
        case .saved: c.text("已保存到钥匙串", "Saved in Keychain")
        case .missing: c.text("未保存", "Not saved")
        case .unknown: c.text("暂时无法确认", "Unable to verify right now")
        }
    }
}

/// Credentials never enter preferences, diagnostics or test snapshots.
@MainActor final class SpeechCredentialSession {
    private struct Entry { let key: String; let expires: Date }
    private var cache: [APIProvider: Entry] = [:]
    private var pending: [APIProvider: (UUID, Task<String, Error>)] = [:]
    private var epoch = UUID()
    private var observers: [NSObjectProtocol] = []
    private var expiryTask: Task<Void, Never>?
    let lifetime: TimeInterval
    init(lifetime: TimeInterval = 300) {
        self.lifetime = lifetime
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.willSleepNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.clear() }
            })
        }
        observers.append(DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.clear() }
        })
    }
    deinit {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        expiryTask?.cancel()
    }
    func clear() {
        epoch = UUID(); cache.removeAll(); expiryTask?.cancel(); expiryTask = nil
        for (_, task) in pending.values { task.cancel() }
        pending.removeAll()
    }
    func read(provider: APIProvider, interaction: Bool, injected: (any SpeechCredentials)?) async throws -> String {
        if let value = cache[provider], value.expires > .now { return value.key }
        cache[provider] = nil
        if let (_, task) = pending[provider] {
            let generation = epoch
            let key = try await task.value
            guard epoch == generation, !Task.isCancelled, !task.isCancelled else { throw CancellationError() }
            return key
        }
        let token = UUID(), generation = epoch
        let task: Task<String, Error>
        if let injected { task = Task { try injected.read() } }
        else if Bundle.main.object(forInfoDictionaryKey: "QuotaSecretaryPreview") as? Bool == true {
            task = Task { throw CloudSpeechError.missingKey }
        } else { task = Task.detached { try KeychainSpeechCredentials(provider: provider).read(allowInteraction: interaction) } }
        pending[provider] = (token, task)
        defer { if pending[provider]?.0 == token { pending[provider] = nil } }
        let key = try await task.value
        guard epoch == generation, !Task.isCancelled, !task.isCancelled else { throw CancellationError() }
        cache[provider] = Entry(key: key, expires: Date().addingTimeInterval(lifetime))
        expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: .seconds(lifetime)) } catch { return }
            clear()
        }
        return key
    }
}
